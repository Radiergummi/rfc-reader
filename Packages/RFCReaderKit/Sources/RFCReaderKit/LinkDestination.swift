import Foundation
import RFCKit

/// Where a click on a reference goes, decided before anything moves.
///
/// A pure function of the URL, the document on screen and the modifiers, so the three
/// rules that make a click feel right — an anchor never leaves the document, a section
/// of the document already open scrolls instead of re-opening it, and a modifier asks
/// for a tab — are tested together rather than one at a time. The App target has no
/// test bundle, which is why this is not in the view that acts on it.
public enum LinkDestination: Equatable, Sendable {
  /// Scroll this document to a section number or an anchor; the reader resolves
  /// either.
  case jump(String)
  /// Show the linked document. How — here or in a tab of its own — is the
  /// activation the caller already holds; `LibraryModel.open(_:activation:in:)` is
  /// the one place that turns it into an effect, so a Command-click means the same
  /// thing here as on a button elsewhere.
  case document(RFCLink)
  /// Not a link the reader understands, so the system should have it.
  case unhandled

  public static func resolve(
    _ url: URL, from currentDocument: DocumentID, activation: LinkActivation
  ) -> LinkDestination {
    // An anchor is a position in the document already on screen, so it has nowhere
    // else to go: a tab of its own showing the same document scrolled elsewhere is
    // not what Command means.
    if let anchor = DocumentTextBuilder.anchor(from: url) {
      return .jump(anchor)
    }
    guard let link = RFCLink(url: url) else { return .unhandled }

    // A section of the document already on screen scrolls rather than re-opening
    // what is already open. Only when following in place: asked for a tab, a
    // section reference names something openable, unlike an anchor.
    if activation == .here, link.id == currentDocument, let section = link.section {
      return .jump(section)
    }
    return .document(link)
  }
}
