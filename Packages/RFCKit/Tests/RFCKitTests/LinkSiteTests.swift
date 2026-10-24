import Foundation
import Testing

@testable import RFCKit

/// Where a link the app hands out points (#712), and that `RFCLink` reads every one of
/// them back as the place it was made for.
@Suite("Link sites")
struct LinkSiteTests {
  private static let bcp14 = DocumentID(series: .bcp, number: 14)

  @Test(
    arguments: [
      (LinkSite.rfcEditor, RFCLink(id: .rfc(9110)), "https://www.rfc-editor.org/info/rfc9110"),
      (
        LinkSite.rfcEditor, RFCLink(id: .rfc(9110), section: "4.2"),
        "https://www.rfc-editor.org/rfc/rfc9110#section-4.2"
      ),
      (
        LinkSite.rfcEditor, RFCLink(id: .rfc(9110), section: "A.1"),
        "https://www.rfc-editor.org/rfc/rfc9110#appendix-A.1"
      ),
      (
        LinkSite.rfcEditor, RFCLink(id: .rfc(9000), anchor: "sample-varint"),
        "https://www.rfc-editor.org/rfc/rfc9000#sample-varint"
      ),
      (LinkSite.rfcEditor, RFCLink(id: bcp14), "https://www.rfc-editor.org/info/bcp14"),
      (
        LinkSite.datatracker, RFCLink(id: .rfc(9110)),
        "https://datatracker.ietf.org/doc/html/rfc9110"
      ),
      (
        LinkSite.datatracker, RFCLink(id: .rfc(9110), section: "4.2"),
        "https://datatracker.ietf.org/doc/html/rfc9110#section-4.2"
      ),
      (
        LinkSite.datatracker, RFCLink(id: .rfc(9110), section: "A.1"),
        "https://datatracker.ietf.org/doc/html/rfc9110#appendix-A.1"
      ),
      (
        LinkSite.datatracker, RFCLink(id: .rfc(9000), anchor: "sample-varint"),
        "https://datatracker.ietf.org/doc/html/rfc9000#sample-varint"
      ),
      (LinkSite.datatracker, RFCLink(id: bcp14), "https://datatracker.ietf.org/doc/html/bcp14"),
      (LinkSite.ietf, RFCLink(id: .rfc(9110)), "https://www.ietf.org/rfc/rfc9110.txt"),
      (LinkSite.app, RFCLink(id: .rfc(9110)), "rfc://9110"),
      (LinkSite.app, RFCLink(id: .rfc(9110), section: "4.2"), "rfc://9110#section-4.2"),
      (LinkSite.app, RFCLink(id: .rfc(9110), section: "A.1"), "rfc://9110#appendix-A.1"),
      (
        LinkSite.app, RFCLink(id: .rfc(9000), anchor: "sample-varint"),
        "rfc://9000#sample-varint"
      ),
      (LinkSite.app, RFCLink(id: bcp14, section: "2"), "rfc://bcp14#section-2"),
    ])
  func `each site has its own shape and reads back as the same place`(
    site: LinkSite, link: RFCLink, expected: String
  ) {
    let url = site.url(for: link)
    #expect(url.absoluteString == expected)
    #expect(RFCLink(url: url) == link)
  }

  /// The plain text has no anchors: a section, or an anchor, links to the document.
  @Test(
    arguments: [
      RFCLink(id: .rfc(9110), section: "4.2"), RFCLink(id: .rfc(9110), section: "A.1"),
      RFCLink(id: .rfc(9000), anchor: "sample-varint"),
    ])
  func `a section on ietf.org is the document`(link: RFCLink) {
    let url = LinkSite.ietf.url(for: link)
    #expect(url.fragment == nil)
    #expect(RFCLink(url: url) == RFCLink(id: link.id))
  }

  /// A series has no page of its own sections on the web, and ietf.org has no copy
  /// of an STD or an FYI (curl-checked): the link is to the series' page, and the
  /// plain text's site links to the RFC Editor's.
  @Test(
    arguments: [
      (
        LinkSite.rfcEditor, RFCLink(id: bcp14, section: "2"),
        "https://www.rfc-editor.org/info/bcp14"
      ),
      (
        LinkSite.rfcEditor, RFCLink(id: bcp14, anchor: "intro"),
        "https://www.rfc-editor.org/info/bcp14"
      ),
      (
        LinkSite.datatracker, RFCLink(id: bcp14, section: "2"),
        "https://datatracker.ietf.org/doc/html/bcp14"
      ),
      (LinkSite.ietf, RFCLink(id: bcp14), "https://www.rfc-editor.org/info/bcp14"),
      (
        LinkSite.ietf, RFCLink(id: DocumentID(series: .std, number: 97), section: "2"),
        "https://www.rfc-editor.org/info/std97"
      ),
    ])
  func `a series on the web is the series' page`(site: LinkSite, link: RFCLink, expected: String) {
    let url = site.url(for: link)
    #expect(url.absoluteString == expected)
    #expect(RFCLink(url: url) == RFCLink(id: link.id))
  }

  /// What every export writes, whatever Settings chose.
  @Test func `a web URL is the RFC Editor's`() {
    for link in [
      RFCLink(id: .rfc(9110)), RFCLink(id: .rfc(9110), section: "4.2"),
      RFCLink(id: .rfc(9000), anchor: "sample-varint"),
    ] {
      #expect(link.webURL == LinkSite.rfcEditor.url(for: link))
    }
  }

  /// An export, and the legacy pack's XML, keep a series' section in its link, as
  /// they did before the sites (#712): the app reads the link back to the section.
  @Test func `a web URL keeps a series' section`() {
    let link = RFCLink(id: Self.bcp14, section: "2")
    #expect(link.webURL.absoluteString == "https://www.rfc-editor.org/rfc/bcp14#section-2")
    #expect(RFCLink(url: link.webURL) == link)
  }
}
