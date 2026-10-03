import Foundation
import SwiftUI

/// Every reader setting, decoded once from user defaults into one value (#703).
///
/// What a reader, a preview, a print or Settings reads, rather than an
/// `@AppStorage` of each key it needs: a setting is added here and to
/// `ReaderPreferences`, and reaches every reader from there. In a view it is read
/// through `@ReaderSettingsValue`; elsewhere, `init(defaults:)`.
///
/// Each setting is either build-time, part of the `ReadingStyle` `style(column:textSize:)`
/// makes, and a change rebuilds the document; or draw-time, part of `palette`, and
/// a change only redraws. See
/// `docs/decisions/2026-10-03-reader-settings-are-a-build-time-style-and-a-draw-time-palette.md`.
public struct ReaderSettings: Sendable, Hashable {
  /// The reader's body size, as it reads at the system's default text size. Always
  /// inside `ReaderPreferences.fontSizes`.
  public var fontSize: Double {
    didSet { fontSize = ReaderPreferences.clamped(fontSize) }
  }
  public var underlineLinks: Bool
  public var measure: MeasurePreference
  /// Open documents in the original text rendering rather than the reader's.
  public var preferOriginalText: Bool
  /// Draw a diagram the reader can render; a figure's own menu overrides it.
  public var drawDiagrams: Bool
  public var syntaxTheme: SyntaxTheme
  public var palette: ReaderPalette

  public init(
    fontSize: Double = ReaderPreferences.defaultFontSize,
    underlineLinks: Bool = ReaderPreferences.defaultUnderlineLinks,
    measure: MeasurePreference = ReaderPreferences.defaultMeasure,
    preferOriginalText: Bool = ReaderPreferences.defaultPreferOriginalText,
    drawDiagrams: Bool = ReaderPreferences.defaultDrawDiagrams,
    syntaxTheme: SyntaxTheme = .standard,
    palette: ReaderPalette = .automatic
  ) {
    self.fontSize = ReaderPreferences.clamped(fontSize)
    self.underlineLinks = underlineLinks
    self.measure = measure
    self.preferOriginalText = preferOriginalText
    self.drawDiagrams = drawDiagrams
    self.syntaxTheme = syntaxTheme
    self.palette = palette
  }

  /// What `defaults` holds, each setting falling back to its default where nothing
  /// is stored, or something of the wrong type, or a theme this version does not
  /// know.
  public init(defaults: UserDefaults) {
    typealias Keys = ReaderPreferences
    self.init(
      fontSize: defaults.object(forKey: Keys.fontSizeKey) as? Double ?? Keys.defaultFontSize,
      underlineLinks: defaults.object(forKey: Keys.underlineLinksKey) as? Bool
        ?? Keys.defaultUnderlineLinks,
      measure: (defaults.string(forKey: Keys.measureKey)).flatMap(MeasurePreference.init)
        ?? Keys.defaultMeasure,
      preferOriginalText: defaults.object(forKey: Keys.preferOriginalTextKey) as? Bool
        ?? Keys.defaultPreferOriginalText,
      drawDiagrams: defaults.object(forKey: Keys.drawDiagramsKey) as? Bool
        ?? Keys.defaultDrawDiagrams,
      syntaxTheme: .named(defaults.string(forKey: Keys.syntaxThemeKey)),
      palette: .named(defaults.string(forKey: Keys.paletteKey))
    )
  }

  /// Writes to `defaults` the settings that differ from `old`, and only those, so
  /// that a setting the reader never touched stays unstored and follows its default
  /// if that changes.
  public func write(to defaults: UserDefaults, replacing old: ReaderSettings) {
    typealias Keys = ReaderPreferences
    if fontSize != old.fontSize { defaults.set(fontSize, forKey: Keys.fontSizeKey) }
    if underlineLinks != old.underlineLinks {
      defaults.set(underlineLinks, forKey: Keys.underlineLinksKey)
    }
    if measure != old.measure { defaults.set(measure.rawValue, forKey: Keys.measureKey) }
    if preferOriginalText != old.preferOriginalText {
      defaults.set(preferOriginalText, forKey: Keys.preferOriginalTextKey)
    }
    if drawDiagrams != old.drawDiagrams {
      defaults.set(drawDiagrams, forKey: Keys.drawDiagramsKey)
    }
    if syntaxTheme != old.syntaxTheme {
      defaults.set(syntaxTheme.id, forKey: Keys.syntaxThemeKey)
    }
    if palette != old.palette { defaults.set(palette.id, forKey: Keys.paletteKey) }
  }

  /// The build-time half: what the builder sets a document in, for a column of
  /// `column` points at the system's `textSize`.
  public func style(column: CGFloat, textSize: DynamicTypeSize) -> ReadingStyle {
    ReadingStyle(
      bodySize: fontSize, measure: column, underlinesLinks: underlineLinks,
      syntaxTheme: syntaxTheme, textSize: textSize)
  }
}

/// The reader's settings in a view: `ReaderSettings` as user defaults hold them,
/// and the view updated when any of them changes.
///
/// A property wrapper over user defaults rather than a model handed down the
/// environment, so it reads the same in every root: a window's hosted roots and
/// menu commands are outside any SwiftUI environment chain, and an `@Environment`
/// lookup there traps at run time with no warning at compile time.
///
///     @ReaderSettingsValue private var settings
///     …
///     Toggle("Underline links", isOn: $settings.underlineLinks)
///     settings.fontSize = ReaderPreferences.defaultFontSize
///
/// Each key is an `@AppStorage`, which is what tells SwiftUI to update the view;
/// the value is decoded from them in one place, `ReaderSettings.init`, as
/// `init(defaults:)` decodes it from user defaults.
@propertyWrapper
public struct ReaderSettingsValue: DynamicProperty {
  @AppStorage private var fontSize: Double
  @AppStorage private var underlineLinks: Bool
  @AppStorage private var measure: MeasurePreference
  @AppStorage private var preferOriginalText: Bool
  @AppStorage private var drawDiagrams: Bool
  @AppStorage private var syntaxTheme: String
  @AppStorage private var palette: String
  private let defaults: UserDefaults

  public init(store defaults: UserDefaults = .standard) {
    typealias Keys = ReaderPreferences
    self.defaults = defaults
    _fontSize = AppStorage(
      wrappedValue: Keys.defaultFontSize, Keys.fontSizeKey, store: defaults)
    _underlineLinks = AppStorage(
      wrappedValue: Keys.defaultUnderlineLinks, Keys.underlineLinksKey, store: defaults)
    _measure = AppStorage(wrappedValue: Keys.defaultMeasure, Keys.measureKey, store: defaults)
    _preferOriginalText = AppStorage(
      wrappedValue: Keys.defaultPreferOriginalText, Keys.preferOriginalTextKey, store: defaults)
    _drawDiagrams = AppStorage(
      wrappedValue: Keys.defaultDrawDiagrams, Keys.drawDiagramsKey, store: defaults)
    _syntaxTheme = AppStorage(
      wrappedValue: Keys.defaultSyntaxTheme, Keys.syntaxThemeKey, store: defaults)
    _palette = AppStorage(wrappedValue: Keys.defaultPalette, Keys.paletteKey, store: defaults)
  }

  /// The settings. Setting them writes what changed to user defaults.
  @MainActor public var wrappedValue: ReaderSettings {
    get {
      ReaderSettings(
        fontSize: fontSize, underlineLinks: underlineLinks, measure: measure,
        preferOriginalText: preferOriginalText, drawDiagrams: drawDiagrams,
        syntaxTheme: .named(syntaxTheme), palette: .named(palette))
    }
    nonmutating set {
      newValue.write(to: defaults, replacing: ReaderSettings(defaults: defaults))
    }
  }

  /// A binding to the settings, and through it to each one
  /// (`$settings.fontSize`). Setting it writes what changed to user defaults.
  @MainActor public var projectedValue: Binding<ReaderSettings> {
    let defaults = defaults
    return Binding(
      get: { ReaderSettings(defaults: defaults) },
      set: { $0.write(to: defaults, replacing: ReaderSettings(defaults: defaults)) }
    )
  }
}
