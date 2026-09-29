import Testing

@testable import RFCKit

@Suite("Citations")
struct CitationFormatterTests {
  let formatter = CitationFormatter()

  @Test func `full citation matches RFC editor style`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let citation = formatter.cite(http, style: .full)
    #expect(
      citation
        == "Fielding, R., Ed., Nottingham, M., Ed., and J. Reschke, Ed., \"HTTP Semantics\", STD 97, RFC 9110, DOI 10.17487/RFC9110, June 2022, <https://www.rfc-editor.org/info/rfc9110>."
    )
  }

  @Test func `single author`() throws {
    let bcp = try #require(try Fixtures.sampleIndex()[2119])
    let citation = formatter.cite(bcp, style: .full)
    #expect(
      citation.hasPrefix(
        "Bradner, S., \"Key words for use in RFCs to Indicate Requirement Levels\", BCP 14, RFC 2119,"
      ))
  }

  @Test func `short forms`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    #expect(formatter.cite(http, section: "4.2", style: .short) == "RFC 9110, Section 4.2")
    #expect(formatter.cite(http, section: "A", style: .short) == "RFC 9110, Appendix A")
    #expect(formatter.cite(http, section: "appendix-1", style: .short) == "RFC 9110, Appendix 1")
    #expect(formatter.cite(http, style: .url) == "https://www.rfc-editor.org/info/rfc9110")
    #expect(
      formatter.cite(http, section: "4.2", style: .url)
        == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
    #expect(
      formatter.cite(http, section: "4.2", style: .markdown)
        == "[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)")
  }

  @Test func `bibtex`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let entry = formatter.cite(http, style: .bibtex)
    #expect(entry.hasPrefix("@misc{rfc9110,"))
    #expect(entry.contains("    number = 9110,"))
    #expect(entry.contains("    title = {{HTTP Semantics}},"))
    #expect(entry.contains("    month = jun,"))
    #expect(entry.contains("    author = {R. Fielding and M. Nottingham and J. Reschke},"))
    #expect(entry.hasSuffix("}"))
  }

  /// A brace ends a BibTeX field early, `%` starts a comment and `&` is LaTeX's
  /// alignment character, so a title holding any of them made the entry invalid
  /// (#150). They are escaped the way LaTeX expects.
  @Test func `bibtex escapes its special characters`() {
    let rfc = RFCMetadata(
      id: .rfc(1), title: "Sets {A & B} at 100%", date: PublicationDate(year: 1969),
      abstract: "Uses % and {braces}.")
    let entry = formatter.cite(rfc, style: .bibtex)
    #expect(
      entry.contains(#"    title = {{Sets \textbraceleft{}A \& B\textbraceright{} at 100\%}},"#))
    #expect(
      entry.contains(#"    abstract = {Uses \% and \textbraceleft{}braces\textbraceright{}.},"#))

    // A backslash of the text's own must not start a command with what follows it.
    let slashed = RFCMetadata(
      id: .rfc(2), title: #"Paths like C:\ and {x\}"#, date: PublicationDate(year: 1969))
    #expect(
      formatter.cite(slashed, style: .bibtex).contains(
        #"    title = {{Paths like C:\textbackslash{} and \textbraceleft{}x\textbackslash{}\textbraceright{}}},"#
      ))
  }

  /// BibTeX counts braces whether or not a backslash precedes them, so `\{` only
  /// works for braces that already pair up. A lone one in a title has to leave the
  /// entry's braces balanced, or the field runs on into the rest of the entry.
  @Test func `bibtex keeps its braces balanced around a lone brace`() {
    for title in ["Syntax for {", "Closing } early"] {
      let rfc = RFCMetadata(id: .rfc(1), title: title, date: PublicationDate(year: 1969))
      let entry = formatter.cite(rfc, style: .bibtex)
      #expect(entry.filter { $0 == "{" }.count == entry.filter { $0 == "}" }.count, "\(title)")
    }
  }
}
