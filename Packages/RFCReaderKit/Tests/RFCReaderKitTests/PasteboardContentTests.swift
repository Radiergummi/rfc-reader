import Foundation
import RFCKit
import Testing
import UniformTypeIdentifiers

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What every copy puts on the pasteboard (#778): one answer per kind of copy, the
/// same on both platforms, written by one `Clipboard`.
@Suite("Pasteboard content")
struct PasteboardContentTests {
  private let reference = Inline.crossReference(
    CrossReference(target: .document(.rfc(9110), section: nil)))
  private let published = URL(string: "https://example.org/rfc9110")!

  /// The reader's link as a public URL, as `LinkCopy.publicURL` would give it.
  private func publicURL(_ link: URL) -> URL? {
    RFCLink(url: link)?.id == .rfc(9110) ? published : nil
  }

  private func types(_ content: PasteboardContent) -> [UTType] {
    content.flavors.map(\.type)
  }

  private func text(_ content: PasteboardContent, _ type: UTType) -> String? {
    guard case .text(let text)? = content.value(for: type) else { return nil }
    return text
  }

  private func richText(_ content: PasteboardContent) throws -> NSAttributedString {
    guard case .data(let data)? = content.value(for: .rtf) else {
      throw CancellationError()
    }
    return try NSAttributedString(
      data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil)
  }

  // MARK: - A selection

  /// iOS copied plain text alone, the Mac its rich text too (#778).
  @Test func `a selection carries rich text, rich text with images, HTML and plain text`() {
    let content = PasteboardContent.selection(
      Fixtures.inlineRun([.text("see "), reference]), publicURL: publicURL)
    #expect(types(content) == [.flatRTFD, .rtf, .html, .utf8PlainText])
    #expect(text(content, .utf8PlainText) == "see [RFC 9110]")
  }

  /// A link of the reader's opens nothing outside it, in a rich paste as in Copy Link.
  @Test func `a selection's rich text links a reference to its public URL`() throws {
    let rich = try richText(
      .selection(Fixtures.inlineRun([.text("see "), reference]), publicURL: publicURL))
    var links: [URL] = []
    rich.enumerateAttribute(.link, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
      if let url = value as? URL ?? (value as? String).flatMap(URL.init(string:)) {
        links.append(url)
      }
    }
    #expect(links.contains(published))
    #expect(!links.contains { $0.scheme == "rfc" })
  }

  @Test func `a reference with no public URL is no link in the rich text`() throws {
    let rich = try richText(
      .selection(Fixtures.inlineRun([.text("see "), reference]), publicURL: { _ in nil }))
    var linked = false
    rich.enumerateAttribute(.link, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
      if value != nil { linked = true }
    }
    #expect(!linked)
  }

  @Test func `a selection's HTML links a reference to its public URL, by its label`() {
    let content = PasteboardContent.selection(
      Fixtures.inlineRun([.text("see <this> "), reference]), publicURL: publicURL)
    #expect(
      text(content, .html)
        == """
        <meta charset="utf-8">
        <p>see &lt;this&gt; <a href="https://example.org/rfc9110">[RFC 9110]</a></p>
        """)
  }

  @Test func `a reference with no public URL is its label in the HTML`() {
    let content = PasteboardContent.selection(
      Fixtures.inlineRun([reference]), publicURL: { _ in nil })
    #expect(text(content, .html) == "<meta charset=\"utf-8\">\n<p>[RFC 9110]</p>")
  }

  @Test func `a selection's HTML sets a figure as its lines, in a pre`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "First paragraph.")),
        .preformatted(Preformatted(kind: .artwork, text: "+--+\n  |  |\n\n+--+")),
        .paragraph(Paragraph(text: "Second paragraph."))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "First", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    #expect(
      text(.selection(selection, publicURL: publicURL), .html)
        == """
        <meta charset="utf-8">
        <p>First paragraph.</p>
        <pre>+--+
          |  |

        +--+</pre>
        <p>Second paragraph.</p>
        """)
  }

  // MARK: - A figure

  /// A diagram pasted as an image from one gesture and as ASCII from the others
  /// (#778): every figure copy carries the drawing where there is one.
  @Test func `a figure is its text, and its drawing where it is drawn`() {
    let figure = Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+")
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let drawn = PasteboardContent.figure(figure, png: png)
    #expect(types(drawn) == [.utf8PlainText, .png])
    #expect(text(drawn, .utf8PlainText) == FigureCopy.pasteboardText(for: figure))
    #expect(drawn.value(for: .png) == .data(png))
    #expect(types(.figure(figure, png: nil)) == [.utf8PlainText])
  }

  // MARK: - A link and a quote

  @Test func `a link is its URL, as text, and its label linked to it`() {
    let link = LinkCopy(url: published, label: "RFC 9110: HTTP Semantics")
    let content = PasteboardContent.link(link)
    #expect(types(content) == [.url, .utf8PlainText, .html, .rtf])
    #expect(text(content, .url) == published.absoluteString)
    #expect(text(content, .utf8PlainText) == published.absoluteString)
    #expect(text(content, .html) == link.html)
  }

  @Test func `a quote is its Markdown, as plain text and as Markdown, its HTML and its RTF`() {
    let quote = QuoteCitation.quote(
      of: Fixtures.inlineRun([.text("quoted")]), document: .rfc(9110), section: "4.2")
    let content = PasteboardContent.quote(quote)
    #expect(
      types(content) == [
        .utf8PlainText, UTType(importedAs: QuoteCitation.Quote.markdownType), .html, .rtf,
      ])
    #expect(text(content, .utf8PlainText) == quote.markdown)
  }

  @Test func `plain text is plain text alone`() {
    #expect(PasteboardContent.text("BibTeX").flavors == [.init(.utf8PlainText, .text("BibTeX"))])
  }
}

/// The URL anyone can open for a link in the reader, or the link itself where it is
/// the web's already (#778).
@Suite("Public URL")
struct PublicURLTests {
  private let bibliography = [
    ReferenceGroup(
      title: "Normative References", entries: [Reference(anchor: "Unlinked", title: "A Paper")])
  ]

  private func publicURL(_ string: String) -> URL? {
    LinkCopy.publicURL(
      for: URL(string: string)!, from: .rfc(9110), in: nil, bibliography: bibliography)
  }

  @Test func `a reader's link is its public URL`() {
    #expect(publicURL("rfc://7932")?.absoluteString == "https://www.rfc-editor.org/info/rfc7932")
  }

  @Test func `a link to the web is itself`() {
    #expect(publicURL("https://www.iana.org/")?.absoluteString == "https://www.iana.org/")
  }

  @Test func `a reader's link with nothing to hand out has none`() {
    #expect(publicURL("\(DocumentTextBuilder.referenceScheme):Unlinked") == nil)
  }
}
