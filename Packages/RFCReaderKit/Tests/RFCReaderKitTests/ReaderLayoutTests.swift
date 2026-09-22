import Testing
@testable import RFCReaderKit
import Foundation

@Suite("Reader layout")
struct ReaderLayoutTests {
    @Test func aNarrowViewGivesTheColumnEverythingButTheMargins() {
        #expect(ReaderLayout.column(forWidth: 390) == 390 - ReaderLayout.margin * 2)
    }

    @Test func aWideViewCapsTheColumnAtTheIdealMeasure() {
        #expect(ReaderLayout.column(forWidth: 2000) == ReaderLayout.idealMeasure)
    }

    /// The breakpoint: the widest view that still tracks, and the narrowest that caps.
    @Test func theTwoRegimesMeetAtTheBreakpoint() {
        let breakpoint = ReaderLayout.idealMeasure + ReaderLayout.margin * 2
        #expect(ReaderLayout.column(forWidth: breakpoint) == ReaderLayout.idealMeasure)
        #expect(ReaderLayout.column(forWidth: breakpoint - 2) == ReaderLayout.idealMeasure - 2)
    }

    /// Above the breakpoint the column is pinned and the gutter absorbs the resize,
    /// so the two are *not* interchangeable as a "has the layout moved?" test.
    ///
    /// The reader's inset is the gutter, and it was invalidated by comparing the
    /// column — which, up here, never changes. Every resize of a wide window was
    /// skipped, and the text kept the inset it was first laid out at: widen a window
    /// and the measure ran to 2,200 pt, narrow one and it collapsed to 105.
    @Test func aboveTheBreakpointTheGutterMovesWhileTheColumnDoesNot() {
        #expect(ReaderLayout.column(forWidth: 1200) == ReaderLayout.column(forWidth: 2400))
        #expect(ReaderLayout.gutter(forWidth: 1200) != ReaderLayout.gutter(forWidth: 2400))
    }

    /// The floor is wide enough to read at, and low enough that the two side columns
    /// plus the reader still fit a laptop display.
    @Test func theMinimumPaneIsReadableAndStillTracksTheView() {
        let column = ReaderLayout.column(forWidth: ReaderLayout.minimumPaneWidth)
        #expect(column == ReaderLayout.minimumPaneWidth - ReaderLayout.margin * 2)
        #expect(column > 300)
    }
}

@Suite("Toolbar title layout")
struct ToolbarTitleLayoutTests {
    /// A short title takes the width of its text and no more — the point of drawing
    /// the title ourselves rather than letting AppKit's own block expand to fill.
    @Test func aShortTitleTakesOnlyTheWidthOfItsText() {
        #expect(ToolbarTitleLayout.width(forText: 120, inColumn: 400) == 136)
    }

    /// Capped to the column it names: a long RFC title ran past the list's trailing
    /// edge and over the reader's own toolbar section.
    @Test func aLongTitleStopsShortOfTheDivider() {
        let width = ToolbarTitleLayout.width(forText: 2000, inColumn: 300)
        #expect(width < 300)
        #expect(width == 276)
    }

    /// A column dragged to nothing still leaves the title a readable stub rather
    /// than a zero-width item the toolbar lays other items over.
    @Test func aCollapsedColumnStillLeavesAStub() {
        #expect(ToolbarTitleLayout.width(forText: 2000, inColumn: 0) == 80)
    }
}
