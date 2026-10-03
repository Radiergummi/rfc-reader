import Foundation

@testable import RFCKit

extension Array where Element == SyntaxToken {
  /// Whether these tokens cover `text` exactly once, in order, with no empty token:
  /// the invariant every highlighter keeps.
  func cover(_ text: String) -> Bool {
    var position = 0
    for token in self {
      guard token.range.location == position, token.range.length > 0 else { return false }
      position = NSMaxRange(token.range)
    }
    return position == NSString(string: text).length
  }

  /// The kind of the one token that holds all of the first occurrence of `fragment`
  /// in `text`, or nil where no single token does.
  func kind(of fragment: String, in text: String) -> TokenKind? {
    let range = NSString(string: text).range(of: fragment)
    guard range.location != NSNotFound else { return nil }
    return first {
      $0.range.location <= range.location && NSMaxRange(range) <= NSMaxRange($0.range)
    }?.kind
  }

  /// The text of every token of `kind`, in order.
  func text(of kind: TokenKind, in text: String) -> [String] {
    let source = NSString(string: text)
    return filter { $0.kind == kind }.map { source.substring(with: $0.range) }
  }
}
