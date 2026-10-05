import CoreGraphics
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

  /// The reader beside is inserted with no width of its own, so its divider is put
  /// halfway across the two readers, which then have the same width (#187).
  @Test func `the readers' divider is put halfway across the two`() {
    let position = ReaderWindowDividers.besidePosition(
      readerStart: 0, besideEnd: 901, dividerThickness: 1)
    #expect(position == 450)
    // The reader runs from 0 to the divider, the reader beside from after it.
    #expect(position - 0 == 901 - (position + 1))
  }
}
