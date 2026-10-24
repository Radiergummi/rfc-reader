import Testing

@testable import RFCKit

@Suite("Citations")
struct CitationFormatterTests {
  @Test func `full citation matches RFC editor style`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let citation = CitationFormatter.cite(http, style: .full)
    #expect(
      citation
        == "Fielding, R., Ed., Nottingham, M., Ed., and J. Reschke, Ed., \"HTTP Semantics\", STD 97, RFC 9110, DOI 10.17487/RFC9110, June 2022, <https://www.rfc-editor.org/info/rfc9110>."
    )
  }

  @Test func `single author`() throws {
    let bcp = try #require(try Fixtures.sampleIndex()[2119])
    let citation = CitationFormatter.cite(bcp, style: .full)
    #expect(
      citation.hasPrefix(
        "Bradner, S., \"Key words for use in RFCs to Indicate Requirement Levels\", BCP 14, RFC 2119,"
      ))
  }

  /// A surname of more than one word is inverted whole, and a name that is all
  /// surname, an organization's, is not inverted at all (#768).
  @Test func `a surname of several words is inverted whole`() {
    let authors = [
      Author(name: "D. Eastlake 3rd"), Author(name: "F. Le Faucheur"),
      Author(name: "Internet Architecture Board"), Author(name: "M. St. Johns"),
    ]
    #expect(
      CitationFormatter.authorList(authors)
        == "Eastlake 3rd, D., Le Faucheur, F., Internet Architecture Board, and M. St. Johns")
    #expect(CitationFormatter.authorList([authors[2]]) == "Internet Architecture Board")
  }

  @Test func `short forms`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    #expect(CitationFormatter.cite(http, section: "4.2", style: .short) == "RFC 9110, Section 4.2")
    #expect(CitationFormatter.cite(http, section: "A", style: .short) == "RFC 9110, Appendix A")
    #expect(
      CitationFormatter.cite(http, section: "appendix-1", style: .short) == "RFC 9110, Appendix 1")
    #expect(CitationFormatter.cite(http, style: .url) == "https://www.rfc-editor.org/info/rfc9110")
    #expect(
      CitationFormatter.cite(http, section: "4.2", style: .url)
        == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
    #expect(
      CitationFormatter.cite(http, section: "4.2", style: .markdown)
        == "[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)")
  }

  @Test func `bibtex`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    let entry = CitationFormatter.cite(http, style: .bibtex)
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
    let entry = CitationFormatter.cite(rfc, style: .bibtex)
    #expect(
      entry.contains(#"    title = {{Sets \textbraceleft{}A \& B\textbraceright{} at 100\%}},"#))
    #expect(
      entry.contains(#"    abstract = {Uses \% and \textbraceleft{}braces\textbraceright{}.},"#))

    // A backslash of the text's own must not start a command with what follows it.
    let slashed = RFCMetadata(
      id: .rfc(2), title: #"Paths like C:\ and {x\}"#, date: PublicationDate(year: 1969))
    #expect(
      CitationFormatter.cite(slashed, style: .bibtex).contains(
        #"    title = {{Paths like C:\textbackslash{} and \textbraceleft{}x\textbackslash{}\textbraceright{}}},"#
      ))
  }

  /// BibTeX accepts these, but LaTeX reads each as markup when it typesets the
  /// field (#242), in every field that `bibtexEscaped` handles.
  @Test(arguments: [
    ("_", #"\_"#),
    ("$", #"\$"#),
    ("#", ##"\#"##),
    ("^", #"\textasciicircum{}"#),
    ("~", #"\textasciitilde{}"#),
  ])
  func `bibtex escapes a character LaTeX reads as markup`(character: String, escaped: String) {
    let rfc = RFCMetadata(
      id: .rfc(1), title: "a\(character)b", authors: [Author(name: "e\(character)f")],
      date: PublicationDate(year: 1969), abstract: "c\(character)d")
    let entry = CitationFormatter.cite(rfc, style: .bibtex)
    #expect(entry.contains("    author = {e\(escaped)f},"))
    #expect(entry.contains("    title = {{a\(escaped)b}},"))
    #expect(entry.contains("    abstract = {c\(escaped)d},"))
  }

  /// A combining mark joins the character before it into one `Character`, which a
  /// switch over characters doesn't match, so the brace or `_` it follows went
  /// through raw.
  @Test func `bibtex escapes a special character that a combining mark follows`() {
    #expect(
      CitationFormatter.bibtexEscaped("{\u{0301}_\u{0332}")
        == "\\textbraceleft{}\u{0301}\\_\u{0332}")
  }

  /// BibTeX counts braces whether or not a backslash precedes them, so `\{` only
  /// works for braces that already pair up. A lone one in a title has to leave the
  /// entry's braces balanced, or the field runs on into the rest of the entry.
  @Test func `bibtex keeps its braces balanced around a lone brace`() {
    for title in ["Syntax for {", "Closing } early"] {
      let rfc = RFCMetadata(id: .rfc(1), title: title, date: PublicationDate(year: 1969))
      let entry = CitationFormatter.cite(rfc, style: .bibtex)
      #expect(entry.filter { $0 == "{" }.count == entry.filter { $0 == "}" }.count, "\(title)")
    }
  }

  // MARK: - xml2rfc (#712)

  /// As bib.ietf.org serves it: editors carry their role, the series the RFC is part
  /// of comes before the RFC itself, and the DOI last.
  @Test func `an xml2rfc reference`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    #expect(
      CitationFormatter.cite(http, style: .xml2rfc) == """
        <reference anchor="RFC9110" target="https://www.rfc-editor.org/info/rfc9110">
          <front>
            <title>HTTP Semantics</title>
            <author fullname="R. Fielding" initials="R." role="editor" surname="Fielding"/>
            <author fullname="M. Nottingham" initials="M." role="editor" surname="Nottingham"/>
            <author fullname="J. Reschke" initials="J." role="editor" surname="Reschke"/>
            <date month="June" year="2022"/>
          </front>
          <seriesInfo name="STD" value="97"/>
          <seriesInfo name="RFC" value="9110"/>
          <seriesInfo name="DOI" value="10.17487/RFC9110"/>
        </reference>
        """)
  }

  /// A BCP's RFC names its BCP, and an author without initials is an organization,
  /// as bib.ietf.org writes the IAB.
  @Test func `an xml2rfc reference of a BCP's RFC, by an organization`() throws {
    var keywords = try #require(try Fixtures.sampleIndex()[2119])
    keywords.authors = [Author(name: "Internet Architecture Board"), Author(name: "S. Bradner")]
    let reference = CitationFormatter.cite(keywords, style: .xml2rfc)
    #expect(
      reference.contains(
        """
            <author>
              <organization>Internet Architecture Board</organization>
            </author>
            <author fullname="S. Bradner" initials="S." surname="Bradner"/>
        """))
    #expect(
      reference.contains(
        """
          <seriesInfo name="BCP" value="14"/>
          <seriesInfo name="RFC" value="2119"/>
        """))
  }

  @Test func `an xml2rfc reference escapes its markup`() {
    let rfc = RFCMetadata(
      id: .rfc(1), title: "<Tags> & \"Quotes\"", authors: [Author(name: "A. O\"Brien")],
      date: PublicationDate(year: 1969))
    let reference = CitationFormatter.cite(rfc, style: .xml2rfc)
    #expect(reference.contains("<title>&lt;Tags&gt; &amp; &quot;Quotes&quot;</title>"))
    #expect(reference.contains(#"fullname="A. O&quot;Brien""#))
    // No month: the year alone.
    #expect(reference.contains(#"<date year="1969"/>"#))
  }

  /// A section is said by the `xref` that cites the reference, never by the
  /// reference, as BibTeX's entry names none either.
  @Test func `only the styles with a place for it cite a section`() {
    #expect(CitationStyle.allCases.filter { !$0.citesSections } == [.bibtex, .xml2rfc])
    #expect(CitationStyle.allCases.filter(\.needsIndexEntry) == [.full, .bibtex, .xml2rfc])
  }

  // MARK: - Sites (#712)

  @Test func `every style links to the chosen site`() throws {
    let http = try #require(try Fixtures.sampleIndex()[9110])
    #expect(
      CitationFormatter.cite(http, section: "4.2", style: .markdown, site: .datatracker)
        == "[RFC 9110, Section 4.2](https://datatracker.ietf.org/doc/html/rfc9110#section-4.2)")
    #expect(
      CitationFormatter.cite(http, section: "4.2", style: .url, site: .app)
        == "rfc://9110#section-4.2")
    #expect(
      CitationFormatter.cite(http, style: .full, site: .ietf)
        .hasSuffix("June 2022, <https://www.ietf.org/rfc/rfc9110.txt>."))
    #expect(
      CitationFormatter.cite(http, style: .bibtex, site: .datatracker)
        .contains("    url = {https://datatracker.ietf.org/doc/html/rfc9110},"))
    #expect(
      CitationFormatter.cite(http, style: .xml2rfc, site: .app)
        .hasPrefix(#"<reference anchor="RFC9110" target="rfc://9110">"#))
  }

  // MARK: - Series (#712, the class of #552 and #656)

  private static let bcp14 = DocumentID(series: .bcp, number: 14)

  /// A BCP is cited as the BCP, never as the first RFC the reader shows for it.
  @Test func `a series is cited as itself`() throws {
    let cited = try #require(CitedDocument(Self.bcp14, in: try Fixtures.sampleIndex()))
    #expect(cited.id == Self.bcp14)
    #expect(CitationFormatter.cite(cited, style: .short) == "BCP 14")
    #expect(CitationFormatter.cite(cited, section: "2", style: .short) == "BCP 14, Section 2")
    #expect(CitationFormatter.cite(cited, style: .url) == "https://www.rfc-editor.org/info/bcp14")
  }

  /// A series has no page of its own sections on the web: the link is to the series
  /// and the label names the section. The app opens it at the section.
  @Test func `a section of a series links to the series on the web`() throws {
    let cited = try #require(CitedDocument(Self.bcp14, in: try Fixtures.sampleIndex()))
    #expect(
      CitationFormatter.cite(cited, section: "2", style: .markdown)
        == "[BCP 14, Section 2](https://www.rfc-editor.org/info/bcp14)")
    #expect(
      CitationFormatter.cite(cited, section: "2", style: .url, site: .app)
        == "rfc://bcp14#section-2")
  }

  @Test func `a series' full citation lists its members`() throws {
    let cited = try #require(CitedDocument(Self.bcp14, in: try Fixtures.sampleIndex()))
    let lines = CitationFormatter.cite(cited, style: .full).split(separator: "\n")
    #expect(lines.count == 4)
    #expect(lines[0] == "Best Current Practice 14, <https://www.rfc-editor.org/info/bcp14>.")
    #expect(lines[1] == "At the time of writing, this BCP comprises the following:")
    #expect(lines[2].hasPrefix("Bradner, S., "))
    #expect(lines[2].contains("BCP 14, RFC 2119,"))
    #expect(lines[3].hasPrefix("Leiba, B., "))
  }

  @Test func `a series' BibTeX entry is the series`() throws {
    let cited = try #require(CitedDocument(Self.bcp14, in: try Fixtures.sampleIndex()))
    let entry = CitationFormatter.cite(cited, style: .bibtex)
    #expect(entry.hasPrefix("@misc{bcp14,"))
    #expect(entry.contains("    series = {Best Current Practice},"))
    #expect(entry.contains("    number = 14,"))
    #expect(entry.contains("    note = {Comprises RFC 2119, RFC 8174},"))
  }

  /// A `referencegroup` of the members' references, as bib.ietf.org serves a BCP.
  @Test func `a series' xml2rfc reference is a reference group`() throws {
    let cited = try #require(CitedDocument(Self.bcp14, in: try Fixtures.sampleIndex()))
    let group = CitationFormatter.cite(cited, style: .xml2rfc)
    #expect(
      group.hasPrefix(
        """
        <referencegroup anchor="BCP14" target="https://www.rfc-editor.org/info/bcp14">
          <reference anchor="RFC2119" target="https://www.rfc-editor.org/info/rfc2119">
            <front>
        """))
    #expect(group.contains(#"  <reference anchor="RFC8174""#))
    #expect(group.hasSuffix("  </reference>\n</referencegroup>"))
  }

  @Test func `only what the index lists is cited from it`() throws {
    let index = try Fixtures.sampleIndex()
    #expect(CitedDocument(.rfc(9110), in: index)?.id == .rfc(9110))
    #expect(CitedDocument(.rfc(1), in: index) == nil)
    #expect(CitedDocument(DocumentID(series: .bcp, number: 9999), in: index) == nil)
    #expect(CitationFormatter.cite(CitedDocument(bare: .rfc(1)), style: .short) == "RFC 1")
  }
}
