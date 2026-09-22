import Foundation
import Testing
@testable import RFCKit

@Suite("Links")
struct RFCLinkTests {
    @Test("recognises the ways RFCs get linked", arguments: [
        ("rfc://9110", RFCLink(id: .rfc(9110))),
        ("rfc://9110#section-4.2", RFCLink(id: .rfc(9110), section: "4.2")),
        ("rfc://9110#appendix-A.1", RFCLink(id: .rfc(9110), section: "A.1")),
        ("rfc://bcp14", RFCLink(id: DocumentID(series: .bcp, number: 14))),
        ("https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2", RFCLink(id: .rfc(9110), section: "4.2")),
        ("https://www.rfc-editor.org/rfc/rfc9110#appendix-A", RFCLink(id: .rfc(9110), section: "A")),
        ("https://www.rfc-editor.org/info/rfc9110", RFCLink(id: .rfc(9110))),
        ("https://www.rfc-editor.org/rfc/rfc9110.txt", RFCLink(id: .rfc(9110))),
        ("https://www.rfc-editor.org/errata/rfc9110", RFCLink(id: .rfc(9110))),
        ("https://datatracker.ietf.org/doc/html/rfc9110#section-15.5.1", RFCLink(id: .rfc(9110), section: "15.5.1")),
        ("https://datatracker.ietf.org/doc/rfc9110/", RFCLink(id: .rfc(9110))),
        ("https://tools.ietf.org/html/rfc2616", RFCLink(id: .rfc(2616))),
    ])
    func parses(input: String, expected: RFCLink) throws {
        let url = try #require(URL(string: input))
        #expect(RFCLink(url: url) == expected)
    }

    @Test("ignores unrelated URLs", arguments: [
        "https://example.com/rfc9110",
        "https://www.rfc-editor.org/",
        "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics/",
        "mailto:rfc-editor@rfc-editor.org",
    ])
    func rejects(input: String) throws {
        let url = try #require(URL(string: input))
        #expect(RFCLink(url: url) == nil)
    }

    @Test func roundTrip() {
        let link = RFCLink(id: .rfc(9110), section: "4.2")
        #expect(link.appURL.absoluteString == "rfc://9110#section-4.2")
        #expect(RFCLink(url: link.appURL) == link)
        #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
    }

    /// An appendix gets the RFC Editor's other prefix, in both URLs, so the two never
    /// name the same place differently.
    @Test func anAppendixRoundTripsAsAnAppendix() {
        let link = RFCLink(id: .rfc(9110), section: "A.1")
        #expect(link.appURL.absoluteString == "rfc://9110#appendix-A.1")
        #expect(RFCLink(url: link.appURL) == link)
        #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#appendix-A.1")
    }

    /// The prefix is the convention, not decoration: an unprefixed fragment is not a
    /// section, and `#page-12` stays unrecognised rather than becoming one. Both
    /// schemes are strict about it.
    @Test("an unprefixed or unrelated fragment is not a section", arguments: [
        "rfc://9110#4.2",
        "rfc://9110#page-12",
        "https://www.rfc-editor.org/rfc/rfc9110#4.2",
        "https://www.rfc-editor.org/rfc/rfc9110#page-12",
    ])
    func rejectsFragment(input: String) throws {
        let url = try #require(URL(string: input))
        #expect(RFCLink(url: url) == RFCLink(id: .rfc(9110)))
    }
}
