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
  /// and the rich flavor is not Markdown, so neither is escaped.
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

  /// The plain text is the Markdown: a web page reads only plain text and HTML, so
  /// GitHub gets its `>` quote only from the plain text, and Slack and chat apps paste
  /// plain text too.
  @Test func `the plain text is the markdown`() throws {
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
    #expect(quote.plainText == quote.markdown)
    #expect(quote.plainText.hasPrefix("> Send"))
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

  /// The document alone is cited by its info page, in the HTML as in the Markdown.
  @Test func `the citation links the info page in html`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "Quoted."), document: .rfc(9110), section: nil)
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
  @Test func `the rich flavor links the citation`() throws {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "Quoted."), document: .rfc(9110), section: "8.3")
    #expect(quote.rich.string == "Quoted.\n\n— RFC 9110, Section 8.3")
    let label = (quote.rich.string as NSString).range(of: "RFC 9110, Section 8.3")
    let link = try #require(
      quote.rich.attribute(.link, at: label.location, effectiveRange: nil) as? URL)
    #expect(link.absoluteString == "https://www.rfc-editor.org/rfc/rfc9110#section-8.3")
  }

  /// A selection dragged from the end of one section's last line opens on that
  /// section's line break, but quotes only the next section: that is the one cited.
  @Test func `a selection opening on the previous section's line break cites the next`() throws {
    let built = DocumentTextBuilder.build(
      RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [
          Section(
            anchor: "section-1", number: "1", title: "One",
            blocks: [.paragraph(Paragraph(text: "Earlier."))]),
          Section(
            anchor: "section-2", number: "2", title: "Two",
            blocks: [.paragraph(Paragraph(text: "Later."))]),
        ],
        source: .xml),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "Earlier.", in: built.text) + "Earlier.".utf16.count
    let end = try Fixtures.offset(of: "Later.", in: built.text) + "Later.".utf16.count
    let quote = try #require(
      QuoteCitation.quote(
        of: NSRange(location: start, length: end - start), in: built, document: .rfc(9110)))
    #expect(quote.markdown.hasSuffix("(https://www.rfc-editor.org/rfc/rfc9110#section-2)"))
  }

  /// A figure's own fence line would close a fence of the same length, and the rest of
  /// the figure would render as Markdown.
  @Test func `a figure holding a fence is fenced by a longer one`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "```\ncode\n```"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "```", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown.hasPrefix(
        """
        > ````
        > ```
        > code
        > ```
        > ````

        """))
  }

  /// Two blocks in a row are two figures, not one: they are told apart by their box.
  @Test func `two figures in a row are fenced apart`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .artwork, text: "+--+")),
        .preformatted(Preformatted(kind: .artwork, text: "+==+"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "+--+", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown.hasPrefix(
        """
        > ```
        > +--+
        > ```
        >
        > ```
        > +==+
        > ```

        """))
    #expect(quote.html.contains("<pre>+--+</pre>\n<pre>+==+</pre>"))
  }

  /// The reader labels source code with its type, which is not part of the code: the
  /// label is the fence's info string, and nowhere in the quote's lines.
  @Test func `a source code label is the fence's info string`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .sourceCode, text: "rule = 1*DIGIT", type: "abnf"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "ABNF", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    #expect(
      quote.markdown.hasPrefix(
        """
        > ```abnf
        > rule = 1*DIGIT
        > ```

        """))
    #expect(quote.html.contains("<pre>rule = 1*DIGIT</pre>"))
    #expect(quote.rich.string.hasPrefix("rule = 1*DIGIT\n"))
  }

  /// Rich targets lay a figure out in the font they are given: a proportional one
  /// breaks its columns.
  @Test func `the rich flavor sets a figure in a fixed-pitch font`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "As drawn:")),
        .preformatted(Preformatted(kind: .artwork, text: "+--+"))),
      style: ReadingStyle())
    let start = try Fixtures.offset(of: "As drawn", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let quote = QuoteCitation.quote(of: selection, document: .rfc(9110), section: nil)
    let figure = (quote.rich.string as NSString).range(of: "+--+")
    let font = try #require(
      quote.rich.attribute(.font, at: figure.location, effectiveRange: nil) as? PlatformFont)
    #if canImport(UIKit)
      #expect(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    #else
      #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #endif
    #expect(quote.rich.attribute(.font, at: 0, effectiveRange: nil) == nil)
  }
}
