import Foundation

/// Which highlighter a block's type names: the one place it is decided.
public enum Lexers {
  public enum Language: Sendable, Hashable {
    case json
    case xml
    case httpMessage
  }

  /// The canonical type names a language is named by, exactly.
  static let names: [String: Language] = [
    "json": .json, "application/json": .json,
    "xml": .xml, "application/xml": .xml, "text/xml": .xml,
    "http-message": .httpMessage, "message/http": .httpMessage,
  ]

  /// The structured suffixes a language is named by, where no name is: any
  /// `+json` or `+xml` type.
  static let suffixes: [String: Language] = ["json": .json, "xml": .xml]

  public static var claimedNames: Set<String> { Set(names.keys) }
  public static var claimedSuffixes: Set<String> { Set(suffixes.keys) }

  /// Over this, in UTF-16 code units, a block is not highlighted: above the corpus's
  /// largest highlighted block, 53 KB in RFC 8727, and a bound on what a
  /// pathological one can cost.
  public static let sizeLimit = 65_536

  /// An exact name wins over a suffix.
  public static func language(of type: ArtworkType) -> Language? {
    names[type.name] ?? type.suffix.flatMap { suffixes[$0] }
  }

  public static func highlighter(for language: Language) -> any Highlighter {
    switch language {
    case .json: JSONLexer.lexer
    case .xml: XMLLexer.lexer
    case .httpMessage: HTTPMessageHighlighter()
    }
  }

  /// `text`'s tokens, or nil where its type names no language or it is over the
  /// size limit.
  public static func highlight(_ text: String, as type: ArtworkType) -> [SyntaxToken]? {
    guard text.utf16.count <= sizeLimit, let language = language(of: type) else { return nil }
    return highlighter(for: language).tokens(in: text)
  }
}
