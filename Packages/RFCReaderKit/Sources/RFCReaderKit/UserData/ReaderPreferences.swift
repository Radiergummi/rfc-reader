import Foundation

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
  /// Where the Settings slider, View ▸ Bigger and Smaller, and the iOS text-size
  /// popover let the size go (#153).
  public static let fontSizes = 12.0...28.0
  /// One step of the slider, and of Bigger and Smaller.
  public static let fontSizeStep = 1.0

  /// The size after View ▸ Bigger: a step up, and never past the range.
  public static func fontSize(steppingUp size: Double) -> Double {
    clamped(size + fontSizeStep)
  }

  /// The size after View ▸ Smaller: a step down, and never past the range.
  public static func fontSize(steppingDown size: Double) -> Double {
    clamped(size - fontSizeStep)
  }

  /// View ▸ Bigger, for a caller with no `@AppStorage` of its own to step: the Mac
  /// reader window's ⌘=. What `@AppStorage` reads when nothing is stored is the
  /// default, so that is where a first step starts.
  public static func stepFontSizeUp(in defaults: UserDefaults = .standard) {
    let size = defaults.object(forKey: fontSizeKey) as? Double ?? defaultFontSize
    defaults.set(fontSize(steppingUp: size), forKey: fontSizeKey)
  }

  private static func clamped(_ size: Double) -> Double {
    min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
  }

  public static let underlineLinksKey = "underlineLinks"
  public static let defaultUnderlineLinks = false

  public static let measureKey = "readerMeasure"
  public static let defaultMeasure = MeasurePreference.recommended

  /// Open documents in the original text rendering rather than the reader's.
  public static let preferOriginalTextKey = "preferOriginalText"
  public static let defaultPreferOriginalText = false
}
