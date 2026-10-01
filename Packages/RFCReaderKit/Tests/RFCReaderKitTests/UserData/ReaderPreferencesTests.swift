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
}
