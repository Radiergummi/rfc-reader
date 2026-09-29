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
  func `recognises the ways RFCs get linked`(input: String, expected: RFCLink) throws {
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

  /// The prefix is the convention, not decoration: an unprefixed fragment is not a
  /// section, and `#page-12` stays unrecognised rather than becoming one. Both
  /// schemes are strict about it.
  @Test(
    arguments: [
      "rfc://9110#4.2",
      "rfc://9110#page-12",
      "https://www.rfc-editor.org/rfc/rfc9110#4.2",
      "https://www.rfc-editor.org/rfc/rfc9110#page-12",
    ])
  func `an unprefixed or unrelated fragment is not a section`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == RFCLink(id: .rfc(9110)))
  }
}
