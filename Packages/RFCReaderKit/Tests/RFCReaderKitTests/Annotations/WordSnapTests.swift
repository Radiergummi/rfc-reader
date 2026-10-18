import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Annotations: snapping a selection to words")
struct WordSnapTests {
  private let text = "The quick brown fox." as NSString

  private func snapped(_ location: Int, _ length: Int) -> String {
    text.substring(with: WordSnap.snapped(NSRange(location: location, length: length), in: text))
  }

  @Test func `a selection inside words grows to their ends`() {
    #expect(snapped(6, 6) == "quick brown")
  }

  @Test func `white space at either end goes`() {
    #expect(snapped(3, 7) == "quick")
  }

  @Test func `punctuation is not a word`() {
    #expect(snapped(17, 3) == "fox.")
    #expect(snapped(16, 2) == "fox")
  }
}
