import Foundation
import RFCKit

/// What a force click on a reference shows (#29). macOS so far; a long press on
/// iOS is to show the same, and still shows the card.
///
/// Safari's link preview, for documents: the document the reference names, at the
/// place it names, readable and scrollable — not a summary of it. The one exception
/// is a bibliography entry that names no RFC (an ISO standard, a draft): there is
/// nothing of ours to show, and no web view to show it in, so it keeps its card.
///
/// A sibling of `LinkDestination` rather than a case of it: a click follows the
/// link, and where it goes depends on the modifiers; a preview only looks, from
/// wherever the reader is.
public enum LinkPreview: Equatable, Sendable {
  /// `id`, opened at `place` — a section number or an anchor, which the preview
  /// resolves the way the reader does — or at the top.
  case document(DocumentID, place: String?)
  /// The bibliography entry with this anchor, as the reference card.
  case card(String)

  /// Nil for a URL the reader does not own: a link to the web previews nothing. A
  /// BCP, STD or FYI previews its first member RFC, as a click on it opens that one
  /// (`NavigationModel.open`): the series has no document of its own to fetch.
  public static func resolve(
    _ url: URL, from currentDocument: DocumentID, in index: RFCIndex?
  ) -> LinkPreview? {
    if let anchor = DocumentTextBuilder.anchor(from: url) {
      return .document(currentDocument, place: anchor)
    }
    if let entry = DocumentTextBuilder.reference(from: url) {
      return .card(entry)
    }
    guard let link = RFCLink(url: url) else { return nil }
    if link.id.series != .rfc, let first = index?.series(link.id)?.members.first {
      return .document(first, place: link.section)
    }
    return .document(link.id, place: link.section)
  }
}
