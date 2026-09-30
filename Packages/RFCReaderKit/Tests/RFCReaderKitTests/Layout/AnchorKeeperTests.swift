import Foundation
import Testing

@testable import RFCReaderKit

/// The reader's place, which only the reader moves: the engine's own scrolls never
/// record it, a re-wrap never walks it back, and it survives a rebuild.
@Suite("Anchor keeper")
struct AnchorKeeperTests {
  private let index = AnchorIndex([
    AnchorIndex.Entry(anchor: "section-1", offset: 0, heading: "One"),
    AnchorIndex.Entry(anchor: "section-2", offset: 500, heading: "Two"),
  ])

  @Test func `a scroll the engine makes is not the reader's`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 120))
    keeper.beginEngineMove()
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 900), line: NSRange(location: 900, length: 40))
    keeper.endEngineMove()
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 120)))
  }

  /// After the engine's move ends, the platform aligns the offset it set to the
  /// display's pixels on a pass of its own, and reports that as a scroll: measured
  /// on RFC 5661, 0.18 to 0.75 pt, into the paragraph above a pinned heading.
  @Test func `the platform settling the engine's move is not the reader's scroll`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 500))
    keeper.beginEngineMove()
    keeper.endEngineMove(top: 1000.25)
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 440, fraction: 0.97),
      line: NSRange(location: 440, length: 60),
      top: 999.5)
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 500)))
  }

  @Test func `a scroll away from where the engine left the top is the reader's`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 500))
    keeper.beginEngineMove()
    keeper.endEngineMove(top: 1000)
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 440, fraction: 0.5),
      line: NSRange(location: 440, length: 60),
      top: 990)
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 440, fraction: 0.5)))
    // Back where the engine left it, by the reader's own hand: theirs, too.
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 500), line: NSRange(location: 500, length: 60), top: 1000)
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 500)))
  }

  @Test func `a scroll the reader makes moves the place`() {
    var keeper = AnchorKeeper()
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 900, fraction: 0.2),
      line: NSRange(location: 900, length: 40))
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 900, fraction: 0.2)))
  }

  /// A re-wrap starts the line earlier than the place; recording the line's start
  /// would walk the place back on every step of a resize.
  @Test func `a line that still holds the place keeps its character`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 530))
    keeper.userScrolled(
      to: ReaderAnchor(characterOffset: 510, fraction: 0.4),
      line: NSRange(location: 510, length: 60))
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 530, fraction: 0.4)))
  }

  @Test func `above the text the place is the top, and a jump works during an engine move`() {
    var keeper = AnchorKeeper()
    keeper.userScrolledAboveText()
    #expect(keeper.place == .top)
    keeper.beginEngineMove()
    keeper.jumped(to: ReaderAnchor(characterOffset: 42))
    keeper.endEngineMove()
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 42)))
  }

  @Test func `the top survives a rebuild as the top`() {
    var keeper = AnchorKeeper()
    let carried = keeper.carried(in: index)
    keeper.restore(carried, in: index, length: 1000)
    #expect(keeper.place == .top)
  }

  @Test func `a place survives a rebuild that moved every offset`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 540, fraction: 0.25))
    let carried = keeper.carried(in: index)
    let rebuilt = AnchorIndex([
      AnchorIndex.Entry(anchor: "section-1", offset: 0, heading: "One"),
      AnchorIndex.Entry(anchor: "section-2", offset: 800, heading: "Two"),
    ])
    keeper.restore(carried, in: rebuilt, length: 2000)
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 840, fraction: 0.25)))
  }

  /// A table re-shaped for a narrow column comes back shorter; the place stays
  /// inside the document rather than past its end.
  @Test func `a place in a block that came back shorter stays inside the document`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 990))
    let carried = keeper.carried(in: index)
    keeper.restore(carried, in: index, length: 600)
    guard case .line(let anchor) = keeper.place else {
      Issue.record("expected a line")
      return
    }
    #expect(anchor.characterOffset < 600)
  }

  @Test func `the reading place to save names the anchor and the distance past it`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 520))
    #expect(keeper.readingPlace(in: index) == ReadingPlace(anchor: "section-2", offset: 20))
  }
}
