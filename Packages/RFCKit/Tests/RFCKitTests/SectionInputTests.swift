import Testing

@testable import RFCKit

/// What someone types to go to a section (#711) in Go to Section… on the Mac and the
/// iPad. It reads a number as the App Intents' section lookup does (#1015).
@Suite("Section input")
struct SectionInputTests {
  private static let sections = [
    Section(
      anchor: "section-1", number: "1", title: "One",
      subsections: [Section(anchor: "section-1.1", number: "1.1", title: "One one")]),
    Section(anchor: "author-anchor", number: "2", title: "Two"),
    Section(
      anchor: "section-4", number: "4", title: "Four",
      subsections: [Section(anchor: "section-4.2", number: "4.2", title: "Four two")]),
    Section(
      anchor: "bad-assumptions", number: "A", title: "Appendix",
      subsections: [
        Section(anchor: "appendix-A.1", number: "A.1", title: "Nested", isAppendix: true)
      ],
      isAppendix: true),
    Section(anchor: "acknowledgments", title: "Acknowledgments"),
  ]

  @Test(arguments: [
    ("4.2", "section-4.2"),
    ("4.2.", "section-4.2"),
    (" 4.2 ", "section-4.2"),
    ("Section 4.2", "section-4.2"),
    ("section 4.2", "section-4.2"),
    ("  Section 4.2.  ", "section-4.2"),
    ("§4.2", "section-4.2"),
    ("§ 4.2", "section-4.2"),
    ("1.1", "section-1.1"),
    ("§2", "author-anchor"),
    ("section-2", "author-anchor"),
    ("section-4.2.", "section-4.2"),
    ("a", "bad-assumptions"),
    ("Appendix A", "bad-assumptions"),
    ("appendix a", "bad-assumptions"),
    ("A.1", "appendix-A.1"),
    ("a.1", "appendix-A.1"),
    ("Appendix A.1", "appendix-A.1"),
    ("appendix-A.1", "appendix-A.1"),
  ])
  func `a typed section names the section of the document it numbers`(
    _ typed: String, _ anchor: String
  ) {
    #expect(SectionInput.anchor(typed, in: Self.sections) == anchor)
  }

  @Test(arguments: [
    "", "  ", "§", ".", "Section", "intro", "Two", "acknowledgments", "4.2-3", "AB.1",
    "page-12", "3", "B", "Appendix B", "Appendix 4.2", "1.2", "Section 9", "section-9",
  ])
  func `what names no section of the document is nowhere`(_ typed: String) {
    #expect(SectionInput.anchor(typed, in: Self.sections) == nil)
  }
}
