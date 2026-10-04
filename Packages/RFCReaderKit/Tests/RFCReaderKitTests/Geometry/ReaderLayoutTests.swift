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

  /// A scroll is kept to what the scroll view can show: never above the top, under
  /// the toolbar's inset, nor past the end of the text. Text that fits sits at the
  /// top, whatever a jump or a reveal asked for: a reveal of the end of a short
  /// Focus section had scrolled its title up under the toolbar.
  @Test func `a scroll stays within what the text can show`() {
    // Taller than the viewport: from under the toolbar to the end, less the viewport.
    func origin(_ target: CGFloat, height: CGFloat?) -> CGFloat {
      ReaderLayout.scrollOrigin(
        target, contentHeight: height, viewportHeight: 1001, topInset: 52, bottomInset: 0)
    }
    #expect(origin(500, height: 5000) == 500)
    #expect(origin(-200, height: 5000) == -52)
    #expect(origin(4800, height: 5000) == 3999)
    // Text that fits: the top, wherever the target was.
    #expect(origin(42.9, height: 943) == -52)
    #expect(origin(359.28, height: 943) == -52)
    // The bottom inset is room to scroll into.
    #expect(
      ReaderLayout.scrollOrigin(
        4800, contentHeight: 5000, viewportHeight: 1001, topInset: 52, bottomInset: 30) == 4029)
    // An end not yet known, under viewport layout, holds only the top: the
    // estimate must not pull a jump short (the layout engine's design).
    #expect(origin(4800, height: nil) == 4800)
    #expect(origin(-200, height: nil) == -52)
  }

  @Test func `the window's floor is the two fixed columns and a readable pane`() {
    #expect(ReaderLayout.minimumWindowWidth(panelIsOpen: false) == CGFloat(900))
  }

  /// AppKit adds an open inspector's thickness on top of the content minimum, so the
  /// panel's width comes off it while the panel shows: what AppKit enforces is then
  /// the same open or shut, and opening the panel never grows the window.
  @Test func `the floor AppKit enforces is the same with the panel open or shut`() {
    let shut = ReaderLayout.minimumWindowWidth(panelIsOpen: false)
    let open = ReaderLayout.minimumWindowWidth(panelIsOpen: true) + ReaderLayout.panelWidth
    #expect(open == shut)
  }

  /// AppKit restores a saved frame without checking it against the minimum, so one
  /// saved narrower than the floor has to be widened by hand.
  @Test func `a restored window narrower than the floor is widened to it`() {
    let restored = ReaderLayout.windowSize(
      fitting: CGSize(width: 700, height: 300), panelIsOpen: false)
    #expect(restored == CGSize(width: 900, height: 480))
  }

  @Test func `a window wider than the floor keeps its size`() {
    let size = CGSize(width: 1400, height: 900)
    #expect(ReaderLayout.windowSize(fitting: size, panelIsOpen: false) == size)
  }

  @Test func `with the panel open a restored window is widened to the floor less the panel`() {
    let restored = ReaderLayout.windowSize(
      fitting: CGSize(width: 500, height: 600), panelIsOpen: true)
    #expect(restored == CGSize(width: 580, height: 600))
  }
}
