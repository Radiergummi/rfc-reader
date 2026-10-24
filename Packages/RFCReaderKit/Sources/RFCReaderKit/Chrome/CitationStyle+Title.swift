import Foundation
import RFCKit

extension CitationStyle {
  /// The style's name in the Cite menu. RFCKit's `displayName` stays English, as
  /// RFCKit has no catalog. BibTeX and URL are names, not language: no keys.
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .short: String(kit: "Short", locale: locale)
    case .full: String(kit: "Full Citation", locale: locale)
    case .markdown: String(kit: "Markdown Link", locale: locale)
    case .bibtex: "BibTeX"
    case .url: "URL"
    case .xml2rfc: String(kit: "xml2rfc Reference", locale: locale)
    }
  }
}

extension LinkSite {
  /// What Settings calls the site (#712): its address, which is a name, not
  /// language, but for the app's own.
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .rfcEditor: "rfc-editor.org"
    case .datatracker: "datatracker.ietf.org"
    case .ietf: "ietf.org"
    case .app: String(kit: "RFC Reader (rfc://)", locale: locale)
    }
  }
}
