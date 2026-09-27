import Testing

@testable import RFCKit

/// `referencedDocuments` over the model itself, not through a parser: which parts of
/// a document it visits is a property of the walk, and a hand-built document can put
/// a citation in exactly one place, where a real RFC cites the same document from its
/// body as well and would pass either way.
@Suite("Referenced documents")
struct ReferencedDocumentsTests {
  private func citing(_ number: Int) -> Inline {
    .crossReference(CrossReference(target: .document(.rfc(number), section: nil)))
  }

  /// Headings became `[Inline]` because some 3,500 of them cite a document ("Changes
  /// from RFC 3066"), and an abstract cites like any prose, but the walk visited only
  /// section bodies: a document cited in a heading or the abstract alone was missing
  /// (#127).
  @Test func `a citation in a heading or the abstract counts`() {
    let header = DocumentHeader(
      title: "Example", abstract: [.paragraph(Paragraph([.text("Updates "), citing(793)]))])
    let changes = Section(
      anchor: "section-1.1", number: "1.1", title: [.text("Changes from "), citing(3066)])
    let body = Section(
      anchor: "section-1", number: "1", title: [.text("Introduction")],
      blocks: [.paragraph(Paragraph([.text("See "), citing(9110)]))], subsections: [changes])
    let document = RFCDocument(header: header, sections: [body], source: .xml)

    #expect(document.referencedDocuments == [.rfc(793), .rfc(3066), .rfc(9110)])
  }

  /// An annotation is prose the parser linkifies like any other, so it can cite a
  /// document the entry itself does not name -- a living standard's entry noting the
  /// RFC it was aligned with. The walk counted an entry's own document but never
  /// looked inside its annotation.
  @Test func `a citation in a reference annotation counts`() {
    let fetch = Reference(
      anchor: "FETCH", title: "Fetch Standard",
      annotation: [.text("Aligned with "), citing(9110), .text(".")])
    let references = Section(
      anchor: "section-2", number: "2", title: [.text("References")],
      blocks: [.references(ReferenceList(title: "References", entries: [fetch]))])
    let document = RFCDocument(
      header: DocumentHeader(title: "Example"), sections: [references], source: .xml)

    #expect(document.referencedDocuments == [.rfc(9110)])
  }
}
