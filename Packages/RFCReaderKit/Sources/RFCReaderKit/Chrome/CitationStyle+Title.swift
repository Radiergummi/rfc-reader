import Foundation
import RFCKit

extension CitationStyle {
  /// The style's name in the Cite menu. RFCKit's `displayName` stays English, as
  /// RFCKit has no catalog.
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .short: String(kit: "Short", locale: locale)
    case .full: String(kit: "Full citation", locale: locale)
    case .markdown: String(kit: "Markdown link", locale: locale)
    case .bibtex: String(kit: "BibTeX", locale: locale)
    case .url: String(kit: "URL", locale: locale)
    }
  }
}
