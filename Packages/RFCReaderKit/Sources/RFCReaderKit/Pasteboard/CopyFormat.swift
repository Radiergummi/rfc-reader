import Foundation

/// What Copy puts on the pasteboard (#712). Edit ▸ Copy As offers each of them,
/// whichever Copy is set to.
public enum CopyFormat: String, CaseIterable, Sendable, Identifiable {
  /// The selection as it reads, in every flavor a target might take
  /// (`PasteboardContent.selection`): what Copy did before the setting.
  case text
  /// Copy as Quote's (`QuoteCitation`): the selection quoted, with its citation.
  case quote

  public var id: String { rawValue }

  /// What Settings, and Edit ▸ Copy As, call it.
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .text: String(kit: "Text", locale: locale)
    case .quote: String(kit: "Quote with Citation", locale: locale)
    }
  }
}
