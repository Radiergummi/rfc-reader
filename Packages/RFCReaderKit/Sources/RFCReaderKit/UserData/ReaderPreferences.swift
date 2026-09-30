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
}
