import Testing

@testable import RFCReaderKit

@Suite("Reader window dividers")
struct ReaderWindowDividersTests {
  @Test func `the panel's divider follows the reader when it is read alone`() {
    #expect(ReaderWindowDividers.panel(comparing: false) == 2)
  }

  @Test func `the panel's divider follows the reader beside while comparing`() {
    #expect(ReaderWindowDividers.panel(comparing: true) == 3)
  }
}
