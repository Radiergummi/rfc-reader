import CoreGraphics
import SwiftUI

/// The reader's settings as user defaults hold them: each key and its default, once.
///
/// The reader, the document preview and Settings each declare their own
/// `@AppStorage` for these, and wrote the keys and defaults out by hand every
/// time; a key misspelled in one of them is a setting that silently does nothing
/// there. The keys are what user defaults hold, so renaming one resets everyone's
/// choice.
public enum ReaderPreferences {
  /// The reader's body size, as it reads at the system's default text size.
  public static let fontSizeKey = "readingFontSize"
  public static let defaultFontSize = 17.0

  public static let underlineLinksKey = "underlineLinks"
  public static let defaultUnderlineLinks = false

  public static let measureKey = "readerMeasure"
  public static let defaultMeasure = MeasurePreference.recommended

  /// Open documents in the original text rendering rather than the reader's.
  public static let preferOriginalTextKey = "preferOriginalText"
  public static let defaultPreferOriginalText = false

  /// The style a reader at `column` builds with, from the settings. Every reader of
  /// a document — the window's and a preview's — builds through this, so the two
  /// cannot set the same settings differently.
  public static func style(
    fontSize: Double, underlineLinks: Bool, column: CGFloat, textSize: DynamicTypeSize = .large
  ) -> ReadingStyle {
    ReadingStyle(
      bodySize: fontSize, measure: column, underlinesLinks: underlineLinks, textSize: textSize)
  }
}
