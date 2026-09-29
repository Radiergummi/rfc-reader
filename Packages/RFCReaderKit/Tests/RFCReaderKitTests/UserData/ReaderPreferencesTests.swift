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

  @Test func `the style carries every setting and the column`() {
    let style = ReaderPreferences.style(
      fontSize: 20, underlineLinks: true, column: 500, textSize: .xxLarge)
    #expect(
      style == ReadingStyle(bodySize: 20, measure: 500, underlinesLinks: true, textSize: .xxLarge))
  }
}
