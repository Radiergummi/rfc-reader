import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Return offer")
struct ReturnOfferTests {
  private let numbers = ["section-4.2": "4.2", "appendix-A.1": "A.1"]

  private func title(_ section: String?) -> String {
    ReturnOffer.title(for: Place(id: .rfc(9110), section: section), sectionNumbers: numbers)
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

  @Test func `no place yet is the top`() {
    #expect(title(nil) == "Back to Top")
  }

  /// The abstract, or anything else the storage anchors without a number.
  @Test func `an unnumbered place is plain back`() {
    #expect(title("abstract") == "Back")
  }
}
