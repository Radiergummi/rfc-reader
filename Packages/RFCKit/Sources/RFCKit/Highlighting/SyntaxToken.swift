import Foundation

/// What a token is, never how it looks: the reader's theme decides that.
public enum TokenKind: Sendable, Hashable, CaseIterable {
  case keyword
  case string
  case number
  case comment
  /// A JSON key, an XML tag, an HTTP field name.
  case name
  case attribute
  case punctuation
  case plain
}

/// A run of a block's text and what it is. The range is UTF-16, relative to the
/// text highlighted, as `NSAttributedString` counts.
public struct SyntaxToken: Sendable, Hashable {
  public var range: NSRange
  public var kind: TokenKind

  public init(range: NSRange, kind: TokenKind) {
    self.range = range
    self.kind = kind
  }
}

/// Turns a block's text into tokens that cover it exactly once, in order, with no
/// empty token. Never fails: what it cannot read is `plain`.
protocol Highlighter: Sendable {
  func tokens(in text: String) -> [SyntaxToken]
}

/// Tokens as a highlighter collects them: empty runs are dropped and a run that
/// continues the one before it, of the same kind, is merged into it, so a block has
/// as few attribute runs as its colors need.
struct TokenRun {
  private(set) var tokens: [SyntaxToken] = []

  mutating func append(_ range: NSRange, _ kind: TokenKind) {
    guard range.length > 0 else { return }
    if let last = tokens.last, last.kind == kind, NSMaxRange(last.range) == range.location {
      tokens[tokens.count - 1].range.length += range.length
    } else {
      tokens.append(SyntaxToken(range: range, kind: kind))
    }
  }

  /// `other`'s tokens, moved `offset` code units on: a part of the text highlighted
  /// on its own, such as an HTTP message's body.
  mutating func append(contentsOf other: [SyntaxToken], offset: Int) {
    for token in other {
      append(
        NSRange(location: token.range.location + offset, length: token.range.length), token.kind)
    }
  }
}
