import Foundation
import Testing

@testable import RFCKit

@Suite("Links")
struct RFCLinkTests {
  @Test(
    arguments: [
      ("rfc://9110", RFCLink(id: .rfc(9110))),
      ("rfc://9110#section-4.2", RFCLink(id: .rfc(9110), section: "4.2")),
      ("rfc://9110#appendix-A.1", RFCLink(id: .rfc(9110), section: "A.1")),
      ("rfc://bcp14", RFCLink(id: DocumentID(series: .bcp, number: 14))),
      (
        "https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2",
        RFCLink(id: .rfc(9110), section: "4.2")
      ),
      ("https://www.rfc-editor.org/rfc/rfc9110#appendix-A", RFCLink(id: .rfc(9110), section: "A")),
      ("https://www.rfc-editor.org/info/rfc9110", RFCLink(id: .rfc(9110))),
      ("https://www.rfc-editor.org/rfc/rfc9110.txt", RFCLink(id: .rfc(9110))),
      ("https://www.rfc-editor.org/errata/rfc9110", RFCLink(id: .rfc(9110))),
      (
        "https://datatracker.ietf.org/doc/html/rfc9110#section-15.5.1",
        RFCLink(id: .rfc(9110), section: "15.5.1")
      ),
      ("https://datatracker.ietf.org/doc/rfc9110/", RFCLink(id: .rfc(9110))),
      ("https://tools.ietf.org/html/rfc2616", RFCLink(id: .rfc(2616))),
    ])
  func `recognizes the ways RFCs get linked`(input: String, expected: RFCLink) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == expected)
  }

  /// A section is caller-supplied text, and every builder spliced it into a URL
  /// string: `appURL` force-unwrapped `URL(string:)` over it, and the web builders
  /// fell back to the page without its fragment (#150). Set as a fragment through
  /// `URLComponents`, it is percent-encoded, and it survives the way back.
  @Test func `a section with reserved characters makes every URL`() {
    let link = RFCLink(id: .rfc(9110), section: "4.2 draft#1")
    #expect(link.appURL.absoluteString == "rfc://9110#section-4.2%20draft%231")
    #expect(RFCLink(url: link.appURL) == link)
    #expect(
      link.webURL.absoluteString
        == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2%20draft%231")
    #expect(
      RFCEditorEndpoints.datatracker(.rfc(9110), section: "4.2 draft#1").absoluteString
        == "https://datatracker.ietf.org/doc/html/rfc9110#section-4.2%20draft%231")
  }

  @Test(
    arguments: [
      "https://example.com/rfc9110",
      "https://www.rfc-editor.org/",
      "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics/",
      "mailto:rfc-editor@rfc-editor.org",
    ])
  func `ignores unrelated URLs`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == nil)
  }

  @Test func `round trip`() {
    let link = RFCLink(id: .rfc(9110), section: "4.2")
    #expect(link.appURL.absoluteString == "rfc://9110#section-4.2")
    #expect(RFCLink(url: link.appURL) == link)
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
  }

  /// An appendix gets the RFC Editor's other prefix, in both URLs, so the two never
  /// name the same place differently.
  @Test func `an appendix round trips as an appendix`() {
    let link = RFCLink(id: .rfc(9110), section: "A.1")
    #expect(link.appURL.absoluteString == "rfc://9110#appendix-A.1")
    #expect(RFCLink(url: link.appURL) == link)
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#appendix-A.1")
  }

  /// A legacy RFC can number its appendices like its sections, `Appendix 1` beside
  /// section 1, and the number alone names the section. A link to such an appendix keeps
  /// its anchor for the place, so it opens the appendix and still links back to it.
  @Test func `an appendix numbered like a section stays an appendix`() throws {
    let link = try #require(RFCLink(url: URL(string: "rfc://1163#appendix-1")!))
    #expect(link.section == "appendix-1")
    #expect(link.appURL.absoluteString == "rfc://1163#appendix-1")
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc1163#appendix-1")
    #expect(RFCLink(url: URL(string: "rfc://1163#section-1")!)?.section == "1")

    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(anchor: "section-1", number: "1", title: "Introduction"),
        Section(anchor: "appendix-1", number: "1", title: "State Tables", isAppendix: true),
      ],
      source: .text)
    #expect(document.anchor(forPlace: try #require(link.section)) == "appendix-1")
    #expect(document.anchor(forPlace: "1") == "section-1")
  }

  /// A fragment that names no section is an anchor, kept as it is: the reader resolves
  /// one the document defines, such as an author's anchor, and opens at the top for
  /// one it doesn't, like the RFC Editor's `#page-12`, rather than at the reading
  /// position (#276).
  @Test(
    arguments: [
      "rfc://9000#sample-varint",
      "https://www.rfc-editor.org/rfc/rfc9000.html#sample-varint",
      "https://datatracker.ietf.org/doc/html/rfc9000#sample-varint",
    ])
  func `a fragment that names no section is kept as an anchor`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == RFCLink(id: .rfc(9000), section: "sample-varint"))
  }

  @Test func `a page fragment is kept, so the document opens at the top`() throws {
    let link = try #require(RFCLink(url: URL(string: "https://www.rfc-editor.org/rfc/rfc9110#page-12")!))
    #expect(link.section == "page-12")
  }

  /// An anchor goes back out as the fragment it came in as, not as a section's.
  @Test func `an anchor round trips as itself`() throws {
    let link = RFCLink(id: .rfc(9000), section: "sample-varint")
    #expect(link.appURL.absoluteString == "rfc://9000#sample-varint")
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9000#sample-varint")
    #expect(RFCLink(url: link.appURL) == link)
  }

  /// The prepped XML's `pn` attributes spell an appendix `section-a.1`; it is the
  /// same appendix as `appendix-A.1`.
  @Test(
    arguments: [
      ("rfc://9000#section-a.1", "A.1"),
      ("rfc://9000#appendix-a.1", "A.1"),
      ("rfc://9000#appendix-b", "B"),
      ("https://www.rfc-editor.org/rfc/rfc9000#section-a", "A"),
    ])
  func `a lower-case appendix letter names the appendix`(input: String, section: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url)?.section == section)
  }

  /// Only a single letter is an appendix's: past the prefix, `foo` is no number, and
  /// the whole fragment is the anchor, not `FOO` or `foo`.
  @Test func `a prefixed fragment that is no number stays whole`() throws {
    let link = try #require(RFCLink(url: URL(string: "rfc://9000#section-foo")!))
    #expect(link.section == "section-foo")
    #expect(link.appURL.absoluteString == "rfc://9000#section-foo")
  }
}
