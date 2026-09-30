import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The Figure | Source control a rendered block carries in its card's top-right
/// corner: where it is drawn and hit, and what the builder sets for it.
@Suite("Figure control")
struct FigureControlTests {
  private let card = CGRect(x: 10, y: 95, width: 400, height: 300)

  @Test func `the control sits in the card's top-right corner`() {
    let control = FigureControl.rect(inCard: card)
    #expect(control.maxX == card.maxX - FigureControl.inset)
    #expect(control.minY == card.minY + FigureControl.inset)
    #expect(control.width == FigureControl.width)
    #expect(control.height == FigureControl.height)
  }

  @Test func `the button is a square that fits in its strip`() {
    #expect(FigureControl.width == FigureControl.height)
    #expect(FigureControl.height <= FigureControl.strip)
  }

  /// The button offers the presentation that is not showing, in the context
  /// menu's words.
  @Test func `the button offers the source of a figure and the rendering of a source`() {
    #expect(FigureControl.title(offeredFrom: .figure) == "Show Source")
    #expect(FigureControl.symbol(offeredFrom: .figure) == "chevron.left.forwardslash.chevron.right")
    #expect(FigureControl.title(offeredFrom: .source) == "Show Rendering")
    #expect(FigureControl.symbol(offeredFrom: .source) == "square.grid.3x3")
  }

  @Test func `the controlled blocks are found at their first characters`() throws {
    let built = build()
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let blockStart = try #require(built.text.extent(ofBox: .rfcVerbatim, at: first)).location
    #expect(
      FigureControl.blocks(in: built.text) == [
        FigureControl.Block(location: blockStart, control: .init(ordinal: 0, shown: .figure))
      ])
  }

  @Test func `a point anywhere in a controlled block names that block`() throws {
    let built = build()
    let later = try Fixtures.offset(of: "   |     Type", in: built.text)
    #expect(FigureControl.ordinal(at: later, in: built.text) == 0)
    #expect(FigureControl.ordinal(at: built.text.length, in: built.text) == nil)
  }

  @Test func `a point in a block without a control names none`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    #expect(FigureControl.ordinal(at: first, in: built.text) == nil)
    #expect(FigureControl.blocks(in: built.text).isEmpty)
  }

  /// A rendered diagram's card sits in the middle of the column, whichever of its
  /// presentations shows, so switching them moves nothing sideways.
  @Test(arguments: [PresentationChoices.defaults, PresentationChoices(shownAsSource: [0])])
  func `a rendered diagram's card is centered in the column`(choices: PresentationChoices) throws {
    let style = ReadingStyle()
    let built = build(style: style, choices: choices)
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let span = try #require(
      FragmentGeometry.decorationSpan(in: built.text, fragment: fragment(at: first, in: built.text))
    )
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

  /// The strip the control sits in is spacing before the block's first line, so
  /// showing the control on hover moves no text.
  @Test func `a rendered block reserves the control's strip above its first line`() throws {
    let built = build()
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: first, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.paragraphSpacingBefore == FigureControl.strip)
    #expect(
      FigureControl.shown(atFragment: fragment(at: first, in: built.text), in: built.text)
        == .figure)
  }

  @Test func `only the block's first line carries the control`() throws {
    let built = build()
    let later = try Fixtures.offset(of: "   |     Type", in: built.text)
    #expect(
      FigureControl.shown(atFragment: fragment(at: later, in: built.text), in: built.text) == nil)
  }

  @Test func `a block shown as its source shows the source segment`() throws {
    let built = build(choices: PresentationChoices(shownAsSource: [0]))
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    #expect(
      FigureControl.shown(atFragment: fragment(at: first, in: built.text), in: built.text)
        == .source)
  }

  /// Paper has nothing to press: a print or an export, built without live links,
  /// carries no control and reserves no strip for one.
  @Test func `a build without live links has no control`() throws {
    let built = build(style: PrintLayout(paperSize: CGSize(width: 612, height: 792)).style)
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: first, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.paragraphSpacingBefore == 0)
    #expect(
      FigureControl.shown(atFragment: fragment(at: first, in: built.text), in: built.text) == nil)
  }

  @Test func `a block with no rendering has no control`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    #expect(
      FigureControl.shown(atFragment: fragment(at: first, in: built.text), in: built.text) == nil)
  }

  @Test func `a card is never narrower than its control`() throws {
    let narrow =
      "    0\n    0 1 2 3 4 5 6 7\n   +-+-+-+-+-+-+-+-+\n   | A |     B     |\n   +-+-+-+-+-+-+-+-+"
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: narrow))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "   | A", in: built.text)
    let span = try #require(
      FragmentGeometry.decorationSpan(in: built.text, fragment: fragment(at: first, in: built.text))
    )
    #expect(try #require(span.contentWidth) >= FigureControl.width)
  }

  private func build(
    style: ReadingStyle = ReadingStyle(), choices: PresentationChoices = .defaults
  ) -> BuiltDocument {
    DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: style, choices: choices)
  }

  /// The paragraph holding `location`: the range a line's fragment covers.
  private func fragment(at location: Int, in text: NSAttributedString) -> NSRange {
    (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
  }
}
