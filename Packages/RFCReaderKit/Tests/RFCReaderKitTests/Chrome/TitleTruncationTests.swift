import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Title truncation")
struct TitleTruncationTests {
  @Test func `a short title is left alone`() {
    #expect("Geo-Coordinates".truncated(to: 40) == "Geo-Coordinates")
  }

  @Test func `a title exactly at the limit is left alone`() {
    let title = String(repeating: "a", count: 20)
    #expect(title.truncated(to: 20) == title)
  }

  @Test func `a long title is cut at a word boundary`() {
    let title = "Locator/ID Separation Protocol (LISP) Geo-Coordinates"
    let short = title.truncated(to: 30)
    #expect(short == "Locator/ID Separation Protocol…")
    #expect(!short.contains("Proto…"), "cutting mid-word reads as a bug, not a truncation")
  }

  @Test func `the ellipsis is one character not three dots`() {
    #expect("one two three four".truncated(to: 8).hasSuffix("…"))
    #expect(!"one two three four".truncated(to: 8).hasSuffix("..."))
  }

  /// No boundary to back up to, so it cuts where it must rather than returning "…".
  @Test func `a single word longer than the limit is still cut`() {
    let title = "Supercalifragilisticexpialidocious"
    let short = title.truncated(to: 10)
    #expect(short == "Supercalif…")
  }

  @Test func `trailing space does not strand an ellipsis`() {
    #expect("alpha beta gamma".truncated(to: 11) == "alpha beta…", "not 'alpha beta …'")
  }

  @Test func `a limit of zero or less is empty`() {
    #expect("anything".truncated(to: 0).isEmpty)
    #expect("anything".truncated(to: -5).isEmpty)
  }
}
