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
  private let sections: AnchorIndex
  private let anchors: AnchorIndex

  public init(document: RFCDocument, anchors: AnchorIndex) {
    self.document = document
    self.anchors = anchors
    self.sections = anchors.sections
  }

  /// The anchor `place` names, as a jump resolves it.
  public func anchor(for place: String) -> String {
    document.anchor(forPlace: place)
  }

  /// The section the reader reports while `place` is at its top: the section
  /// `place` is in, or `place` itself when the build holds no such anchor.
  public func section(of place: String) -> String {
    let anchor = anchor(for: place)
    return anchors.offset(of: anchor).flatMap(sections.anchor(at:)) ?? anchor
  }
}
