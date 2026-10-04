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
    #expect(ReaderPreferences.drawDiagramsKey == "drawDiagrams")
    #expect(ReaderPreferences.syntaxThemeKey == "syntaxTheme")
    #expect(ReaderPreferences.paletteKey == "readerPalette")
  }

  @Test func `the default size is the style's own default`() {
    #expect(CGFloat(ReaderPreferences.defaultFontSize) == ReadingStyle().bodySize)
    #expect(ReaderPreferences.defaultUnderlineLinks == ReadingStyle().underlinesLinks)
  }

  /// A print and an export read the preference from user defaults, and a reader
  /// who never set it draws diagrams, as the reader does.
  @Test func `diagrams are drawn unless the reader turned them off`() throws {
    let suite = "ReaderPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(ReaderPreferences.defaultDrawDiagrams)
    #expect(ReaderPreferences.drawsDiagrams(in: defaults))
    defaults.set(false, forKey: ReaderPreferences.drawDiagramsKey)
    #expect(!ReaderPreferences.drawsDiagrams(in: defaults))
  }

  // MARK: - Stepping

  // View ▸ Bigger and Smaller, and the iOS Aa menu (#153), step
  // within the same range as the Settings slider.

  @Test func `the default size is inside the range`() {
    #expect(ReaderPreferences.fontSizes.contains(ReaderPreferences.defaultFontSize))
  }

  @Test func `bigger and smaller step by one step`() {
    let size = ReaderPreferences.defaultFontSize
    let step = ReaderPreferences.fontSizeStep
    #expect(ReaderPreferences.fontSize(steppingUp: size) == size + step)
    #expect(ReaderPreferences.fontSize(steppingDown: size) == size - step)
  }

  @Test func `stepping stops at the ends of the range`() {
    let sizes = ReaderPreferences.fontSizes
    let step = ReaderPreferences.fontSizeStep
    #expect(ReaderPreferences.fontSize(steppingUp: sizes.upperBound - step) == sizes.upperBound)
    #expect(ReaderPreferences.fontSize(steppingDown: sizes.lowerBound + step) == sizes.lowerBound)
    #expect(ReaderPreferences.fontSize(steppingUp: sizes.upperBound) == sizes.upperBound)
    #expect(ReaderPreferences.fontSize(steppingDown: sizes.lowerBound) == sizes.lowerBound)
  }

  /// A size stored outside the range steps back into it rather than further
  /// away.
  @Test func `a size outside the range steps into it`() {
    let sizes = ReaderPreferences.fontSizes
    #expect(ReaderPreferences.fontSize(steppingDown: sizes.upperBound + 10) == sizes.upperBound)
    #expect(ReaderPreferences.fontSize(steppingUp: sizes.lowerBound - 10) == sizes.lowerBound)
  }

  // MARK: - The size as a percentage

  // The iOS Aa menu shows the size between its small and large "A", as Safari's
  // page menu does.

  @Test func `the default size reads as one hundred percent`() {
    let english = Locale(identifier: "en_US")
    let size = ReaderPreferences.defaultFontSize
    #expect(ReaderPreferences.percentage(of: size, locale: english) == "100%")
  }

  @Test func `the percentage is of the default size, to the nearest whole percent`() {
    let english = Locale(identifier: "en_US")
    // 18 of 17 points is 105.9 percent.
    #expect(ReaderPreferences.percentage(of: 18, locale: english) == "106%")
    #expect(ReaderPreferences.percentage(of: 34, locale: english) == "200%")
  }

  /// The sign is set as the reader's language sets it, with the space German puts
  /// before it.
  @Test func `the percentage follows the locale`() {
    let german = Locale(identifier: "de_DE")
    let size = ReaderPreferences.defaultFontSize
    #expect(ReaderPreferences.percentage(of: size, locale: german) == "100\u{00A0}%")
  }

  /// ⌘= on the Mac, which has no `@AppStorage` to step, steps what it holds.
  @Test func `stepping up in user defaults steps the stored size`() throws {
    let suite = "ReaderPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    ReaderPreferences.stepFontSizeUp(in: defaults)
    #expect(
      defaults.double(forKey: ReaderPreferences.fontSizeKey)
        == ReaderPreferences.defaultFontSize + ReaderPreferences.fontSizeStep)

    defaults.set(ReaderPreferences.fontSizes.upperBound, forKey: ReaderPreferences.fontSizeKey)
    ReaderPreferences.stepFontSizeUp(in: defaults)
    #expect(
      defaults.double(forKey: ReaderPreferences.fontSizeKey)
        == ReaderPreferences.fontSizes.upperBound)
  }
}
