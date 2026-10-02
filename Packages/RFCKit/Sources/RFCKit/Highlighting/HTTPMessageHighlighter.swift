import Foundation

/// The head of an HTTP message, a line at a time: a start line or none, then fields.
///
/// Written for RFCs rather than translated: neither Pygments' HTTP lexer, which works
/// through callbacks, nor Chroma's, which is code, is a table, and both expect a
/// message that starts with a start line, which 221 of the corpus's 520 do not.
enum HTTPLexer {
  /// RFC 9112's request line, set in from the margin or not.
  static let requestLine =
    #"^([ \t]*+)([A-Z][A-Z-]*+)([ \t]++)([^\s]++)([ \t]++)(HTTP/[0-9](?:\.[0-9])?)[ \t]*+$"#
  /// RFC 9112's status line.
  static let statusLine = #"^([ \t]*+)(HTTP/[0-9](?:\.[0-9])?)([ \t]++)([0-9]{3})([^\n]*+)$"#
  /// A status line without its version, as some RFCs abbreviate one.
  static let bareStatusLine = #"^([ \t]*+)([1-5][0-9]{2})([ \t]++[^\n]*+)$"#
  /// An HTTP/2 or HTTP/3 pseudo-header field, as RFCs list them: `:method = GET`.
  static let pseudoHeaderLine = #"^([ \t]*+)(:[a-z]++)([ \t]*+[:=])([^\n]*+)$"#
  /// A field line: a token, a colon, a value.
  static let fieldLine = #"^([ \t]*+)([!#$%&'*+.^_`|~0-9A-Za-z-]++)(:)([^\n]*+)$"#

  static let headStates: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(requestLine, groups: [.plain, .keyword, .plain, .string, .plain, .keyword]),
      Lexer.Rule(statusLine, groups: [.plain, .keyword, .plain, .number, .plain]),
      Lexer.Rule(bareStatusLine, groups: [.plain, .number, .plain]),
      Lexer.Rule(pseudoHeaderLine, groups: [.plain, .name, .punctuation, .plain]),
      Lexer.Rule(fieldLine, groups: [.plain, .name, .punctuation, .plain]),
      Lexer.Rule(#"[^\n]++"#, .plain),
      Lexer.Rule(#"\n"#, .plain),
    ]
  ]

  static let head = Lexer.defined(headStates)

  private static let startLine = Lexer.expression(
    "(?:\(requestLine))|(?:\(statusLine))", options: .anchorsMatchLines)

  /// Whether `line` starts a message: a request or status line with its version.
  static func isStartLine(_ line: String) -> Bool {
    startLine.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
  }

  static let contentType = Lexer.expression(
    #"^[ \t]*+content-type[ \t]*+:[ \t]*+([^\n]*+)$"#,
    options: [.anchorsMatchLines, .caseInsensitive])
}

/// An HTTP message, or several, as RFCs set them: a head lexed by `HTTPLexer`, and
/// a body lexed as its `Content-Type` says, where it names JSON or XML, and plain
/// otherwise.
struct HTTPMessageHighlighter: Highlighter {
  /// One message's head and body, as ranges of the block. The blank line that ends
  /// a head belongs to its body.
  struct Message: Equatable {
    var head: NSRange
    var body: NSRange?
  }

  func tokens(in text: String) -> [SyntaxToken] {
    let source = NSString(string: text)
    var output = TokenRun()
    for message in Self.messages(in: source) {
      let head = source.substring(with: message.head)
      output.append(contentsOf: HTTPLexer.head.tokens(in: head), offset: message.head.location)
      guard let body = message.body else { continue }
      let bodyText = source.substring(with: body)
      let tokens =
        Self.bodyHighlighter(forHead: head)?.tokens(in: bodyText)
        ?? [SyntaxToken(range: NSRange(location: 0, length: body.length), kind: .plain)]
      output.append(contentsOf: tokens, offset: body.location)
    }
    return output.tokens
  }

  /// The block split into messages, which together cover it. A message's head runs
  /// to its first blank line, and its body from there to a start line after a
  /// blank line; a start line inside a head starts the next message too.
  static func messages(in text: NSString) -> [Message] {
    guard text.length > 0 else { return [] }
    var messages: [Message] = []
    var start = 0
    var bodyStart: Int?
    var previousLineBlank = false
    var position = 0
    while position < text.length {
      let line = text.lineRange(for: NSRange(location: position, length: 0))
      let content = text.substring(with: line)
      let blank = content.allSatisfy(\.isWhitespace)
      if line.location > start, bodyStart == nil || previousLineBlank,
        HTTPLexer.isStartLine(content)
      {
        messages.append(message(from: start, bodyStart: bodyStart, to: line.location))
        start = line.location
        bodyStart = nil
      } else if bodyStart == nil, blank {
        bodyStart = line.location
      }
      previousLineBlank = blank
      position = NSMaxRange(line)
    }
    messages.append(message(from: start, bodyStart: bodyStart, to: text.length))
    return messages
  }

  private static func message(from start: Int, bodyStart: Int?, to end: Int) -> Message {
    let headEnd = bodyStart ?? end
    return Message(
      head: NSRange(location: start, length: headEnd - start),
      body: bodyStart.map { NSRange(location: $0, length: end - $0) })
  }

  /// What the head's `Content-Type` names, where it names a language other than
  /// HTTP itself.
  private static func bodyHighlighter(forHead head: String) -> (any Highlighter)? {
    let source = NSString(string: head)
    guard
      let match = HTTPLexer.contentType.firstMatch(
        in: head, range: NSRange(location: 0, length: source.length)),
      let type = ArtworkType.canonical(source.substring(with: match.range(at: 1))),
      let language = Lexers.language(of: type), language != .httpMessage
    else { return nil }
    return Lexers.highlighter(for: language)
  }
}
