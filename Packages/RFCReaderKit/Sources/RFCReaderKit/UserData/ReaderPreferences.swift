import Foundation

/// The reader's settings as user defaults hold them: each key and its default, once.
///
/// Read through `ReaderSettings`, which decodes them all into one value, and in a
/// view through `@ReaderSettingsValue`, rather than through an `@AppStorage` of each
/// key in every view that needs one: a key misspelled in one of those was a setting
/// that silently did nothing there. The keys are what user defaults hold, so
/// renaming one resets everyone's choice.
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
  /// The default size is "100%", in the reader's own language's notation.
  public static func percentage(of size: Double, locale: Locale = .current) -> String {
    (size / defaultFontSize).formatted(.percent.precision(.fractionLength(0)).locale(locale))
  }

  /// View ▸ Bigger, for a caller with no `@AppStorage` of its own to step: the Mac
  /// reader window's ⌘=. What `@AppStorage` reads when nothing is stored is the
  /// default, so that is where a first step starts.
  public static func stepFontSizeUp(in defaults: UserDefaults = .standard) {
    let size = defaults.object(forKey: fontSizeKey) as? Double ?? defaultFontSize
    defaults.set(fontSize(steppingUp: size), forKey: fontSizeKey)
  }

  static func clamped(_ size: Double) -> Double {
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

  /// The preference, for what reads it outside a view: a print and an export.
  public static func drawsDiagrams(in defaults: UserDefaults) -> Bool {
    ReaderSettings(defaults: defaults).drawDiagrams
  }

  /// The syntax theme's `SyntaxTheme.id`.
  public static let syntaxThemeKey = "syntaxTheme"
  public static let defaultSyntaxTheme = SyntaxTheme.standard.id

  /// The page palette's `ReaderPalette.id`.
  public static let paletteKey = "readerPalette"
  public static let defaultPalette = ReaderPalette.automatic.id
}
