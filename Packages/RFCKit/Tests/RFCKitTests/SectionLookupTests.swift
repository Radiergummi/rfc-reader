import Testing

@testable import RFCKit

/// A document's sections as an App Intent names and finds them (#192): by an
/// identifier across documents, and by number or title within one.
@Suite("Section lookup")
struct SectionLookupTests {
  @Test func `an identifier is the document's file stem and the section's anchor`() throws {
    let identifier = SectionIdentifier(document: .rfc(9110), anchor: "section-4.2")
    #expect(identifier.description == "rfc9110#section-4.2")
    #expect(SectionIdentifier("rfc9110#section-4.2") == identifier)
    // An author's anchor is kept as it is written.
    #expect(SectionIdentifier("bcp14#Some-Anchor")?.anchor == "Some-Anchor")
  }

  @Test func `an identifier without a document or an anchor names nothing`() {
    #expect(SectionIdentifier("rfc9110") == nil)
    #expect(SectionIdentifier("rfc9110#") == nil)
    #expect(SectionIdentifier("#section-1") == nil)
    #expect(SectionIdentifier("RFC 9110#section-1") == nil)
  }

  @Test func `a number in any spelling names its section`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    for spelling in ["5.2", "Section 5.2", "section 5.2.", "§ 5.2", "sec. 5.2"] {
      #expect(
        SectionLookup.sections(matching: spelling, in: document).map(\.number) == ["5.2"],
        "\(spelling)")
    }
  }

  @Test func `an appendix is named by its letter`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    let found = SectionLookup.sections(matching: "Appendix A", in: document)
    #expect(found.map(\.number) == ["A"])
    #expect(SectionLookup.sections(matching: "a", in: document).map(\.number) == ["A"])
  }

  @Test func `an anchor names its section`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    let found = SectionLookup.sections(matching: "long-header", in: document)
    #expect(found.map(\.number) == ["5.1"])
  }

  /// Words find every section whose title has them all, in document order.
  @Test func `words find the sections whose titles hold them`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    let headers = SectionLookup.sections(matching: "header", in: document)
    #expect(headers.map(\.number) == ["5.1", "5.2"])
    #expect(SectionLookup.sections(matching: "short HEADER", in: document).map(\.number) == ["5.2"])
  }

  @Test func `nothing typed lists every section, as the contents do`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    let all = SectionLookup.sections(matching: " ", in: document)
    #expect(all.map(\.anchor) == document.allSections.map(\.anchor))
  }
}
