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
    .init(anchor: "section-8", offset: 100, heading: "8. Content"),
    .init(anchor: "figure-3", offset: 150),
    .init(anchor: "section-8.3", offset: 200, heading: "8.3. Content-Type"),
  ])
  private let numbers = ["section-8": "8", "section-8.3": "8.3", "appendix-a": "A"]

  // MARK: Which section

  @Test func `a selection is cited from the section it starts in`() {
    #expect(QuoteCitation.section(at: 210, anchors: anchors, numbers: numbers) == "8.3")
    #expect(QuoteCitation.section(at: 200, anchors: anchors, numbers: numbers) == "8.3")
  }

  /// A figure's anchor is not a section: the citation names what a reader looks up.
  @Test func `only a section anchor counts`() {
    #expect(QuoteCitation.section(at: 160, anchors: anchors, numbers: numbers) == "8")
  }

  /// Before the first section, in the abstract or the header, the document alone.
  @Test func `a selection before any section cites the document`() {
    #expect(QuoteCitation.section(at: 20, anchors: anchors, numbers: numbers) == nil)
  }

  /// A range of the reader's text is quoted from its own section, and one that
  /// selects nothing, or runs past the text, quotes nothing.
  @Test func `a range of the built text is quoted from its section`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph(text: "Quoted."))), style: ReadingStyle())
    let start = try Fixtures.offset(of: "Quoted", in: built.text)
    let numbers = ["section-1": "1"]
    let quote = try #require(
      QuoteCitation.quote(
        of: NSRange(location: start, length: 7), in: built, document: .rfc(9110),
        sectionNumbers: numbers))
    #expect(
      quote.markdown.hasSuffix(
        "— [RFC 9110, Section 1](https://www.rfc-editor.org/rfc/rfc9110#section-1)"))
    #expect(
      QuoteCitation.quote(
        of: NSRange(location: start, length: 0), in: built, document: .rfc(9110),
        sectionNumbers: numbers) == nil)
    #expect(
      QuoteCitation.quote(
        of: NSRange(location: start, length: built.text.length), in: built, document: .rfc(9110),
        sectionNumbers: numbers) == nil)
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
