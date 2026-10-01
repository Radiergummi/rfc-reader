import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The menu of a block with a rendering: its words, and the item a long press on
/// the block is for.
@Suite("Figure menu")
struct FigureMenuTests {
  /// The item offers the presentation that is not showing.
  @Test func `the menu offers the text of a figure and the figure of a text`() {
    #expect(FigureMenu.title(offeredFrom: .figure) == "Show as Text")
    #expect(FigureMenu.offered(from: .figure) == .text)
    #expect(FigureMenu.title(offeredFrom: .text) == "Show as Figure")
    #expect(FigureMenu.offered(from: .text) == .figure)
    #expect(FigureMenu.symbol(offeredFrom: .figure) != FigureMenu.symbol(offeredFrom: .text))
  }

  @Test func `a rendered block is one item over its whole body`() throws {
    let built = build()
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let box = try #require(FigureCopy.box(at: first, in: built.text))
    var extent = NSRange()
    let tag = built.text.attribute(
      .rfcFigureItem, at: first, longestEffectiveRange: &extent,
      in: NSRange(location: 0, length: built.text.length))
    #expect(tag as? String == FigureMenu.itemTag(of: box))
    #expect(extent == built.text.extent(ofBox: .rfcVerbatim, at: first))
  }

  /// UIKit hands the long press a text item no longer than the storage run under
  /// the finger, and a drawn diagram's grid and ruler colors cut its body into
  /// runs a line or less long: the lifted figure was the line pressed. The menu
  /// lifts the item's whole extent instead.
  @Test func `a press anywhere on a drawn block is for the whole block`() throws {
    let built = build()
    let field = try Fixtures.offset(of: "Length", in: built.text)
    var run = NSRange()
    _ = built.text.attribute(.rfcFigureItem, at: field, effectiveRange: &run)
    let whole = try #require(built.text.extent(ofBox: .rfcVerbatim, at: field))
    #expect(run != whole)
    #expect(FigureMenu.itemRange(at: field, in: built.text) == whole)
  }

  @Test func `a press outside a block is for no item`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    #expect(FigureMenu.itemRange(at: first, in: built.text) == nil)
  }

  /// So a block shown as its text can be switched back from its menu.
  @Test func `a block shown as its text is still an item`() throws {
    let built = build(choices: PresentationChoices(preferred: .text))
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    #expect(FigureCopy.box(at: first, in: built.text)?.presentation == .text)
    #expect(built.text.attribute(.rfcFigureItem, at: first, effectiveRange: nil) != nil)
  }

  @Test func `two blocks are two items`() {
    let first = VerbatimBox(Preformatted(kind: .artwork, text: ""), ordinal: 0)
    let second = VerbatimBox(Preformatted(kind: .artwork, text: ""), ordinal: 1)
    #expect(FigureMenu.itemTag(of: first) != FigureMenu.itemTag(of: second))
  }

  @Test func `a block with no rendering is no item`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: "+--+\n|  |\n+--+"))),
      style: ReadingStyle())
    let first = try Fixtures.offset(of: "+--+", in: built.text)
    #expect(built.text.attribute(.rfcFigureItem, at: first, effectiveRange: nil) == nil)
  }

  /// Paper has nothing to press.
  @Test func `a build without live links has no item`() throws {
    let built = build(style: PrintLayout(paperSize: CGSize(width: 612, height: 792)).style)
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    #expect(built.text.attribute(.rfcFigureItem, at: first, effectiveRange: nil) == nil)
  }

  /// Nothing sits above a rendered block's first line any more, so nothing is
  /// reserved there.
  @Test func `a rendered block's first line has no spacing before it`() throws {
    let built = build()
    let first = try Fixtures.offset(of: "    0 ", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: first, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.paragraphSpacingBefore == 0)
  }

  private func build(
    style: ReadingStyle = ReadingStyle(), choices: PresentationChoices = .defaults
  ) -> BuiltDocument {
    DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: style, choices: choices)
  }
}
