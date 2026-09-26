import Testing

@testable import RFCKit

@Suite("Citations")
struct CitationFormatterTests {
  let formatter = CitationFormatter()

  @Test func fullCitationMatchesRFCEditorStyle() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let citation = formatter.cite(http, style: .full)
    #expect(
      citation
        == "Fielding, R., Ed., Nottingham, M., Ed., and J. Reschke, Ed., \"HTTP Semantics\", STD 97, RFC 9110, DOI 10.17487/RFC9110, June 2022, <https://www.rfc-editor.org/info/rfc9110>."
    )
  }

  @Test func singleAuthor() throws {
    let bcp = try #require(try Fixtures.sampleIndex()[2119])
    let citation = formatter.cite(bcp, style: .full)
    #expect(
      citation.hasPrefix(
        "Bradner, S., \"Key words for use in RFCs to Indicate Requirement Levels\", BCP 14, RFC 2119,"
      ))
  }

  @Test func shortForms() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    #expect(formatter.cite(http, section: "4.2", style: .short) == "RFC 9110, Section 4.2")
    #expect(formatter.cite(http, section: "A", style: .short) == "RFC 9110, Appendix A")
    #expect(formatter.cite(http, style: .url) == "https://www.rfc-editor.org/info/rfc9110")
    #expect(
      formatter.cite(http, section: "4.2", style: .url)
        == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
    #expect(
      formatter.cite(http, section: "4.2", style: .markdown)
        == "[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)")
  }

  @Test func bibtex() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let entry = formatter.cite(http, style: .bibtex)
    #expect(entry.hasPrefix("@misc{rfc9110,"))
    #expect(entry.contains("    number = 9110,"))
    #expect(entry.contains("    title = {{HTTP Semantics}},"))
    #expect(entry.contains("    month = jun,"))
    #expect(entry.contains("    author = {R. Fielding and M. Nottingham and J. Reschke},"))
    #expect(entry.hasSuffix("}"))
  }
}
