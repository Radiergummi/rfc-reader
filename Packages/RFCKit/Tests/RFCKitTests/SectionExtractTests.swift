import Foundation
import Testing

@testable import RFCKit

/// A document narrowed to the section a reader is in, for an export or a print of
/// it alone (#386).
@Suite("Section extract")
struct SectionExtractTests {
  private static let document = RFCDocument(
    header: DocumentHeader(
      id: .rfc(9999), title: "A Protocol", abbreviatedTitle: "Protocol",
      abstract: [.paragraph(Paragraph(text: "What it does."))]),
    sections: [
      Section(
        anchor: "section-1", number: "1", title: "Introduction",
        blocks: [
          .paragraph(
            Paragraph(
              [.crossReference(CrossReference(target: .anchor("section-2.1"), text: "below"))],
              anchor: "section-1-1"))
        ]),
      Section(
        anchor: "section-2", number: "2", title: "Rules",
        blocks: [
          .paragraph(
            Paragraph(
              [.crossReference(CrossReference(target: .anchor("section-1"), text: "above"))],
              anchor: "section-2-1"))
        ],
        subsections: [Section(anchor: "section-2.1", number: "2.1", title: "More")]),
    ], source: .xml)

  @Test func `a section keeps its subsections and loses the rest`() throws {
    let narrowed = try #require(Self.document.narrowed(toSection: "section-2"))
    #expect(narrowed.allSections.map(\.anchor) == ["section-2", "section-2.1"])
    #expect(narrowed.header.abstract.isEmpty)
    #expect(narrowed.header.id == .rfc(9999))
  }

  @Test func `the title names the section after the document`() throws {
    let narrowed = try #require(Self.document.narrowed(toSection: "section-2.1"))
    #expect(narrowed.header.title == "A Protocol, §\u{00A0}2.1")
    #expect(narrowed.header.abbreviatedTitle == "Protocol, §\u{00A0}2.1")
  }

  @Test func `no section is narrowed to nothing`() {
    #expect(Self.document.narrowed(toSection: "section-9") == nil)
  }

  @Test func `the anchors are the sections', the blocks' and the abstract's`() throws {
    #expect(
      Self.document.anchors == [
        "section-1", "section-1-1", "section-2", "section-2-1", "section-2.1", "abstract",
      ])
    let narrowed = try #require(Self.document.narrowed(toSection: "section-2"))
    #expect(narrowed.anchors == ["section-2", "section-2-1", "section-2.1"])
  }

  /// A reference to what the section leaves out goes to the document on
  /// rfc-editor.org; one into the section stays in the file.
  @Test func `a reference out of the section links to the published document`() throws {
    let narrowed = try #require(Self.document.narrowed(toSection: "section-2"))
    let markdown = RFCMarkdownSerializer(outside: .rfc(9999)).serialize(narrowed)
    #expect(markdown.contains("[above](https://www.rfc-editor.org/rfc/rfc9999#section-1)"))
    #expect(!markdown.contains("(#section-1)"))
    let html = RFCHTMLSerializer(outside: .rfc(9999)).page(narrowed)
    #expect(html.contains("href=\"https://www.rfc-editor.org/rfc/rfc9999#section-1\""))
    let book = RFCHTMLSerializer(outside: .rfc(9999)).chapters(narrowed)
    #expect(book[1].body.contains("href=\"https://www.rfc-editor.org/rfc/rfc9999#section-1\""))
  }

  /// A whole document links within itself, whatever anchor a link names: a place
  /// the document lacks is no other document's.
  @Test func `a whole document's links stay in it`() {
    let whole = RFCMarkdownSerializer().serialize(Self.document)
    #expect(whole.contains("[below](#section-2.1)"))
    #expect(!whole.contains("rfc-editor.org/rfc/rfc9999#"))
  }
}
