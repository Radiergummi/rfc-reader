import SwiftUI
import Testing

@testable import RFCReaderKit

/// The reader's settings as user defaults hold them.
@Suite("Reader preferences")
struct ReaderPreferencesTests {
  /// What user defaults already hold: renaming one resets everyone's choice.
  @Test func `the keys are the ones already stored`() {
    #expect(ReaderPreferences.fontSizeKey == "readingFontSize")
    #expect(ReaderPreferences.underlineLinksKey == "underlineLinks")
    #expect(ReaderPreferences.measureKey == "readerMeasure")
    #expect(ReaderPreferences.preferOriginalTextKey == "preferOriginalText")
  }

  @Test func `the default size is the style's own default`() {
    #expect(CGFloat(ReaderPreferences.defaultFontSize) == ReadingStyle().bodySize)
    #expect(ReaderPreferences.defaultUnderlineLinks == ReadingStyle().underlinesLinks)
  }

  /// View ▸ Bigger and Smaller, and the iOS text-size popover (#153), step
  /// within the same range as the Settings slider.
  @Test func `the default size is inside the range`() {
    #expect(ReaderPreferences.fontSizes.contains(ReaderPreferences.defaultFontSize))
  }

  @Test func `bigger and smaller step by one point`() {
    #expect(ReaderPreferences.fontSize(steppingUp: 17) == 18)
    #expect(ReaderPreferences.fontSize(steppingDown: 17) == 16)
  }

  @Test func `stepping stops at the ends of the range`() {
    let sizes = ReaderPreferences.fontSizes
    #expect(ReaderPreferences.fontSize(steppingUp: sizes.upperBound) == sizes.upperBound)
    #expect(ReaderPreferences.fontSize(steppingDown: sizes.lowerBound) == sizes.lowerBound)
  }

  /// A size stored outside the range, by an older slider or by hand, steps back
  /// into it rather than further away.
  @Test func `a size outside the range steps into it`() {
    let sizes = ReaderPreferences.fontSizes
    #expect(ReaderPreferences.fontSize(steppingDown: sizes.upperBound + 10) == sizes.upperBound)
    #expect(ReaderPreferences.fontSize(steppingUp: sizes.lowerBound - 10) == sizes.lowerBound)
  }
}
