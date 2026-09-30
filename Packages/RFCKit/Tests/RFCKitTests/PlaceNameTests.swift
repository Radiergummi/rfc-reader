import Testing

@testable import RFCKit

/// How a place in a document is named: a section, a lettered appendix, and an
/// appendix numbered like a section, which a legacy RFC can have beside section 1
/// (#429).
@Suite("Place names")
struct PlaceNameTests {
  @Test func `a section's place is its number`() {
    #expect(Section(anchor: "section-4.2", number: "4.2", title: "Methods").place == "4.2")
  }

  @Test func `a lettered appendix's place is its number`() {
    let appendix = Section(
      anchor: "appendix-A.1", number: "A.1", title: "Grammar", isAppendix: true)
    #expect(appendix.place == "A.1")
  }

  /// The number alone names section 1, so the place is the appendix's anchor, the
  /// way `RFCLink` names it.
  @Test func `an appendix numbered like a section is placed by its anchor`() {
    let appendix = Section(
      anchor: "appendix-1", number: "1", title: "State Tables", isAppendix: true)
    #expect(appendix.place == "appendix-1")
  }

  /// Read back from RFCXML, a subsection of a numbered appendix is in `<back>`, so it
  /// is an appendix too, but its anchor is a section's: that anchor is where a link to
  /// it has to go.
  @Test func `a numbered appendix's subsection is placed by its number`() {
    let subsection = Section(
      anchor: "section-1.1", number: "1.1", title: "Transitions", isAppendix: true)
    #expect(subsection.place == "1.1")
  }

  @Test func `an unnumbered section has no place`() {
    #expect(Section(anchor: "abstract", title: "Abstract").place == nil)
  }

  @Test func `a place is spelled out as a section or an appendix`() {
    #expect(PlaceName.spelledOut("4.2") == "Section 4.2")
    #expect(PlaceName.spelledOut("A.1") == "Appendix A.1")
    #expect(PlaceName.spelledOut("appendix-1") == "Appendix 1")
  }

  /// A section sign before a number that is an appendix's would name section 1.
  @Test func `only a place the section sign cannot name is spelled out when abbreviated`() {
    #expect(PlaceName.abbreviated("4.2") == "§\u{00A0}4.2")
    #expect(PlaceName.abbreviated("A.1") == "§\u{00A0}A.1")
    #expect(PlaceName.abbreviated("appendix-1") == "Appendix\u{00A0}1")
  }

  @Test func `a reference to a numbered appendix names it as an appendix`() {
    let reference = CrossReference(target: .document(.rfc(1163), section: "appendix-1"))
    #expect(reference.label == "Appendix\u{00A0}1 of [RFC\u{00A0}1163]")
    #expect(reference.display.text == "RFC\u{00A0}1163\u{00A0}Appendix\u{00A0}1")
    let bare = CrossReference(
      target: .document(.rfc(1163), section: "appendix-1"), sectionFormat: .bare)
    #expect(bare.label == "Appendix\u{00A0}1")
  }

  @Test func `a reference to a lettered appendix does not break before its letter`() {
    let reference = CrossReference(target: .document(.rfc(9110), section: "A.1"))
    #expect(reference.label == "Appendix\u{00A0}A.1 of [RFC\u{00A0}9110]")
  }
}
