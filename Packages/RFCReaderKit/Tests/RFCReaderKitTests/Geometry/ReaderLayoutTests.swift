import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Reader layout")
struct ReaderLayoutTests {
  @Test func `a narrow view gives the column everything but the margins`() {
    #expect(
      ReaderLayout.column(forWidth: 390, measure: .recommended) == 390 - ReaderLayout.margin * 2)
  }

  @Test func `a wide view caps the column at the ideal measure`() {
    #expect(ReaderLayout.column(forWidth: 2000, measure: .recommended) == ReaderLayout.idealMeasure)
  }

  /// The breakpoint: the widest view that still tracks, and the narrowest that caps.
  @Test func `the two regimes meet at the breakpoint`() {
    let breakpoint = ReaderLayout.idealMeasure + ReaderLayout.margin * 2
    #expect(
      ReaderLayout.column(forWidth: breakpoint, measure: .recommended) == ReaderLayout.idealMeasure)
    #expect(
      ReaderLayout.column(forWidth: breakpoint - 2, measure: .recommended) == ReaderLayout
        .idealMeasure - 2)
  }

  /// Above the breakpoint the column is pinned and the gutter absorbs the resize,
  /// so the two are *not* interchangeable as a "has the layout moved?" test.
  ///
  /// The reader's inset is the gutter, and it was invalidated by comparing the
  /// column — which, up here, never changes. Every resize of a wide window was
  /// skipped, and the text kept the inset it was first laid out at: widen a window
  /// and the measure ran to 2,200 pt, narrow one and it collapsed to 105.
  @Test func `above the breakpoint the gutter moves while the column does not`() {
    #expect(
      ReaderLayout.column(forWidth: 1200, measure: .recommended)
        == ReaderLayout.column(forWidth: 2400, measure: .recommended))
    #expect(
      ReaderLayout.gutter(forWidth: 1200, measure: .recommended)
        != ReaderLayout.gutter(forWidth: 2400, measure: .recommended))
  }

  /// Full width is `less`: the text runs to the margins however wide the window.
  @Test func `full width gives the column everything but the margins at any width`() {
    for width: CGFloat in [390, 760, 1200, 2560] {
      #expect(ReaderLayout.gutter(forWidth: width, measure: .fullWidth) == ReaderLayout.margin)
      #expect(
        ReaderLayout.column(forWidth: width, measure: .fullWidth)
          == width - ReaderLayout.margin * 2)
    }
  }

  /// Below the breakpoint the two preferences are the same layout: the window is
  /// already narrower than the recommended measure.
  @Test func `below the breakpoint the preference changes nothing`() {
    #expect(
      ReaderLayout.column(forWidth: 600, measure: .fullWidth)
        == ReaderLayout.column(forWidth: 600, measure: .recommended))
  }

  /// Stored in user defaults by its raw value, so the spelling is the setting:
  /// renaming a case would quietly reset everyone who chose it.
  @Test func `the preference is stored under its existing spellings`() {
    #expect(MeasurePreference(rawValue: "recommended") == .recommended)
    #expect(MeasurePreference(rawValue: "fullWidth") == .fullWidth)
  }

  /// The floor is wide enough to read at, and low enough that the two side columns
  /// plus the reader still fit a laptop display.
  @Test func `the minimum pane is readable and still tracks the view`() {
    let column = ReaderLayout.column(forWidth: ReaderLayout.minimumPaneWidth, measure: .recommended)
    #expect(column == ReaderLayout.minimumPaneWidth - ReaderLayout.margin * 2)
    #expect(column > 300)
  }

  /// A header with no height of its own — a link preview's `EmptyView` (#29) —
  /// answers with the height it was offered, and as an inset that unbounded height
  /// made the text view's frame NaN, which AppKit traps on.
  @Test func `a header that answers with the height it was offered has none`() {
    #expect(ReaderLayout.headerHeight(measured: 84, offered: .greatestFiniteMagnitude) == 84)
    #expect(
      ReaderLayout.headerHeight(
        measured: .greatestFiniteMagnitude, offered: .greatestFiniteMagnitude) == 0)
  }
}
