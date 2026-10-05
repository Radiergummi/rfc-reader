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
  /// Where the Settings slider, View ▸ Bigger and Smaller, and the iOS Aa
  /// menu let the size go (#153).
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

  /// `size` as a share of the default, to the nearest whole percent: what the iOS
  /// Aa menu shows between its small and large "A", as Safari's page menu does.
  /// The default size is "100%", in the interface's notation.
  public static func percentage(of size: Double, locale: Locale = .interface) -> String {
    (size / defaultFontSize).formatted(.percent.precision(.fractionLength(0)).locale(locale))
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

  /// Draw a diagram the reader can render, or show it as the text it was drawn
  /// with. A choice made in a figure's own menu overrides it for that figure.
  public static let drawDiagramsKey = "drawDiagrams"
  public static let defaultDrawDiagrams = true

  /// Notify when a bookmarked RFC is obsoleted or updated, a draft starts to revise
  /// it or reaches the RFC Editor queue, or errata are listed for it (#191). Off
  /// until the reader turns it on, which is when permission is asked for.
  public static let notifyAboutBookmarksKey = "notifyAboutBookmarks"
  public static let defaultNotifyAboutBookmarks = false

  /// The order the Contents tab lists sections in: a `ContentsOutline.Order`'s raw
  /// value.
  public static let contentsOrderKey = "contentsOrder"

  /// The preference, for what reads it outside a view and so has no `@AppStorage`:
  /// a print and an export.
  public static func drawsDiagrams(in defaults: UserDefaults) -> Bool {
    defaults.object(forKey: drawDiagramsKey) as? Bool ?? defaultDrawDiagrams
  }
}
