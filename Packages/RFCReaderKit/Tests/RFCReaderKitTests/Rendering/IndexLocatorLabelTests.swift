import Testing

@testable import RFCReaderKit

@Suite("Index locator labels")
struct IndexLocatorLabelTests {
  @Test(arguments: [
    ("Section 9.3.1", "§9.3.1"),
    ("Section 15", "§15"),
    ("Section 3.7, Paragraph 6", "§3.7\u{00A0}¶6"),
    ("Section 14.6, Paragraph 4, Item 2", "§14.6\u{00A0}¶4"),
    ("Appendix A.2.5, Paragraph 1", "§A.2.5\u{00A0}¶1"),
    ("Appendix B.1", "§B.1"),
    ("Section\u{00A0}9.3.1", "§9.3.1"),
  ])
  func `a section or appendix label shortens to its number and paragraph`(
    label: String, short: String
  ) {
    #expect(IndexLocatorLabel.short(label) == short)
  }

  @Test(arguments: ["Table 2", "Figure 4", "Section 3, Item 2", "Section", "", "Appendix"])
  func `a label of any other shape reads unchanged`(label: String) {
    #expect(IndexLocatorLabel.short(label) == label)
  }
}
