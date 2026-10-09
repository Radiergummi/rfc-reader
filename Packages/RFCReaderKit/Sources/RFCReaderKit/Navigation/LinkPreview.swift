import Foundation
import RFCKit

/// What a force click (macOS) or a long press (iOS) on a reference shows (#29).
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

  /// The document preview's size where there is room for it: macOS's popover, or
  /// an iPad's context menu.
  public static let documentSize = CGSize(width: 560, height: 620)

  /// The document preview's size inside `available`, a context menu's screen. It
  /// keeps the 16 pt a context menu's preview keeps from the screen's edges, and
  /// no more than 60 % of its height, so the menu under it fits without UIKit
  /// shrinking the preview to make room.
  public static func documentSize(fitting available: CGSize) -> CGSize {
    CGSize(
      width: min(documentSize.width, available.width - 2 * 16),
      height: min(documentSize.height, (available.height * 0.6).rounded(.down)))
  }

  /// What pressing `reference`, which links to `url`, previews. A section of an
  /// entry outside the series links to the section's page on the web, and previews
  /// the entry's card all the same, as a citation of the whole entry does (#473).
  public static func resolve(
    _ reference: CrossReference, linkedTo url: URL, from currentDocument: DocumentID,
    in index: RFCIndex?
  ) -> LinkPreview? {
    if case .entrySection(let entry, _, _, _) = reference.target {
      return .card(entry)
    }
    return resolve(url, from: currentDocument, in: index)
  }

  /// Nil for a URL the reader does not own: a link to the web previews nothing. A
  /// BCP, STD or FYI previews its first member RFC, as a click on it opens that one
  /// (`NavigationModel.open`): the series has no document of its own to fetch.
  public static func resolve(
    _ url: URL, from currentDocument: DocumentID, in index: RFCIndex?
  ) -> LinkPreview? {
    if let anchor = ReaderLinkScheme.anchor(from: url) {
      return .document(currentDocument, place: anchor)
    }
    if let entry = ReaderLinkScheme.reference(from: url) {
      return .card(entry)
    }
    guard let link = RFCLink(url: url) else { return nil }
    if link.id.series != .rfc, let first = index?.series(link.id)?.members.first {
      return .document(first, place: link.place)
    }
    return .document(link.id, place: link.place)
  }
}
