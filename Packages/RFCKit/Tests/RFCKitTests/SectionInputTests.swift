import Testing

@testable import RFCKit

/// What someone types to go to a section (#711): Go to Section… on the Mac and the
/// iPad, and the iOS # jump (#579), which share the parser.
@Suite("Section input")
struct SectionInputTests {
  @Test(arguments: [
    ("4.2", "4.2"),
    (" 4.2 ", "4.2"),
    ("4.2.", "4.2"),
    ("§4.2", "4.2"),
    ("§ 4.2", "4.2"),
    ("A.1", "A.1"),
    ("a.1", "A.1"),
    ("b", "B"),
    ("section-4.2", "section-4.2"),
    ("appendix-A.1", "appendix-A.1"),
  ])
  func `a typed section is read as its number or its anchor`(_ typed: String, _ place: String) {
    #expect(SectionInput.place(typed) == place)
  }

  @Test(arguments: ["", "  ", "§", "intro", "4.2-3", "AB.1", "page-12", "."])
  func `what names no section is nothing`(_ typed: String) {
    #expect(SectionInput.place(typed) == nil)
  }

  private static let sections = [
    Section(
      anchor: "section-1", number: "1", title: "One",
      subsections: [Section(anchor: "section-1.1", number: "1.1", title: "One one")]),
    Section(anchor: "author-anchor", number: "2", title: "Two"),
    Section(
      anchor: "bad-assumptions", number: "A", title: "Appendix",
      subsections: [
        Section(anchor: "appendix-A.1", number: "A.1", title: "Nested", isAppendix: true)
      ],
      isAppendix: true),
    Section(anchor: "acknowledgments", title: "Acknowledgments"),
  ]

  @Test(arguments: [
    ("1.1", "section-1.1"),
    ("§2", "author-anchor"),
    ("section-2", "author-anchor"),
    ("a", "bad-assumptions"),
    ("A.1", "appendix-A.1"),
    ("appendix-A.1", "appendix-A.1"),
  ])
  func `a typed section names the section of the document it numbers`(
    _ typed: String, _ anchor: String
  ) {
    #expect(SectionInput.anchor(typed, in: Self.sections) == anchor)
  }

  @Test(arguments: ["3", "B", "1.2", "section-9"])
  func `a section the document does not have is nowhere`(_ typed: String) {
    #expect(SectionInput.anchor(typed, in: Self.sections) == nil)
  }
}
