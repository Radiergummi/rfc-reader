import RFCKit

/// How the document on screen spells its places, for the history to compare them
/// (#482).
///
/// A place arrives as a section number, `4.2`, from a link, `jump to section` or a
/// deep link, and as an anchor, `section-4.2`, from the contents and the reader.
/// Only the document can say they are the same place. And the reader reports where
/// it is by section, so a jump to a figure is still where the reader is while the
/// reader reports the figure's section.
public struct DocumentPlaces: Sendable {
  private let document: RFCDocument
  private let anchors: AnchorIndex

  public init(document: RFCDocument, anchors: AnchorIndex) {
    self.document = document
    self.anchors = anchors
  }

  /// The anchor `place` names, as a jump resolves it.
  public func anchor(for place: String) -> String {
    document.anchor(forPlace: place)
  }

  /// The section the reader reports while `place` is at its top: the section
  /// `place` is in, the first section for a place ahead of it, as the reader
  /// reports there, or `place` itself when the build holds no such anchor.
  ///
  /// The sections are indexed here, not on creation, because only a jump to the
  /// history's current place asks.
  public func section(of place: String) -> String {
    let anchor = anchor(for: place)
    guard let offset = anchors.offset(of: anchor) else { return anchor }
    let sections = anchors.sections
    return sections.anchor(at: offset) ?? sections.entries.first?.anchor ?? anchor
  }
}
