import Foundation
import RFCKit
import SwiftUI

/// Every reader setting, decoded once from user defaults into one value (#703).
///
/// What a reader, a preview, a print or Settings reads, rather than an
/// `@AppStorage` of each key it needs: a setting is added here and to
/// `ReaderPreferences`, and reaches every reader from there. In a view it is read
/// through `@ReaderSettingsValue`; elsewhere, `init(defaults:)`.
///
/// Each setting is either build-time, part of the `ReadingStyle` `style(column:textSize:)`
/// makes, and a change rebuilds the document; or draw-time, part of the palette
/// `palette(for:)` picks, and a change only redraws; or, like the original text and
/// the keys, neither. See
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
  /// The app's appearance, which also picks the page theme drawn (#704).
  public var appearance: AppearancePreference
  /// The page theme drawn while the app is light: one offered in light.
  public var lightPalette: ReaderPalette
  /// The page theme drawn while the app is dark: one offered in dark.
  public var darkPalette: ReaderPalette
  /// The vim-style keys in the reader (#711).
  public var vimKeys: Bool
  /// Tab and Shift-Tab through the reader's links (#711).
  public var tabsThroughLinks: Bool
  /// What a copy cites in, and where its links point (#712). Neither builds nor
  /// draws anything: read when something is copied or shared.
  public var citationStyle: CitationStyle
  public var linkSite: LinkSite
  /// What Copy puts on the pasteboard (#712).
  public var copyFormat: CopyFormat
  /// Whether a copied heading keeps its number as a prefix (#712).
  public var copiesSectionNumbers: Bool

  /// Which of the reader's keys are on.
  public var keys: ReaderKeys.Options {
    ReaderKeys.Options(vimKeys: vimKeys, tabsThroughLinks: tabsThroughLinks)
  }

  public init(
    fontSize: Double = ReaderPreferences.defaultFontSize,
    underlineLinks: Bool = ReaderPreferences.defaultUnderlineLinks,
    measure: MeasurePreference = ReaderPreferences.defaultMeasure,
    preferOriginalText: Bool = ReaderPreferences.defaultPreferOriginalText,
    drawDiagrams: Bool = ReaderPreferences.defaultDrawDiagrams,
    syntaxTheme: SyntaxTheme = .standard,
    appearance: AppearancePreference = ReaderPreferences.defaultAppearance,
    lightPalette: ReaderPalette = .automatic,
    darkPalette: ReaderPalette = .automatic,
    vimKeys: Bool = ReaderPreferences.defaultVimKeys,
    tabsThroughLinks: Bool = ReaderPreferences.defaultTabsThroughLinks,
    citationStyle: CitationStyle = ReaderPreferences.defaultCitationStyle,
    linkSite: LinkSite = ReaderPreferences.defaultLinkSite,
    copyFormat: CopyFormat = ReaderPreferences.defaultCopyFormat,
    copiesSectionNumbers: Bool = ReaderPreferences.defaultCopiesSectionNumbers
  ) {
    self.fontSize = ReaderPreferences.clamped(fontSize)
    self.underlineLinks = underlineLinks
    self.measure = measure
    self.preferOriginalText = preferOriginalText
    self.drawDiagrams = drawDiagrams
    self.syntaxTheme = syntaxTheme
    self.appearance = appearance
    self.lightPalette = lightPalette
    self.darkPalette = darkPalette
    self.vimKeys = vimKeys
    self.tabsThroughLinks = tabsThroughLinks
    self.citationStyle = citationStyle
    self.linkSite = linkSite
    self.copyFormat = copyFormat
    self.copiesSectionNumbers = copiesSectionNumbers
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
      appearance: defaults.string(forKey: Keys.appearanceKey).flatMap(AppearancePreference.init)
        ?? Keys.defaultAppearance,
      lightPalette: .named(defaults.string(forKey: Keys.lightPaletteKey), in: .light),
      darkPalette: .named(defaults.string(forKey: Keys.darkPaletteKey), in: .dark),
      vimKeys: defaults.object(forKey: Keys.vimKeysKey) as? Bool ?? Keys.defaultVimKeys,
      tabsThroughLinks: defaults.object(forKey: Keys.tabsThroughLinksKey) as? Bool
        ?? Keys.defaultTabsThroughLinks,
      citationStyle: defaults.string(forKey: Keys.citationStyleKey).flatMap(CitationStyle.init)
        ?? Keys.defaultCitationStyle,
      linkSite: defaults.string(forKey: Keys.linkSiteKey).flatMap(LinkSite.init)
        ?? Keys.defaultLinkSite,
      copyFormat: defaults.string(forKey: Keys.copyFormatKey).flatMap(CopyFormat.init)
        ?? Keys.defaultCopyFormat,
      copiesSectionNumbers: defaults.object(forKey: Keys.copiesSectionNumbersKey) as? Bool
        ?? Keys.defaultCopiesSectionNumbers
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
    if appearance != old.appearance {
      defaults.set(appearance.rawValue, forKey: Keys.appearanceKey)
    }
    if lightPalette != old.lightPalette {
      defaults.set(lightPalette.id, forKey: Keys.lightPaletteKey)
    }
    if darkPalette != old.darkPalette {
      defaults.set(darkPalette.id, forKey: Keys.darkPaletteKey)
    }
    if vimKeys != old.vimKeys { defaults.set(vimKeys, forKey: Keys.vimKeysKey) }
    if tabsThroughLinks != old.tabsThroughLinks {
      defaults.set(tabsThroughLinks, forKey: Keys.tabsThroughLinksKey)
    }
    if citationStyle != old.citationStyle {
      defaults.set(citationStyle.rawValue, forKey: Keys.citationStyleKey)
    }
    if linkSite != old.linkSite { defaults.set(linkSite.rawValue, forKey: Keys.linkSiteKey) }
    if copyFormat != old.copyFormat {
      defaults.set(copyFormat.rawValue, forKey: Keys.copyFormatKey)
    }
    if copiesSectionNumbers != old.copiesSectionNumbers {
      defaults.set(copiesSectionNumbers, forKey: Keys.copiesSectionNumbersKey)
    }
  }

  /// The draw-time half: the page theme drawn while the app is in `appearance`,
  /// the one the system's or the override makes effective.
  public func palette(for appearance: PaletteAppearance) -> ReaderPalette {
    switch appearance {
    case .light: lightPalette
    case .dark: darkPalette
    }
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
  @AppStorage private var appearance: AppearancePreference
  @AppStorage private var lightPalette: String
  @AppStorage private var darkPalette: String
  @AppStorage private var vimKeys: Bool
  @AppStorage private var tabsThroughLinks: Bool
  @AppStorage private var citationStyle: CitationStyle
  @AppStorage private var linkSite: LinkSite
  @AppStorage private var copyFormat: CopyFormat
  @AppStorage private var copiesSectionNumbers: Bool
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
    _appearance = AppStorage(
      wrappedValue: Keys.defaultAppearance, Keys.appearanceKey, store: defaults)
    _lightPalette = AppStorage(
      wrappedValue: Keys.defaultPalette, Keys.lightPaletteKey, store: defaults)
    _darkPalette = AppStorage(
      wrappedValue: Keys.defaultPalette, Keys.darkPaletteKey, store: defaults)
    _vimKeys = AppStorage(wrappedValue: Keys.defaultVimKeys, Keys.vimKeysKey, store: defaults)
    _tabsThroughLinks = AppStorage(
      wrappedValue: Keys.defaultTabsThroughLinks, Keys.tabsThroughLinksKey, store: defaults)
    _citationStyle = AppStorage(
      wrappedValue: Keys.defaultCitationStyle, Keys.citationStyleKey, store: defaults)
    _linkSite = AppStorage(wrappedValue: Keys.defaultLinkSite, Keys.linkSiteKey, store: defaults)
    _copyFormat = AppStorage(
      wrappedValue: Keys.defaultCopyFormat, Keys.copyFormatKey, store: defaults)
    _copiesSectionNumbers = AppStorage(
      wrappedValue: Keys.defaultCopiesSectionNumbers, Keys.copiesSectionNumbersKey,
      store: defaults)
  }

  /// The settings. Setting them writes what changed to user defaults.
  @MainActor public var wrappedValue: ReaderSettings {
    get {
      ReaderSettings(
        fontSize: fontSize, underlineLinks: underlineLinks, measure: measure,
        preferOriginalText: preferOriginalText, drawDiagrams: drawDiagrams,
        syntaxTheme: .named(syntaxTheme), appearance: appearance,
        lightPalette: .named(lightPalette, in: .light),
        darkPalette: .named(darkPalette, in: .dark), vimKeys: vimKeys,
        tabsThroughLinks: tabsThroughLinks, citationStyle: citationStyle, linkSite: linkSite,
        copyFormat: copyFormat, copiesSectionNumbers: copiesSectionNumbers)
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
