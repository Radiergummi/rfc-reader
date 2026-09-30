import Testing

@testable import RFCKit

@Suite("Tab expansion")
struct TabExpansionTests {
  /// Each line of a block is expanded from its own column 0, so a whole figure can be
  /// expanded at once (#31): the columns do not run on across a newline.
  @Test func `tab expansion starts every line at column zero`() {
    #expect("abc\n\tx".expandingTabs() == "abc\n        x")
    #expect("abc\r\n\tx".expandingTabs() == "abc\r\n        x", "a CRLF is one Character")
    #expect("abcdefg\t|".expandingTabs() == "abcdefg |")
  }
}
