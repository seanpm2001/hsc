module parse.lex;

import std.stdio : stdout;
import std.conv;
import std.format : format;
import std.range;
import std.range.primitives;

enum CellType {
  EOF,
  Symbol,
  Number,
  List,
  Proc,
  Lambda,
}

//                                "!#$%&|*+-/:<=>?@^_~"
enum Delimeters {
  OpenParen = '(',
  CloseParen = ')',

}

enum TokenType {
  EOF,
  Identifier,
  Keyword,
  Error,
  Number,
  Space,
  Text,

  OpenParen,
  CloseParen,
  Bang,
  Hash,
  Dollar,
  Percent,
  Amersand,
  Pipe,
  Asterisk,
  Plus,
  Minus,
  Slash,
  Colon,
  OpenAngleBracket,
  Equals,
  RightAngleBracket,
  QuestionMark,
  At,
  Caret,
  Underscore,
  Tilde,
}

/**
 * Position inside of a file
 */
struct Position {
  size_t line;
  size_t col;
  size_t index;

  string toString() {
    return format("%d:%d", line, col);
  }
}

/**
 * A lexed token
 */
struct Token {
  TokenType type;
  string value;
  Position position;

  string toString() {
    switch (type) {
    case TokenType.EOF:
      return "EOF";
    case TokenType.Error:
      return value;
    default:
      return format("%s \"%s\": line %s", type, value, position);
    }
  }
}

class Lexer {
  // used for debugging
  immutable(string) name;
  string input;
  Token[] items; // emitted items
  void delegate() state; // current state
  size_t position = 0; // current position in the input
  size_t start = 0; // position of wherever we started lexing the last item
  size_t lastPosition; // position of the last item we lexed
  size_t parenDepth = 0; // depth of parenthesis

  enum : char {
    eof = cast(char)-1,
    openParen = '(',
    closeParen = ')',
    comment = ';'
  };

  this(string name, string input) {
    this.name = name;
    this.input = input;
    this.state = &lexText;
  }

  /**
   * Adds a pre-built item to the lexed items list
   */
  void addItem(Token item) {
    items ~= item;

    start = position;
  }

  /**
   * Adds an Token to the lexed items list
   */
  void addItem(TokenType item) {
    addItem(Token(item, input[start..position], currentPosition()));
  }

  /**
   * Sets the lexer's current token start position to position, ignoring all characters
   * between position and start when this is called
   */
  void ignore() {
    start = position;
  }

  /**
   * Begins lexing
   */
  void run() {
    while (state !is null) {
      state();
    }
  }

  /**
   * Consumes and returns the next character in the buffer. Returns EOF if we've gone outside the buffer
   */
  char next() {
    if (position >= input.length) {
      return eof;
    }

    // this is the type of thing you're told not to do
    return input[position++];
  }

  /**
   * Returns but does not consume the next character in the buffer
   */
  char peek() {
    auto n = next();
    backup();

    return n;
  }

  /**
   * Backs up the buffer by one character
   */
  void backup() {
    position--;
  }

  /**
   * Lexes top-level text. This will usually skip whitespace, encounter EOF, or set the state to lexing a comment /
   * script
   */
  void lexText() {
  loop: while (true) {
      switch (next()) {
      case comment:
        state = &lexComment;
        return;
      case openParen:
        state = &lexOpenParen;
        return;
      case eof:
        state = null;
        return;
      default:
        break;
      }
    }
  }

  /**
   * Positions the buffer to wherever the first non-CR/LF character is
   */
  void skipEOL() {
    char nextc = next();
    while (nextc == '\r' || nextc == '\n') {
      nextc = next();
    }

    backup();

    ignore();
  }

  /**
   * Lexes comments and does not emit any tokens
   */
  void lexComment() {
    // consume characters until we hit EOL
    char nextc;
    while(true) {
      nextc = next();

      if (nextc == eof) {
        state = null;
        return;
      } else if (isEndOfLine(nextc)) {
        skipEOL();
        break;
      }
    }

    ignore();

    if (parenDepth > 0) {
      state = &lexInsideParens;
    } else {
      state = &lexText;
    }
  }

  void lexOpenParen() {
    addItem(TokenType.OpenParen);
    parenDepth++;

    // check for a comment since these can go here
    if (peek() == comment) {
      state = &lexComment;
      return;
    }


    state = &lexInsideParens;
  }

  void lexCloseParen() {
    addItem(TokenType.CloseParen);
    parenDepth--;

    if (parenDepth == 0) {
      state = &lexText;
    } else {
      state = &lexInsideParens;
    }
  }

  void lexInsideParens() {
    // Parens signify a function call, so it will be something like:
    // (;comment
    // function-name argument ; another comment
    // )
    // and that can be recursive

    immutable(char) nextChar = next();
    if (nextChar == comment) {
      state = &lexComment;
      return;
    } else if (isSpace(nextChar)) {
      state = &lexSpace;
      return;
    } else if (nextChar == openParen) {
      state = &lexOpenParen;
      return;
    } else if (nextChar == closeParen) {
      state = &lexCloseParen;
      return;
    } else if (isIdentifierChar(nextChar)) {
      state = &lexIdentifier;
      return;
    } else if (nextChar == eof) {
      error("unclosed open paren");
    } else {
      error("unrecognized character \"" ~ nextChar ~"\"");
    }
  }

  void lexSpace() {
    while (isSpace(peek())) {
      if (next() == eof) {
        state = null;
        return;
      }
    }

    addItem(TokenType.Space);

    state = &lexInsideParens;
  }

  void lexIdentifier() {
    while(true) {
      auto nextChar = next();

      if (isIdentifierChar(nextChar)) {
        // do nothing
      } else {
        backup();

        string word = input[start..position];

        // do something with word later
        addItem(TokenType.Identifier);

        break;
      }
    }

    state = &lexInsideParens;
  }

  void error(string message) {
    addItem(Token(TokenType.Error, message, currentPosition()));

    state = null;
  }

  Position currentPosition() {
    import std.range : retro;
    import std.algorithm.searching : count, countUntil;

    auto charsUntilPosition = input[0..position];

    size_t lines = count(charsUntilPosition, '\n');
    size_t indexOfLastLinebreak = countUntil(charsUntilPosition, '\n');

    // countUntil is 1-indexed so we -1 since columns should be 0-indexed
    return Position(lines, (start - indexOfLastLinebreak) - 1, start);
  }

  bool isEndOfLine(char c) {
    return c == '\r' || c == '\n';
  }

  bool isSpace(char c) {
    return c == '\t' || c == ' ' || isEndOfLine(c);
  }

  bool isIdentifierChar(char c) {
    import core.stdc.ctype : isalnum;
    import std.algorithm.searching : canFind;

    return canFind(['_', '!', '/', '+', '=', '*', '-', '<', '>'], c) || isalnum(cast(int)c) != 0;
  }

  unittest {
    Lexer lex = new Lexer("input", ";foo hooo\n(foo (+ (x) y))");
    lex.run();

    std.stdio.stdout.writeln(lex.items);
    assert(lex.items == [
                         Token(TokenType.OpenParen, "(", Position(1, 0, 10)),
                         Token(TokenType.Identifier, "foo", Position(1, 1, 11)),
                         Token(TokenType.Space, " ", Position(1, 4, 14)),
                         Token(TokenType.OpenParen, "(", Position(1, 5, 15)),
                         Token(TokenType.Identifier, "+", Position(1, 6, 16)),
                         Token(TokenType.Space, " ", Position(1, 7, 17)),
                         Token(TokenType.OpenParen, "(", Position(1, 8, 18)),
                         Token(TokenType.Identifier, "x", Position(1, 9, 19)),
                         Token(TokenType.CloseParen, ")", Position(1, 10, 20)),
                         Token(TokenType.Space, " ", Position(1, 11, 21)),
                         Token(TokenType.Identifier, "y", Position(1, 12, 22)),
                         Token(TokenType.CloseParen, ")", Position(1, 13, 23)),
                         Token(TokenType.CloseParen, ")", Position(1, 14, 24)),
                         ]);
  }
}
