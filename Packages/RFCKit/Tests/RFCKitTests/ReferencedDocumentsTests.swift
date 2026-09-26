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
  @Test func aCitationInAHeadingOrTheAbstractCounts() {
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
}
