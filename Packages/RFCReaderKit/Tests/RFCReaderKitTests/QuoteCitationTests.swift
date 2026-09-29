import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Copy as Quote: the selected text, and a citation of where it was taken from (#186).
@Suite("Quote citation")
struct QuoteCitationTests {
  private let anchors = AnchorIndex([
    .init(anchor: "abstract", offset: 0),
    .init(anchor: "section-8", offset: 100, heading: "8. Content", number: "8"),
    .init(anchor: "figure-3", offset: 150),
    .init(anchor: "section-8.3", offset: 200, heading: "8.3. Content-Type", number: "8.3"),
    .init(anchor: "acknowledgements", offset: 300, heading: "Acknowledgements"),
  ])

  // MARK: Which section

  @Test func `a selection is cited from the section it starts in`() {
    #expect(QuoteCitation.section(at: 210, anchors: anchors) == "8.3")
    #expect(QuoteCitation.section(at: 200, anchors: anchors) == "8.3")
  }

  /// A figure's anchor is not a section: the citation names what a reader looks up.
  @Test func `only a section anchor counts`() {
    #expect(QuoteCitation.section(at: 160, anchors: anchors) == "8")
  }

  /// An unnumbered section has nothing to cite it by, so the document alone.
  @Test func `an unnumbered section cites the document`() {
    #expect(QuoteCitation.section(at: 310, anchors: anchors) == nil)
  }

  /// Before the first section, in the abstract or the header, the document alone.
  @Test func `a selection before any section cites the document`() {
    #expect(QuoteCitation.section(at: 20, anchors: anchors) == nil)
  }

  /// A range of the reader's text is quoted from its own section, which the build
  /// alone knows, and one that selects nothing, or runs past the text, quotes nothing.
  @Test func `a range of the built text is quoted from its section`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph(text: "Quoted."))), style: ReadingStyle())
    let start = try Fixtures.offset(of: "Quoted", in: built.text)
    let quote = try #require(
      QuoteCitation.quote(
        of: NSRange(location: start, length: 7), in: built, document: .rfc(9110)))
    #expect(
      quote.markdown.hasSuffix(
        "— [RFC 9110, Section 1](https://www.rfc-editor.org/rfc/rfc9110#section-1)"))
    #expect(
      QuoteCitation.quote(
        of: NSRange(location: start, length: 0), in: built, document: .rfc(9110))
        == nil)
    #expect(
      QuoteCitation.quote(
        of: NSRange(location: start, length: built.text.length), in: built, document: .rfc(9110))
        == nil)
  }

  // MARK: What goes on the pasteboard

  @Test func `the markdown quotes the selection and cites the section`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "A sender MUST NOT generate this.\nIt is optional."),
      document: .rfc(9110), section: "8.3")
    #expect(
      quote.markdown == """
        > A sender MUST NOT generate this.
        >
        > It is optional.

        — [RFC 9110, Section 8.3](https://www.rfc-editor.org/rfc/rfc9110#section-8.3)
        """)
  }

  /// The reader ends a paragraph with one line break and draws the gap between
  /// paragraphs as spacing, so every paragraph of the selection is quoted as one of
  /// its own, or Markdown runs them together.
  @Test func `paragraphs stay apart in the quote`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "First paragraph.")),
        .paragraph(Paragraph(text: "Second paragraph."))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "First", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown == """
        > First paragraph.
        >
        > Second paragraph.

        — [RFC 9110](https://www.rfc-editor.org/info/rfc9110)
        """)
    #expect(quote.rich.string == "First paragraph.\n\nSecond paragraph.\n\n— RFC 9110")
  }

  /// A figure's lines are its layout: fenced, so Markdown neither reflows them nor
  /// collapses their spaces.
  @Test func `a figure keeps its lines in a fence`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "As drawn:")),
        .preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n\n+--+"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "As drawn", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown.hasPrefix(
        """
        > As drawn:
        >
        > ```
        > +--+
        > |  |
        >
        > +--+
        > ```

        """))
  }

  /// GitHub drops what reads as an HTML tag, a `<field-name>` among them, so the
  /// Markdown writes a `<` in prose as an entity. A fence takes its lines literally,
  /// and the rich flavour is not Markdown, so neither is escaped.
  @Test func `a less-than sign is escaped in prose and nowhere else`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "Send <field-name> & more > less.")),
        .preformatted(Preformatted(kind: .artwork, text: "<a> -> <b>"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "Send", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown.hasPrefix(
        """
        > Send &lt;field-name> & more > less.
        >
        > ```
        > <a> -> <b>
        > ```

        """))
    #expect(quote.rich.string.hasPrefix("Send <field-name> & more > less.\n\n<a> -> <b>"))
  }

  /// Plain text is for where Markdown is not rendered: the quote as it reads, with no
  /// `>`, fence, entity or link syntax, paragraphs a blank line apart, a figure's lines
  /// and indentation as drawn, and the citation with its URL spelled out.
  @Test func `the plain text is the quote without markdown syntax`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "Send <field-name> & more.")),
        .paragraph(Paragraph(text: "As drawn:")),
        .preformatted(Preformatted(kind: .artwork, text: "+--+\n  |  |\n\n+--+"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "Send", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: "8.3")
    #expect(
      quote.plainText == """
        Send <field-name> & more.

        As drawn:

        +--+
          |  |

        +--+

        — RFC 9110, Section 8.3, https://www.rfc-editor.org/rfc/rfc9110#section-8.3
        """)
  }

  /// HTML is a blockquote of one paragraph per paragraph and one `pre` per figure, and
  /// the citation a link after it.
  @Test func `the html quotes paragraphs and figures and links the citation`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "First paragraph.")),
        .preformatted(Preformatted(kind: .artwork, text: "+--+\n  |  |\n\n+--+")),
        .paragraph(Paragraph(text: "Second paragraph."))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "First", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: "8.3")
    #expect(
      quote.html == """
        <meta charset="utf-8">
        <blockquote>
        <p>First paragraph.</p>
        <pre>+--+
          |  |

        +--+</pre>
        <p>Second paragraph.</p>
        </blockquote>
        <p>— <cite><a href="https://www.rfc-editor.org/rfc/rfc9110#section-8.3">RFC 9110, Section 8.3</a></cite></p>
        """)
  }

  /// Markup characters in the quote are text, in prose and in a figure alike.
  @Test func `the html escapes markup characters`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "Send <field-name> & \"quoted\" 'value'.")),
        .preformatted(Preformatted(kind: .artwork, text: "<a> -> <b> & \"c\""))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "Send", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.html.contains(
        "<p>Send &lt;field-name&gt; &amp; &quot;quoted&quot; &#39;value&#39;.</p>"))
    #expect(quote.html.contains("<pre>&lt;a&gt; -&gt; &lt;b&gt; &amp; &quot;c&quot;</pre>"))
  }

  /// The document alone is cited by its info page, in every flavour.
  @Test func `the citation names its url in plain text and links it in html`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "Quoted."), document: .rfc(9110), section: nil)
    #expect(quote.plainText == "Quoted.\n\n— RFC 9110, https://www.rfc-editor.org/info/rfc9110")
    #expect(
      quote.html.hasSuffix(
        "<p>— <cite><a href=\"https://www.rfc-editor.org/info/rfc9110\">RFC 9110</a></cite></p>"))
  }

  @Test func `an appendix is cited as one`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "Text."), document: .rfc(9110), section: "A")
    #expect(
      quote.markdown.hasSuffix(
        "— [RFC 9110, Appendix A](https://www.rfc-editor.org/rfc/rfc9110#appendix-A)"))
  }

  /// A reference in the selection reads as its label, the way Copy writes it, never as
  /// the chip's attachment character.
  @Test func `a reference inside the quote reads as its label`() {
    let text = NSMutableAttributedString(string: "as defined in ")
    text.append(
      NSAttributedString(
        string: "\u{FFFC}\u{2060}RFC\u{00A0}9111",
        attributes: [
          .rfcReference: ReferenceBox(CrossReference(target: .document(.rfc(9111), section: nil)))
        ]))
    let quote = QuoteCitation.quote(of: text, document: .rfc(9110), section: "8.3")
    #expect(quote.markdown.hasPrefix("> as defined in [RFC 9111]\n"))
  }

  /// Rich text has the quote as text and the citation as a real link, with none of the
  /// Markdown syntax.
  @Test func `the rich flavour links the citation`() throws {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "Quoted."), document: .rfc(9110), section: "8.3")
    #expect(quote.rich.string == "Quoted.\n\n— RFC 9110, Section 8.3")
    let label = (quote.rich.string as NSString).range(of: "RFC 9110, Section 8.3")
    let link = try #require(
      quote.rich.attribute(.link, at: label.location, effectiveRange: nil) as? URL)
    #expect(link.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#section-8.3")
  }
}
