import Testing

@testable import RFCReaderKit

/// A list's selection that can be cleared without the choice behind it being lost:
/// the sidebar's filter, which the document list keeps listing while a collapsed
/// split view shows the sidebar with nothing selected (#261).
@Suite("Kept selection")
struct KeptSelectionTests {
  @Test func startsSelected() {
    let kept = KeptSelection("all")
    #expect(kept.selection == "all")
    #expect(kept.value == "all")
  }

  @Test func clearingKeepsTheValue() {
    var kept = KeptSelection("bookmarks")
    kept.selection = nil
    #expect(kept.selection == nil)
    #expect(kept.value == "bookmarks")
  }

  @Test func choosingAgainShowsTheNewValue() {
    var kept = KeptSelection("bookmarks")
    kept.selection = nil
    kept.selection = "recent"
    #expect(kept.selection == "recent")
    #expect(kept.value == "recent")
  }

  @Test func choosingTheKeptValueShowsItAgain() {
    var kept = KeptSelection("bookmarks")
    kept.selection = nil
    kept.selection = "bookmarks"
    #expect(kept.selection == "bookmarks")
  }
}
