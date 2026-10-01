import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A verbatim block's card ends a padding past its widest line, not at the column's
/// edge: on a wide window a narrow diagram sat at the left of a card twice its
/// width. A table's card still spans the column.
@Suite("Card width: a verbatim block's card hugs its content")
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

  /// Every line of a block reports the same width, or the card's right edge would
  /// step line by line: the staircase again, on the other side.
  @Test func `every line of a verbatim block reports its widest line`() throws {
    let art = "+--+\n| A long middle line |\n+--+"
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: art))),
      style: ReadingStyle())
    let text = built.text.string as NSString
    let widest = try Fixtures.offset(of: "| A long", in: built.text)
    let font = try #require(
      built.text.attribute(.font, at: widest, effectiveRange: nil) as? PlatformFont)
    let expected = DocumentTextBuilder.lineWidth(
      NSAttributedString(string: "| A long middle line |", attributes: [.font: font]))
    for needle in ["+--+\n", "| A long", "+--+"] {
      let location = text.range(of: needle, options: .backwards).location
      let fragment = text.paragraphRange(for: NSRange(location: location, length: 0))
      let span = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: fragment))
      let width = try #require(span.contentWidth)
      #expect(abs(width - expected) < 0.5, "\(needle): \(width) against \(expected)")
    }
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

  @Test func `a block with no rendering keeps its indent`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: first, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.headIndent == 0)
  }
}
