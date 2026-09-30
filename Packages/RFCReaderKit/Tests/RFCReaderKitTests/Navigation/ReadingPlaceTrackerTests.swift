import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Reading place tracker")
struct ReadingPlaceTrackerTests {
  private let index = AnchorIndex([
    .init(anchor: "section-1", offset: 100, heading: "1. Section"),
    .init(anchor: "section-1-1", offset: 130),
    .init(anchor: "section-2", offset: 400, heading: "2. Section"),
  ])
  private let wide: CGFloat = 712
  private let narrow: CGFloat = 480

  /// Laid out at `wide`, tracking, and reading the line starting at 250.
  private func reading() -> ReadingPlaceTracker {
    var tracker = ReadingPlaceTracker()
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(!laysOutWide, "nothing is installed yet")
    tracker.installed(atColumn: wide)
    tracker.restored(top: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 250, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    return tracker
  }

  @Test func `tracks the line at the top`() {
    var tracker = reading()
    tracker.report(
      viewportTop: 340, line: NSRange(location: 310, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 180)))
  }

  @Test func `a change of column pauses tracking until the storage is laid out again`() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    // The old storage, re-wrapped under an unmoved offset: text the reader never saw.
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    tracker.installed(atColumn: narrow)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(
      tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)),
      "installed is not yet restored")
    tracker.restored(top: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: nil, offset: 20)))
  }

  /// Wide, narrow and wide again inside the rebuild's debounce. The container is
  /// back at the width the storage was laid out at, but TextKit threw that layout
  /// away at the narrow one, and what it shows now is estimated: keyed on the
  /// width alone, tracking resumed here and recorded a line the reader never saw.
  @Test func `a column that comes back does not resume tracking on discarded layout`() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(laysOutWide, "the storage was laid out at this column, so it can be laid out again now")
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
  }

  @Test func `a document installed before any column is laid out at the first one`() {
    var tracker = ReadingPlaceTracker()
    tracker.installed(atColumn: nil)
    tracker.report(
      viewportTop: 300, line: NSRange(location: 20, length: 60), in: index, length: 500)
    #expect(tracker.place == nil)
    let laysOutWide = tracker.columnChanged(to: wide)
    #expect(laysOutWide)
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
  }

  /// At the document's end a restore clamps, so the line holding the place is not
  /// the one at the top. Tracking that line would walk the place back on every
  /// resize; until the reader scrolls, the place is the one that was carried.
  @Test func `keeps the carried place until the reader scrolls away from the restore`() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    tracker.installed(atColumn: narrow)
    tracker.restored(top: 280)
    tracker.report(
      viewportTop: 280, line: NSRange(location: 200, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    tracker.report(
      viewportTop: 260, line: NSRange(location: 160, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 30)))
  }

  @Test func `a viewport above the text is the top`() {
    var tracker = reading()
    tracker.report(viewportTop: -40, line: NSRange(location: 0, length: 60), in: index, length: 500)
    #expect(tracker.place == .top)
  }

  /// A jump is where the reader is, even while tracking waits for a rebuild.
  @Test func `a jump is the place even while paused`() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    tracker.jumped(to: ReadingPlace(anchor: "section-2", offset: 0))
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-2", offset: 0)))
  }

  /// Whether the viewport is still where the last restore left it: the reader has
  /// not scrolled since, and the place is the one carried rather than the line on
  /// screen.
  @Test func `is at the restored place until the reader scrolls or jumps away`() {
    var tracker = reading()
    #expect(!tracker.isAtRestoredPlace, "nothing was restored")
    tracker.restored(top: 280)
    #expect(tracker.isAtRestoredPlace)
    tracker.report(
      viewportTop: 280, line: NSRange(location: 200, length: 40), in: index, length: 500)
    #expect(tracker.isAtRestoredPlace)
    tracker.report(
      viewportTop: 260, line: NSRange(location: 160, length: 40), in: index, length: 500)
    #expect(!tracker.isAtRestoredPlace)
    tracker.restored(top: 280)
    tracker.jumped(to: ReadingPlace(anchor: "section-2", offset: 0))
    #expect(!tracker.isAtRestoredPlace)
  }

  /// A place restored again after the header changed height lands, at the
  /// document's end, clamped somewhere else than the first restore did; the scroll
  /// that gets it there is not the reader's, and records nothing.
  @Test func `restoring the place again pauses tracking until it is restored`() {
    var tracker = reading()
    let laysOutNarrow = tracker.columnChanged(to: narrow)
    #expect(!laysOutNarrow)
    tracker.installed(atColumn: narrow)
    tracker.restored(top: 280)
    tracker.restoring()
    tracker.report(
      viewportTop: 220, line: NSRange(location: 150, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
    tracker.restored(top: 220)
    tracker.report(
      viewportTop: 220, line: NSRange(location: 150, length: 40), in: index, length: 500)
    #expect(tracker.place == .line(ReadingPlace(anchor: "section-1-1", offset: 120)))
  }
}
