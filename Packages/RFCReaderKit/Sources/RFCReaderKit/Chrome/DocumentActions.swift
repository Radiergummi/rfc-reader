import Foundation
import RFCKit

/// What the reader's toolbars *say* when they act on the document on screen.
///
/// Both platforms offer the same three actions — bookmark it, cite it, link to the
/// section being read — and until now each wrote its own answer to what they mean.
/// The two had already drifted: a new bookmark stored a different title depending on
/// which toolbar made it, because one of them knew a fallback the other did not.
///
/// So the wording lives here, once, where it can be tested. The App target keeps the
/// half that is genuinely platform work — reading and writing SwiftData, reaching the
/// pasteboard — and asks these for the string to use.
public enum DocumentActions {
  /// The title to file a new bookmark under.
  ///
  /// The index is the first source because it is the library's own name for the
  /// document and the same one the list shows. It does not cover everything,
  /// though — an RFC opened by number before the index has loaded, or one missing
  /// from it — and in that case the document has just been parsed and its header
  /// says so. `displayName` is the last resort and always works: `RFC 9110`.
  public static func bookmarkTitle(
    metadata: RFCMetadata?,
    documentTitle: String?,
    id: DocumentID
  ) -> String {
    metadata?.title ?? documentTitle ?? id.displayName
  }

  /// Whether the document is bookmarked, in words: what the Bookmark button, whose
  /// label stays "Bookmark", says beside its glyph to VoiceOver (#278).
  public static func bookmarkState(isBookmarked: Bool, locale: Locale = .interface) -> String {
    isBookmarked
      ? String(kit: "Bookmarked", locale: locale) : String(kit: "Not bookmarked", locale: locale)
  }

  /// The Mac's Bookmark button's tooltip (#761): what a click does, as every other
  /// tooltip says, then the state, which VoiceOver reads from it (#278). One
  /// sentence pair per state, not the command and the state put together. A
  /// document, not an RFC: a BCP, STD or FYI read as itself is bookmarked as itself.
  public static func bookmarkTooltip(isBookmarked: Bool, locale: Locale = .interface) -> String {
    isBookmarked
      ? String(kit: "Remove Bookmark. This document is bookmarked.", locale: locale)
      : String(kit: "Bookmark this document. It is not bookmarked.", locale: locale)
  }

  /// What the ⌘D command and a row's bookmark action are called: what they will do,
  /// on the Mac's Edit menu and the iPad's alike, where the button's label stays
  /// "Bookmark" (#278).
  public static func bookmarkCommand(isBookmarked: Bool, locale: Locale = .interface) -> String {
    isBookmarked
      ? String(kit: "Remove Bookmark", locale: locale) : String(kit: "Bookmark", locale: locale)
  }

  /// What a list row's Keep Offline item, and the Info pane's toggle to VoiceOver,
  /// are called: what they will do (#358).
  public static func keepOfflineCommand(isKept: Bool, locale: Locale = .interface) -> String {
    isKept
      ? String(kit: "Stop Keeping Offline", locale: locale)
      : String(kit: "Keep Offline", locale: locale)
  }

  /// The SF Symbol beside `keepOfflineCommand`.
  public static func keepOfflineSymbol(isKept: Bool) -> String {
    isKept ? "xmark.circle" : "arrow.down.circle"
  }

  /// What the document is called, under its designation in the reader's title.
  ///
  /// The same sources as `bookmarkTitle`, in the same order, without its last
  /// resort: the designation is already the title above it.
  public static func subtitle(metadata: RFCMetadata?, documentTitle: String?) -> String? {
    metadata?.title ?? documentTitle
  }

  /// The citation to put on the pasteboard, linking to `site`: of `section` where
  /// the style names one (`CitationStyle.citesSections`), and of the document
  /// otherwise.
  public static func citation(
    _ cited: CitedDocument,
    section: String?,
    style: CitationStyle,
    site: LinkSite = .rfcEditor
  ) -> String {
    CitationFormatter.cite(
      cited, section: style.citesSections ? section : nil, style: style, site: site)
  }

  /// What Share hands out for a document (#712): its page on `site`, a series as
  /// itself, as the tab opened it (#656).
  public static func shareLink(id: DocumentID, site: LinkSite) -> URL {
    site.url(for: RFCLink(id: id))
  }

  /// The shareable link to the place being read, as a string for the pasteboard.
  ///
  /// The link Settings chose, the web's by default rather than the app's own
  /// `rfc://`: this is copied to be pasted somewhere else, and the reader opens an
  /// rfc-editor.org link anyway.
  public static func sectionLink(
    id: DocumentID, section: String?, site: LinkSite = .rfcEditor
  ) -> String {
    site.url(for: RFCLink(id: id, section: section)).absoluteString
  }
}
