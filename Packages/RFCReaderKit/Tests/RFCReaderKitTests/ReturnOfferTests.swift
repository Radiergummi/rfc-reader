import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Return offer")
struct ReturnOfferTests {
  private let document = RFCDocument(
    header: DocumentHeader(title: "T"),
    sections: [
      Section(anchor: "abstract", title: "Abstract"),
      Section(
        anchor: "section-4", number: "4", title: "Semantics",
        subsections: [Section(anchor: "section-4.2", number: "4.2", title: "Methods")]),
      Section(anchor: "appendix-A.1", number: "A.1", title: "Grammar", isAppendix: true),
    ],
    source: .xml)

  private func title(_ section: String?, in document: RFCDocument? = nil) -> String {
    ReturnOffer.title(for: Place(id: .rfc(9110), section: section), in: document ?? self.document)
  }

  /// What the history usually records: the anchor the reader had scrolled to.
  @Test func `an anchor is named by its section number`() {
    #expect(title("section-4.2") == "Back to §4.2")
    #expect(title("appendix-A.1") == "Back to §A.1")
  }

  /// A deep link or a section link can record the number itself.
  @Test func `a section number is named as it is`() {
    #expect(title("4.2") == "Back to §4.2")
  }

  /// Resolved the way a jump resolves it, through `anchor(forPlace:)`: a number
  /// is read as a number first, so the label names the section a tap goes to even
  /// when some anchor happens to be spelled like another section's number.
  @Test func `a place is resolved the way a jump resolves it`() {
    let tricky = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(anchor: "4.2", number: "7", title: "Oddly anchored"),
        Section(anchor: "section-4.2", number: "4.2", title: "Methods"),
      ],
      source: .xml)
    #expect(tricky.anchor(forPlace: "4.2") == "section-4.2")
    #expect(title("4.2", in: tricky) == "Back to §4.2")
  }

  @Test func `no place yet is the top`() {
    #expect(title(nil) == "Back to Top")
  }

  /// The abstract, or anything else the storage anchors without a number.
  @Test func `an unnumbered place is plain back`() {
    #expect(title("abstract") == "Back")
    #expect(title("figure-3") == "Back")
  }

  /// Before the document has loaded there is nothing to name a section by.
  @Test func `a place in a document not yet loaded is plain back`() {
    #expect(ReturnOffer.title(for: Place(id: .rfc(9110), section: "4.2"), in: nil) == "Back")
  }
}
