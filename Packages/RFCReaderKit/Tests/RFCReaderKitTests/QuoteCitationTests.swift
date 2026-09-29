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

  // MARK: What goes on the pasteboard

  @Test func `the markdown quotes every line and cites the section`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "A sender MUST NOT generate this.\nIt is optional."),
      document: .rfc(9110), section: "8.3")
    #expect(
      quote.markdown == """
        > A sender MUST NOT generate this.
        > It is optional.

        — [RFC 9110, Section 8.3](https://www.rfc-editor.org/rfc/rfc9110#section-8.3)
        """)
  }

  /// A blank line inside the quote stays inside it, as `>` alone; the selection's
  /// own trailing line break adds no empty quoted line.
  @Test func `blank and trailing lines are kept inside the quote`() {
    let quote = QuoteCitation.quote(
      of: NSAttributedString(string: "First paragraph.\n\nSecond paragraph.\n"),
      document: .rfc(9110), section: nil)
    #expect(
      quote.markdown == """
        > First paragraph.
        >
        > Second paragraph.

        — [RFC 9110](https://www.rfc-editor.org/info/rfc9110)
        """)
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
