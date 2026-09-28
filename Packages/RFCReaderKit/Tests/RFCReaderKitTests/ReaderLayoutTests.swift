import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Reader layout")
struct ReaderLayoutTests {
  @Test func `an i phone in portrait keeps the bar to contents and more`() {
    #expect(!ReaderLayout.toolbarHasRoom(isRegularWidth: false, isCompactHeight: false))
  }

  /// Most iPhones report a compact width even in landscape: the height is what
  /// says there is room.
  @Test func `an i phone in landscape has room`() {
    #expect(ReaderLayout.toolbarHasRoom(isRegularWidth: false, isCompactHeight: true))
  }

  @Test func `an i pad has room`() {
    #expect(ReaderLayout.toolbarHasRoom(isRegularWidth: true, isCompactHeight: false))
  }

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

  /// The inset and the build each ask for one of these, and they have drifted
  /// apart before: whatever the preference, the column is what the gutters leave.
  @Test func `the column is what the gutters leave under either preference`() {
    for measure in MeasurePreference.allCases {
      for width: CGFloat in [390, 760, 1200, 2560] {
        let gutter = ReaderLayout.gutter(forWidth: width, measure: measure)
        #expect(ReaderLayout.column(forWidth: width, measure: measure) == width - gutter * 2)
      }
    }
  }

  /// Stored in user defaults by its raw value, so the spelling is the setting.
  @Test func `the preference round trips through its stored value`() {
    for measure in MeasurePreference.allCases {
      #expect(MeasurePreference(rawValue: measure.rawValue) == measure)
    }
  }

  /// The floor is wide enough to read at, and low enough that the two side columns
  /// plus the reader still fit a laptop display.
  @Test func `the minimum pane is readable and still tracks the view`() {
    let column = ReaderLayout.column(forWidth: ReaderLayout.minimumPaneWidth, measure: .recommended)
    #expect(column == ReaderLayout.minimumPaneWidth - ReaderLayout.margin * 2)
    #expect(column > 300)
  }
}

@Suite("Toolbar title layout")
struct ToolbarTitleLayoutTests {
  /// A short title takes the width of its text and no more — the point of drawing
  /// the title ourselves rather than letting AppKit's own block expand to fill.
  @Test func `a short title takes only the width of its text`() {
    #expect(ToolbarTitleLayout.width(forText: 120, inColumn: 400) == 136)
  }

  /// Capped to the column it names: a long RFC title ran past the list's trailing
  /// edge and over the reader's own toolbar section.
  @Test func `a long title stops short of the divider`() {
    let width = ToolbarTitleLayout.width(forText: 2000, inColumn: 300)
    #expect(width < 300)
    #expect(width == 276)
  }

  /// A column dragged to nothing still leaves the title a readable stub rather
  /// than a zero-width item the toolbar lays other items over.
  @Test func `a collapsed column still leaves a stub`() {
    #expect(ToolbarTitleLayout.width(forText: 2000, inColumn: 0) == 80)
  }

  /// The reader's title flexes down to nothing; below the stub width it hides
  /// rather than drawing an ellipsis on its own.
  @Test func `a title narrower than the stub is not drawn`() {
    #expect(ToolbarTitleLayout.isWorthDrawing(width: 80))
    #expect(!ToolbarTitleLayout.isWorthDrawing(width: 79))
    #expect(!ToolbarTitleLayout.isWorthDrawing(width: 0))
  }
}

@Suite("Toolbar title reveal")
struct ToolbarTitleRevealTests {
  /// A 40 pt last line whose bottom sits at y = 200.
  private func progress(atToolbarEdge edge: CGFloat) -> CGFloat {
    ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: edge, distance: 40)
  }

  /// At the top of the document the header shows the title, so the toolbar does not.
  @Test func `hidden while the heading is below the toolbar`() {
    #expect(progress(atToolbarEdge: 0) == 0)
    #expect(progress(atToolbarEdge: 160) == 0, "the last line's top has only just reached the edge")
  }

  /// It scrubs with the scroll: half the line under the toolbar is half the way in.
  @Test func `follows the scroll across the last line`() {
    #expect(progress(atToolbarEdge: 170) == 0.25)
    #expect(progress(atToolbarEdge: 180) == 0.5)
  }

  /// Fully in once the line is fully under, and it stays there all the way down.
  @Test func `fully shown once the heading has passed`() {
    #expect(progress(atToolbarEdge: 200) == 1)
    #expect(progress(atToolbarEdge: 90_000) == 1)
  }

  /// A heading of several lines reveals over its last line only: the toolbar has
  /// room for one, and the lines above it are gone by then anyway.
  @Test func `a tall heading reveals over its last line only`() {
    let wrapped = ToolbarTitleReveal.progress(headingBottom: 300, visibleTop: 280, distance: 40)
    #expect(wrapped == 0.5)
  }

  /// Invisible while it crosses the toolbar's edge, then fading in to fully opaque.
  @Test func `opacity waits for the first half of the travel`() {
    #expect(ToolbarTitleReveal.opacity(atProgress: 0) == 0)
    #expect(ToolbarTitleReveal.opacity(atProgress: 0.5) == 0)
    #expect(ToolbarTitleReveal.opacity(atProgress: 0.75) == 0.5)
    #expect(ToolbarTitleReveal.opacity(atProgress: 1) == 1)
  }

  /// A heading with no measurable line switches at its bottom rather than dividing
  /// by zero.
  @Test func `a zero distance switches at the headings bottom`() {
    #expect(ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: 199, distance: 0) == 0)
    #expect(ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: 200, distance: 0) == 1)
  }
}
