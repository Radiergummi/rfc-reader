import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A figure's card ends a padding past its widest line, not at the column's edge:
/// on a wide window a narrow diagram sat at the left of a card twice its width.
/// Every other card, code, plain artwork or a table, spans the column.
@Suite("Card width: a figure's card hugs its content")
struct CardWidthTests {
  private let padding: CGFloat = 10
  private let line = CGRect(x: 0, y: 100, width: 40, height: 20)

  private func card(contentWidth: CGFloat?, indent: CGFloat = 0) -> CGRect {
    FragmentGeometry.Placement(
      origin: CGPoint(x: 0, y: 100), frame: line, containerWidth: 600, indent: indent,
      contentWidth: contentWidth
    ).decorationRect(padding: padding, capTop: false, capBottom: false)
  }

  @Test func `a card ends a padding past its content`() {
    #expect(card(contentWidth: 200).width == 200 + padding * 2)
  }

  @Test func `a card as wide as the column or wider is the column's width`() {
    #expect(card(contentWidth: 800).width == 600 + padding * 2)
    #expect(card(contentWidth: 800, indent: 40).width == 560 + padding * 2)
  }

  @Test func `a card with no content width spans the column`() {
    #expect(card(contentWidth: nil).width == 600 + padding * 2)
  }

  /// The frame holds the paragraph's spacing; a capped end leaves it out, so the
  /// spacing is the margin between the card and the text around it.
  @Test func `a capped end leaves the paragraph's spacing out`() {
    let placement = FragmentGeometry.Placement(
      origin: CGPoint(x: 0, y: 100), frame: line, containerWidth: 600, indent: 0,
      spacingBefore: 6, spacingAfter: 14)
    let capped = placement.decorationRect(padding: padding, capTop: true, capBottom: true)
    #expect(capped.minY == 100 + 6 - padding / 2)
    #expect(capped.maxY == 100 + line.height - 14 + padding * 1.5)
    let open = placement.decorationRect(padding: padding, capTop: false, capBottom: false)
    #expect(open.minY == 100)
    #expect(open.maxY == 100 + line.height)
  }

  /// Every line of a figure reports the same width, or the card's right edge would
  /// step line by line: the staircase again, on the other side.
  @Test func `every line of a figure reports its widest line`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let text = built.text.string as NSString
    var widths: [CGFloat] = []
    for needle in ["Type", "Value"] {
      let location = text.range(of: needle).location
      let fragment = text.paragraphRange(for: NSRange(location: location, length: 0))
      let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: fragment))
      widths.append(try #require(span.contentWidth))
    }
    #expect(widths[0] == widths[1])
  }

  /// A character the monospaced font sets wider than a column, or lacks and takes
  /// from a fallback font, still ends inside the card: the card is as wide as the
  /// line is set, not as its characters count.
  @Test func `a line with a wide character is measured as it is set`() throws {
    let style = ReadingStyle()
    let wide = "key = \u{4E2D}\u{6587}\u{6587}\u{4E2D}\u{6587}\u{6587}"
    let laidOut = DocumentTextBuilder.lineWidth(
      NSAttributedString(string: wide, attributes: [.font: style.monospacedFont(scale: 1)]))
    let width = DocumentTextBuilder(style: style).widestLine(of: "x = 1\n" + wide, scale: 1)
    #expect(width >= laidOut - 0.5, "\(width) against \(laidOut)")
  }

  @Test(arguments: [
    Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"),
    Preformatted(kind: .sourceCode, text: "x = 1"),
    Preformatted(kind: .sourceCode, text: #"{ "a": true }"#, type: "json"),
  ])
  func `a card that is not a figure's spans the column`(content: Preformatted) throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(content)), style: ReadingStyle())
    let location = try Fixtures.offset(of: String(content.text.prefix(3)), in: built.text)
    let fragment = (built.text.string as NSString).paragraphRange(
      for: NSRange(location: location, length: 0))
    let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: fragment))
    #expect(span.contentWidth == nil)
  }

  @Test func `a table's card spans the column`() throws {
    let built = DocumentTextBuilder.build(
      try Fixtures.document(named: "rfc8761.xml"), style: ReadingStyle())
    var checked = false
    built.text.enumerateAttribute(
      .rfcDecoration, in: NSRange(location: 0, length: built.text.length)
    ) { value, range, stop in
      guard RFCDecoration(attributeValue: value) == .table else { return }
      #expect(FragmentGeometry.decorationSpan(in: built.text, fragment: range)?.contentWidth == nil)
      checked = true
      stop.pointee = true
    }
    #expect(checked, "RFC 8761 has tables")
  }

  /// A rendered diagram's card sits in the middle of the column, whichever of its
  /// presentations shows, so switching them moves nothing sideways.
  @Test(arguments: [PresentationChoices.defaults, PresentationChoices(preferred: .text)])
  func `a rendered diagram's card is centered in the column`(choices: PresentationChoices) throws {
    let style = ReadingStyle()
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: style, choices: choices)
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let fragment = (built.text.string as NSString).paragraphRange(
      for: NSRange(location: first, length: 0))
    let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: fragment))
    let width = try #require(span.contentWidth)
    #expect(abs(span.indent + width / 2 - style.measure / 2) < 0.5)
  }

  /// Set in by the card's inset, and the card measured from before it, so the card
  /// stays at the column's edge and the inset is room inside it.
  @Test func `a block with no rendering keeps its indent inside the card's inset`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: first, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.headIndent == FragmentGeometry.cardInset)
    let fragment = (built.text.string as NSString).paragraphRange(
      for: NSRange(location: first, length: 0))
    let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: fragment))
    #expect(span.indent == 0)
  }

  @Test func `the language label is set in from the card's trailing edge`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .sourceCode, text: "x = 1", type: "abnf"))),
      style: ReadingStyle())
    let label = try Fixtures.offset(of: "ABNF", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: label, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.tailIndent == -FragmentGeometry.cardInset)
  }
}
