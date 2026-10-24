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
  /// Show this entry of the document's bibliography, which the body leaves out;
  /// see `ReaderLinkScheme.referenceScheme`.
  case reference(String)
  /// Show the linked document, an RFC or a draft (#728). How — here or in a tab of
  /// its own — is the activation the caller already holds;
  /// `LibraryModel.open(_:activation:in:)` is the one place that turns it into an
  /// effect, so a Command-click means the same thing here as on a button elsewhere.
  case document(ReadableLink)
  /// Not a link the reader understands, so the system should have it.
  case unhandled

  public static func resolve(
    _ url: URL, from currentDocument: DocumentID, activation: LinkActivation
  ) -> LinkDestination {
    resolve(url, from: .rfc(currentDocument), activation: activation)
  }

  /// `resolve(_:from:activation:)` in an RFC or a draft's revision (#728).
  public static func resolve(
    _ url: URL, from currentDocument: ReadableDocument, activation: LinkActivation
  ) -> LinkDestination {
    // An anchor is a position in the document already on screen, so it has nowhere
    // else to go: a tab of its own showing the same document scrolled elsewhere is
    // not what Command means.
    if let anchor = ReaderLinkScheme.anchor(from: url) {
      return .jump(anchor)
    }
    if let entry = ReaderLinkScheme.reference(from: url) {
      return .reference(entry)
    }
    guard let link = ReadableLink(url: url) else { return .unhandled }

    // A section of the document already on screen scrolls rather than re-opening
    // what is already open. Only when following in place: asked for a tab, a
    // section reference names something openable, unlike an anchor.
    if activation == .here, names(currentDocument, link.document), let section = link.place {
      return .jump(section)
    }
    return .document(link)
  }

  /// Whether a link to `linked` is to `current`: the same RFC or revision, or, from
  /// inside a draft's revision, the draft by its name alone (#728).
  private static func names(_ current: ReadableDocument, _ linked: ReadableDocument) -> Bool {
    if linked == current { return true }
    guard let draft = linked.draft, draft.revision == nil, let shown = current.draft else {
      return false
    }
    return draft.name == shown.name
  }

  /// Where a jump to `place` in the document already open lands: the anchor it
  /// resolves to, or the bibliography entry it names, as `#RFC9110` does in the RFC
  /// Editor's HTML, which the body leaves out (#276). A document just opened only
  /// scrolls, and stays at its top for an entry.
  ///
  /// `.unhandled` when the build holds no such anchor, as it holds no `#page-12`: the
  /// jump would move nothing, so it is no jump, and gets no entry in the history.
  public static func landing(
    at place: String, in document: RFCDocument, bibliography: [ReferenceGroup],
    anchors: AnchorIndex
  ) -> LinkDestination {
    let anchor = document.anchor(forPlace: place)
    if bibliography.entry(anchor: anchor) != nil { return .reference(anchor) }
    return anchors.offset(of: anchor) != nil ? .jump(anchor) : .unhandled
  }
}
