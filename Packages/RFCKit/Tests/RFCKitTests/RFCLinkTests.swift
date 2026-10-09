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
  /// position (#276). It is no section, so no citation names it.
  @Test(
    arguments: [
      "rfc://9000#sample-varint",
      "https://www.rfc-editor.org/rfc/rfc9000.html#sample-varint",
      "https://datatracker.ietf.org/doc/html/rfc9000#sample-varint",
    ])
  func `a fragment that names no section is kept as an anchor`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == RFCLink(id: .rfc(9000), anchor: "sample-varint"))
    #expect(RFCLink(url: url)?.section == nil)
    #expect(RFCLink(url: url)?.place == "sample-varint")
  }

  @Test func `a page fragment is kept, so the document opens at the top`() throws {
    let link = try #require(
      RFCLink(url: URL(string: "https://www.rfc-editor.org/rfc/rfc9110#page-12")!))
    #expect(link.anchor == "page-12")
  }

  /// The prefix is the convention for a section: a bare `#4.2` is none, and no
  /// anchor either, since an XML ID cannot start with a digit.
  @Test(arguments: ["rfc://9110#4.2", "https://www.rfc-editor.org/rfc/rfc9110#4.2"])
  func `an unprefixed number is neither a section nor an anchor`(input: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url) == RFCLink(id: .rfc(9110)))
  }

  /// An anchor goes back out as the fragment it came in as, not as a section's, even
  /// when it has the shape of an appendix number, as `X.690` does.
  @Test(arguments: ["sample-varint", "X.690"])
  func `an anchor round trips as itself`(anchor: String) throws {
    let link = RFCLink(id: .rfc(9000), anchor: anchor)
    #expect(link.appURL.absoluteString == "rfc://9000#\(anchor)")
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9000#\(anchor)")
    #expect(RFCLink(url: link.appURL) == link)
    #expect(RFCLink(url: link.webURL) == link)
  }

  /// A section's anchor as the place goes out as itself, not as
  /// `appendix-section-8.3`, and comes back as the number it names.
  @Test func `a section's anchor goes out as its own fragment`() {
    let link = RFCLink(id: .rfc(9110), section: "section-8.3")
    #expect(link.appURL.absoluteString == "rfc://9110#section-8.3")
    #expect(RFCLink(url: link.appURL)?.section == "8.3")
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
    #expect(link.section == nil)
    #expect(link.anchor == "section-foo")
    #expect(link.appURL.absoluteString == "rfc://9000#section-foo")
  }

  /// A paragraph's fragment is its prepped part number, `section-4.2-3`: the number
  /// before the dash is its section's, and the whole fragment is the paragraph's anchor,
  /// not section `4.2-3`.
  @Test(arguments: ["section-4.2-3", "section-8.3-2", "appendix-A.1-4"])
  func `a paragraph's fragment is an anchor, not a section`(fragment: String) throws {
    let link = try #require(RFCLink(url: URL(string: "rfc://9000#\(fragment)")!))
    #expect(link.section == nil)
    #expect(link.anchor == fragment)
    #expect(link.appURL.absoluteString == "rfc://9000#\(fragment)")
  }

  /// A repeated legacy section is `section-1_2` (#491): the second section 1, an anchor,
  /// not section `1_2`, and so is a paragraph of it.
  @Test(arguments: ["section-1_2", "appendix-A_2", "section-1_2-3"])
  func `a repeated section's fragment is an anchor, not a section`(fragment: String) throws {
    let link = try #require(RFCLink(url: URL(string: "rfc://19#\(fragment)")!))
    #expect(link.section == nil)
    #expect(link.anchor == fragment)
  }

  /// Prep spells a top-level appendix's part number `section-appendix.a`; it is the
  /// same appendix as `appendix-A`.
  @Test(
    arguments: [
      ("rfc://9000#section-appendix.a", "A"),
      ("rfc://9000#section-appendix.b", "B"),
      ("https://www.rfc-editor.org/rfc/rfc9000#section-appendix.c", "C"),
    ])
  func `a prepped appendix part number names the appendix`(input: String, section: String) throws {
    let url = try #require(URL(string: input))
    #expect(RFCLink(url: url)?.section == section)
  }

  /// What a citation can say of a URL: the document, or one of its sections. A page
  /// about the document, or an anchor that names no section, is a link (#683).
  @Test(arguments: [
    ("https://www.rfc-editor.org/rfc/rfc4321", RFCLink(id: .rfc(4321))),
    ("http://www.rfc-editor.org/info/rfc4321", RFCLink(id: .rfc(4321))),
    (
      "https://www.rfc-editor.org/rfc/rfc4321.html#section-4.2",
      RFCLink(id: .rfc(4321), section: "4.2")
    ),
    ("https://datatracker.ietf.org/doc/html/rfc4321", RFCLink(id: .rfc(4321))),
  ])
  func `a URL to a document or its section can be cited`(address: String, expected: RFCLink)
    throws
  {
    let url = try #require(URL(string: address))
    #expect(RFCLink(citing: url) == expected)
  }

  /// Every form the Safari extension meets (#194), each keeping its section: the
  /// RFC Editor's page in any of its formats, the PDF it keeps under `pdfrfc/` among
  /// them, and Datatracker's two pages.
  @Test(arguments: [
    "https://www.rfc-editor.org/rfc/rfc4321#section-8.3",
    "https://rfc-editor.org/rfc/rfc4321.html#section-8.3",
    "https://www.rfc-editor.org/rfc/rfc4321.txt#section-8.3",
    "https://www.rfc-editor.org/rfc/rfc4321.xml#section-8.3",
    "https://www.rfc-editor.org/rfc/rfc4321.pdf#section-8.3",
    "https://www.rfc-editor.org/rfc/pdfrfc/rfc4321.txt.pdf#section-8.3",
    "https://datatracker.ietf.org/doc/html/rfc4321#section-8.3",
    "https://datatracker.ietf.org/doc/rfc4321/#section-8.3",
    "https://datatracker.ietf.org/doc/rfc4321#section-8.3",
  ])
  func `the extension opens every form of a document's page at its section`(address: String)
    throws
  {
    let url = try #require(URL(string: address))
    let link = RFCLink(id: .rfc(4321), section: "8.3")
    #expect(RFCLink(url: url) == link)
    #expect(RFCLink(documentPage: url) == link)
    #expect(RFCLink(documentPage: url)?.appURL.absoluteString == "rfc://4321#section-8.3")
  }

  /// A page about a document names it, so the toolbar button can open it, but it is
  /// not the document: someone following a link to its errata or its history wants
  /// that page, and the opt-in redirect leaves it in Safari (#194).
  @Test(arguments: [
    "https://www.rfc-editor.org/info/rfc4321",
    "https://www.rfc-editor.org/errata/rfc4321",
    "https://datatracker.ietf.org/doc/rfc4321/history/",
    "https://datatracker.ietf.org/doc/rfc4321/bibtex/",
    "https://www.rfc-editor.org/rfc/rfc4321.json",
    "https://www.rfc-editor.org/rfc/inline-errata/rfc4321.html",
  ])
  func `a page about a document is no document page`(address: String) throws {
    let url = try #require(URL(string: address))
    #expect(RFCLink(url: url) == RFCLink(id: .rfc(4321)))
    #expect(RFCLink(documentPage: url) == nil)
  }

  /// A number in a Datatracker path is no RFC unless it is spelled as one: a draft's
  /// revision, a meeting and an IPR disclosure are numbered too, and the extension
  /// would open RFC 19, 118 or 6000 for them (#194).
  @Test(arguments: [
    "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics/19/",
    "https://datatracker.ietf.org/meeting/118",
    "https://datatracker.ietf.org/ipr/6000/",
  ])
  func `a bare number on Datatracker names no RFC`(address: String) throws {
    let url = try #require(URL(string: address))
    #expect(RFCLink(url: url) == nil)
    #expect(RFCLink(documentPage: url) == nil)
  }

  /// The RFC Editor keeps a BCP's and an STD's text beside the RFCs', and the app
  /// opens those as it opens an RFC.
  @Test(arguments: [
    ("https://www.rfc-editor.org/rfc/bcp/bcp14.txt", DocumentID(series: .bcp, number: 14)),
    ("https://www.rfc-editor.org/rfc/std/std1.txt", DocumentID(series: .std, number: 1)),
  ])
  func `a BCP's or an STD's text is a document page`(address: String, id: DocumentID) throws {
    let url = try #require(URL(string: address))
    #expect(RFCLink(documentPage: url) == RFCLink(id: id))
  }

  /// Nor is the app's own link, which the extension never has to send anywhere.
  @Test(arguments: [
    "rfc://4321",
    "https://www.rfc-editor.org/",
    "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics/",
    "https://example.com/rfc/rfc4321",
  ])
  func `anything else is no document page`(address: String) throws {
    let url = try #require(URL(string: address))
    #expect(RFCLink(documentPage: url) == nil)
  }

  @Test(arguments: [
    "https://www.rfc-editor.org/errata/rfc4321",
    "https://www.rfc-editor.org/rfc/inline-errata/rfc4321.html",
    "https://datatracker.ietf.org/doc/rfc4321/history/",
    "https://www.rfc-editor.org/rfc/rfc4321.html#name-example-flows",
  ])
  func `a URL to a page about a document, or to an anchor, cannot be cited`(address: String)
    throws
  {
    let url = try #require(URL(string: address))
    #expect(RFCLink(citing: url) == nil)
  }
}
