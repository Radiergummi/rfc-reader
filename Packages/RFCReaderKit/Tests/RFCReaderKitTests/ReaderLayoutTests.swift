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
}
