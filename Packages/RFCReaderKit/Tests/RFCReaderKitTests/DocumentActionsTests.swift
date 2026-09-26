import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Document actions")
struct DocumentActionsTests {
  private let id = DocumentID(series: .rfc, number: 9110)

  private func metadata(title: String) -> RFCMetadata {
    RFCMetadata(id: id, title: title, date: PublicationDate(year: 2022, month: 6))
  }

  // MARK: - The bookmark's title

  @Test func theIndexNamesTheBookmark() {
    let title = DocumentActions.bookmarkTitle(
      metadata: metadata(title: "HTTP Semantics"),
      documentTitle: "Something else entirely",
      id: id
    )
    #expect(title == "HTTP Semantics")
  }

  /// The divergence this whole type exists to settle: macOS had no document to
  /// fall back to and went straight to `RFC 9110`, so the same bookmark read
  /// differently depending on which toolbar made it.
  @Test func theDocumentNamesItWhenTheIndexDoesNot() {
    let title = DocumentActions.bookmarkTitle(
      metadata: nil, documentTitle: "HTTP Semantics", id: id)
    #expect(title == "HTTP Semantics")
  }

  @Test func theNumberNamesItWhenNothingElseCan() {
    #expect(DocumentActions.bookmarkTitle(metadata: nil, documentTitle: nil, id: id) == "RFC 9110")
  }

  // MARK: - The citation

  @Test func aCitationCarriesTheSectionBeingRead() {
    let cited = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: "4.2", style: .full)
    #expect(cited.contains("4.2"))
  }

  /// BibTeX has no field that says "and I mean §4.2", so a section passed through
  /// would land in the title or be dropped by whoever renders the entry.
  @Test func bibtexCitesTheWholeDocumentEvenWhileASectionIsBeingRead() {
    let withSection = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: "4.2", style: .bibtex)
    let without = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: nil, style: .bibtex)
    #expect(withSection == without)
  }

  @Test func everyOtherStyleKeepsTheSection() {
    for style in CitationStyle.allCases where style != .bibtex {
      let withSection = DocumentActions.citation(
        metadata(title: "HTTP Semantics"), section: "4.2", style: style)
      let without = DocumentActions.citation(
        metadata(title: "HTTP Semantics"), section: nil, style: style)
      #expect(withSection != without, "\(style) dropped the section")
    }
  }

  // MARK: - The section link

  @Test func theSectionLinkPointsAtThePlaceBeingRead() {
    let link = DocumentActions.sectionLink(id: id, section: "4.2")
    #expect(link == RFCLink(id: id, section: "4.2").webURL.absoluteString)
    #expect(link.contains("section-4.2"))
  }

  @Test func theLinkPointsAtTheDocumentWhenNoSectionIsKnown() {
    let link = DocumentActions.sectionLink(id: id, section: nil)
    #expect(!link.contains("section"))
  }
}
