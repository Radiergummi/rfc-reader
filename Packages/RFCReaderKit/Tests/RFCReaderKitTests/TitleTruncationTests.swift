import Foundation
import Testing
@testable import RFCReaderKit

@Suite("Title truncation")
struct TitleTruncationTests {
    @Test func aShortTitleIsLeftAlone() {
        #expect("Geo-Coordinates".truncated(to: 40) == "Geo-Coordinates")
    }

    @Test func aTitleExactlyAtTheLimitIsLeftAlone() {
        let title = String(repeating: "a", count: 20)
        #expect(title.truncated(to: 20) == title)
    }

    @Test func aLongTitleIsCutAtAWordBoundary() {
        let title = "Locator/ID Separation Protocol (LISP) Geo-Coordinates"
        let short = title.truncated(to: 30)
        #expect(short == "Locator/ID Separation Protocol…")
        #expect(!short.contains("Proto…"), "cutting mid-word reads as a bug, not a truncation")
    }

    @Test func theEllipsisIsOneCharacterNotThreeDots() {
        #expect("one two three four".truncated(to: 8).hasSuffix("…"))
        #expect(!"one two three four".truncated(to: 8).hasSuffix("..."))
    }

    /// No boundary to back up to, so it cuts where it must rather than returning "…".
    @Test func aSingleWordLongerThanTheLimitIsStillCut() {
        let title = "Supercalifragilisticexpialidocious"
        let short = title.truncated(to: 10)
        #expect(short == "Supercalif…")
    }

    @Test func trailingSpaceDoesNotStrandAnEllipsis() {
        #expect("alpha beta gamma".truncated(to: 11) == "alpha beta…", "not 'alpha beta …'")
    }

    @Test func aLimitOfZeroOrLessIsEmpty() {
        #expect("anything".truncated(to: 0).isEmpty)
        #expect("anything".truncated(to: -5).isEmpty)
    }
}
