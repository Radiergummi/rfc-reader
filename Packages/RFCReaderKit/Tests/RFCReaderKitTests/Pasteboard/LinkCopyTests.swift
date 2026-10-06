import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What Copy and Share on a reference's long-press menu hand out (#431): the
/// rfc-editor.org URL, never the reader's own `rfc://`.
@Suite("Link copy")
struct LinkCopyTests {
  private let current = DocumentID.rfc(9110)
  private let index = RFCIndex(
    rfcs: [
      RFCMetadata(id: .rfc(9110), title: "HTTP Semantics", date: PublicationDate(year: 2022)),
      RFCMetadata(
        id: .rfc(7932), title: "Brotli Compressed Data Format",
        date: PublicationDate(year: 2016)),
    ],
    series: [])
  private let bibliography = [
    ReferenceGroup(
      title: "Normative References",
      entries: [
        Reference(
          anchor: "ISO.8601", title: "Date and time format",
          url: URL(string: "https://www.iso.org/iso-8601-date-and-time-format.html")),
        Reference(anchor: "Unlinked", title: "A Paper"),
      ])
  ]

  private func copy(_ string: String) -> LinkCopy? {
    LinkCopy.forLink(
      URL(string: string)!, from: current, in: index, bibliography: bibliography)
  }

  @Test func `another RFC is its rfc-editor.org page, labelled with its title`() {
    #expect(
      copy("rfc://7932")
        == LinkCopy(
          url: URL(string: "https://www.rfc-editor.org/info/rfc7932")!,
          label: "RFC 7932: Brotli Compressed Data Format"))
  }

  @Test func `a section of another RFC keeps its section`() {
    #expect(
      copy("rfc://7932#section-4.2")?.url.absoluteString
        == "https://www.rfc-editor.org/rfc/rfc7932#section-4.2")
  }

  @Test func `an anchor in this document is this document's page at that anchor`() {
    #expect(
      copy("\(DocumentTextBuilder.anchorScheme):section-4.2")
        == LinkCopy(
          url: URL(string: "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")!,
          label: "RFC 9110: HTTP Semantics"))
  }

  @Test func `an RFC the index does not know is labelled with its designation`() {
    #expect(copy("rfc://1149")?.label == "RFC 1149")
  }

  @Test func `a bibliography entry is the URL it names, labelled with its title`() {
    #expect(
      copy("\(DocumentTextBuilder.referenceScheme):ISO.8601")
        == LinkCopy(
          url: URL(string: "https://www.iso.org/iso-8601-date-and-time-format.html")!,
          label: "Date and time format"))
  }

  @Test func `a bibliography entry that names no URL has nothing to copy`() {
    #expect(copy("\(DocumentTextBuilder.referenceScheme):Unlinked") == nil)
  }

  @Test func `a link to the web is not the reader's to copy`() {
    #expect(copy("https://www.iana.org/assignments/") == nil)
  }

  @Test func `the HTML link escapes its label and its URL`() {
    let link = LinkCopy(
      url: URL(string: "https://example.com/?a=1&b=2")!, label: "A <b> & \"c\" 'd'")
    #expect(
      link.html
        == """
        <meta charset="utf-8">
        <a href="https://example.com/?a=1&amp;b=2">A &lt;b&gt; &amp; &quot;c&quot; &#39;d&#39;</a>
        """)
  }

  /// A bibliography title is often not ASCII, and a target reading the flavor as
  /// Latin-1 garbles it without the charset (#775).
  @Test func `the HTML link of a non-ASCII title declares its charset`() {
    let link = LinkCopy(
      url: URL(string: "https://example.com/")!, label: "Zürich — Ångström")
    #expect(link.html.hasPrefix("<meta charset=\"utf-8\">\n"))
    #expect(link.html.hasSuffix(">Zürich — Ångström</a>"))
  }

  @Test func `the RTF reads back as the label, linked to the URL`() throws {
    let link = try #require(copy("rfc://7932"))
    let data = try #require(link.rtf)
    let text = try NSAttributedString(
      data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil)
    #expect(text.string == link.label)
    let value = text.attribute(.link, at: 0, effectiveRange: nil)
    let url = value as? URL ?? (value as? String).flatMap(URL.init(string:))
    #expect(url == link.url)
  }
}
