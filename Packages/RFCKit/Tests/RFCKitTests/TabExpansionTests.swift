import RFCKit
import Testing

@Suite("Tab expansion")
struct TabExpansionTests {
  /// A tab goes to the next multiple-of-eight column, counted from where the line's
  /// text has reached, so one tab is anything from one space to eight.
  @Test func `a tab is spaces to the next eighth column`() {
    #expect("\tx".expandingTabs() == "        x")
    #expect("abcdefg\t|".expandingTabs() == "abcdefg |")
    #expect("abcdefgh\t|".expandingTabs() == "abcdefgh        |")
  }
}
