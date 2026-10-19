import RFCKit
import SwiftUI
import Testing

@testable import RFCReaderKit

/// Every reader setting, decoded once from user defaults (#703).
@Suite("Reader settings")
struct ReaderSettingsTests {
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "ReaderSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  @Test func `nothing stored decodes to the defaults`() throws {
    try withDefaults { defaults in
      #expect(ReaderSettings(defaults: defaults) == ReaderSettings())
    }
  }

  @Test func `the defaults are the preferences' defaults`() {
    let settings = ReaderSettings()
    #expect(settings.fontSize == ReaderPreferences.defaultFontSize)
    #expect(settings.underlineLinks == ReaderPreferences.defaultUnderlineLinks)
    #expect(settings.measure == ReaderPreferences.defaultMeasure)
    #expect(settings.preferOriginalText == ReaderPreferences.defaultPreferOriginalText)
    #expect(settings.drawDiagrams == ReaderPreferences.defaultDrawDiagrams)
    #expect(settings.syntaxTheme.id == ReaderPreferences.defaultSyntaxTheme)
    #expect(settings.appearance == ReaderPreferences.defaultAppearance)
    #expect(settings.lightPalette.id == ReaderPreferences.defaultPalette)
    #expect(settings.darkPalette.id == ReaderPreferences.defaultPalette)
    #expect(settings.citationStyle == .markdown)
    #expect(settings.linkSite == .rfcEditor)
    #expect(settings.copyFormat == .text)
    #expect(settings.copiesSectionNumbers)
  }

  /// What a copy cites in, where it links and what Copy copies (#712).
  @Test func `the sharing settings decode, and garbage falls back`() throws {
    try withDefaults { defaults in
      defaults.set("xml2rfc", forKey: ReaderPreferences.citationStyleKey)
      defaults.set("datatracker", forKey: ReaderPreferences.linkSiteKey)
      defaults.set("quote", forKey: ReaderPreferences.copyFormatKey)
      defaults.set(false, forKey: ReaderPreferences.copiesSectionNumbersKey)
      let settings = ReaderSettings(defaults: defaults)
      #expect(settings.citationStyle == .xml2rfc)
      #expect(settings.linkSite == .datatracker)
      #expect(settings.copyFormat == .quote)
      #expect(!settings.copiesSectionNumbers)

      defaults.set("chicago", forKey: ReaderPreferences.citationStyleKey)
      defaults.set("example.com", forKey: ReaderPreferences.linkSiteKey)
      defaults.set("markdown", forKey: ReaderPreferences.copyFormatKey)
      defaults.set("no", forKey: ReaderPreferences.copiesSectionNumbersKey)
      #expect(ReaderSettings(defaults: defaults) == ReaderSettings())
    }
  }

  /// Every key user defaults hold reads into the one value.
  @Test func `every stored key decodes`() throws {
    try withDefaults { defaults in
      defaults.set(21.0, forKey: ReaderPreferences.fontSizeKey)
      defaults.set(true, forKey: ReaderPreferences.underlineLinksKey)
      defaults.set(MeasurePreference.fullWidth.rawValue, forKey: ReaderPreferences.measureKey)
      defaults.set(true, forKey: ReaderPreferences.preferOriginalTextKey)
      defaults.set(false, forKey: ReaderPreferences.drawDiagramsKey)
      defaults.set(AppearancePreference.dark.rawValue, forKey: ReaderPreferences.appearanceKey)
      defaults.set(ReaderPalette.sepia.id, forKey: ReaderPreferences.lightPaletteKey)
      defaults.set(ReaderPalette.black.id, forKey: ReaderPreferences.darkPaletteKey)

      let settings = ReaderSettings(defaults: defaults)
      #expect(settings.fontSize == 21)
      #expect(settings.underlineLinks)
      #expect(settings.measure == .fullWidth)
      #expect(settings.preferOriginalText)
      #expect(!settings.drawDiagrams)
      #expect(settings.appearance == .dark)
      #expect(settings.lightPalette == .sepia)
      #expect(settings.darkPalette == .black)
    }
  }

  /// A value of the wrong type, a measure or theme this version does not know, falls
  /// back to the default rather than failing or reading as something else.
  @Test func `garbage falls back to the default`() throws {
    try withDefaults { defaults in
      defaults.set("large", forKey: ReaderPreferences.fontSizeKey)
      defaults.set("yes", forKey: ReaderPreferences.underlineLinksKey)
      defaults.set("narrow", forKey: ReaderPreferences.measureKey)
      defaults.set("solarized-2031", forKey: ReaderPreferences.syntaxThemeKey)
      defaults.set("dusk", forKey: ReaderPreferences.appearanceKey)
      defaults.set("tartan", forKey: ReaderPreferences.lightPaletteKey)
      defaults.set(7, forKey: ReaderPreferences.darkPaletteKey)

      #expect(ReaderSettings(defaults: defaults) == ReaderSettings())
    }
  }

  /// A size stored outside the range reads as the nearest end of it.
  @Test func `a size outside the range is clamped`() throws {
    try withDefaults { defaults in
      defaults.set(99.0, forKey: ReaderPreferences.fontSizeKey)
      #expect(ReaderSettings(defaults: defaults).fontSize == ReaderPreferences.fontSizes.upperBound)
    }
    var settings = ReaderSettings()
    settings.fontSize = 1
    #expect(settings.fontSize == ReaderPreferences.fontSizes.lowerBound)
  }

  @Test func `writing round trips`() throws {
    try withDefaults { defaults in
      var settings = ReaderSettings()
      settings.fontSize = 20
      settings.underlineLinks = true
      settings.measure = .fullWidth
      settings.preferOriginalText = true
      settings.drawDiagrams = false
      settings.appearance = .light
      settings.lightPalette = .gray
      settings.darkPalette = .night
      settings.citationStyle = .bibtex
      settings.linkSite = .app
      settings.copyFormat = .quote
      settings.copiesSectionNumbers = false
      settings.write(to: defaults, replacing: ReaderSettings())
      #expect(ReaderSettings(defaults: defaults) == settings)
    }
  }

  /// A theme is drawn only in an appearance it belongs to: one of the other
  /// appearance stored for this one reads as the automatic theme (#704).
  @Test func `a theme of the other appearance falls back to automatic`() throws {
    try withDefaults { defaults in
      defaults.set(ReaderPalette.black.id, forKey: ReaderPreferences.lightPaletteKey)
      defaults.set(ReaderPalette.sepia.id, forKey: ReaderPreferences.darkPaletteKey)
      let settings = ReaderSettings(defaults: defaults)
      #expect(settings.lightPalette == .automatic)
      #expect(settings.darkPalette == .automatic)
    }
  }

  /// The appearance the app is drawn in picks the light theme or the dark one, and
  /// High Contrast, which has both, can be either (#704).
  @Test func `the effective appearance picks the light or the dark theme`() {
    let settings = ReaderSettings(lightPalette: .sepia, darkPalette: .highContrast)
    #expect(settings.palette(for: .light) == .sepia)
    #expect(settings.palette(for: .dark) == .highContrast)
    #expect(ReaderSettings().palette(for: .light) == .automatic)
    #expect(ReaderSettings().palette(for: .dark) == .automatic)
  }

  /// System follows the system's appearance; Light and Dark force theirs whatever
  /// the system's is.
  @Test func `the appearance override decides the effective appearance`() {
    for system in PaletteAppearance.allCases {
      #expect(AppearancePreference.system.effective(system: system) == system)
      #expect(AppearancePreference.light.effective(system: system) == .light)
      #expect(AppearancePreference.dark.effective(system: system) == .dark)
    }
    #expect(AppearancePreference.system.forced == nil)
    #expect(PaletteAppearance(ColorScheme.dark) == .dark)
    #expect(PaletteAppearance(ColorScheme.light) == .light)
  }

  /// A setting the reader never touched stays unstored, and so follows its default
  /// if a later version changes it.
  @Test func `writing stores only what changed`() throws {
    try withDefaults { defaults in
      var settings = ReaderSettings()
      settings.underlineLinks = true
      settings.write(to: defaults, replacing: ReaderSettings())
      #expect(defaults.object(forKey: ReaderPreferences.underlineLinksKey) != nil)
      #expect(defaults.object(forKey: ReaderPreferences.fontSizeKey) == nil)
      #expect(defaults.object(forKey: ReaderPreferences.syntaxThemeKey) == nil)
      #expect(defaults.object(forKey: ReaderPreferences.appearanceKey) == nil)
      #expect(defaults.object(forKey: ReaderPreferences.lightPaletteKey) == nil)
      #expect(defaults.object(forKey: ReaderPreferences.darkPaletteKey) == nil)
    }
  }

  // MARK: - Build-time and draw-time

  @Test func `the style carries the build-time settings`() {
    var settings = ReaderSettings()
    settings.fontSize = 20
    settings.underlineLinks = true
    let style = settings.style(column: 500, textSize: .large)
    #expect(style.bodySize == 20)
    #expect(style.measure == 500)
    #expect(style.underlinesLinks)
    #expect(style.syntaxTheme == settings.syntaxTheme)
  }

  /// A draw-time setting must never key a build: changing the palette may not
  /// rebuild a document, or invalidate a cached preview.
  @Test func `the palette is not part of the style`() {
    let settings = ReaderSettings()
    var repainted = settings
    repainted.appearance = .dark
    repainted.lightPalette = .sepia
    repainted.darkPalette = .black
    #expect(
      settings.style(column: 500, textSize: .large)
        == repainted.style(column: 500, textSize: .large))
  }

  /// Each build-time setting is a reason to build again, so it must change the
  /// style, which keys the preview cache (`BuildKey`).
  @Test func `every build-time setting changes the build key`() {
    let id = DocumentID.rfc(9110)
    let base = ReaderSettings()
    func key(_ settings: ReaderSettings) -> BuildKey {
      BuildKey(
        document: id, style: settings.style(column: 500, textSize: .large), boldText: false)
    }
    var bigger = base
    bigger.fontSize += 1
    var underlined = base
    underlined.underlineLinks.toggle()
    var themed = base
    themed.syntaxTheme = SyntaxTheme(id: "test", [:])
    for changed in [bigger, underlined, themed] {
      #expect(key(changed) != key(base))
    }
  }

  /// Bold Text is applied to the fonts as they are made, so a build made before it
  /// was turned on is not the build after (#765): a kept preview keyed without it
  /// came back in the old weight.
  @Test func `bold text changes the build key`() {
    let style = ReaderSettings().style(column: 500, textSize: .large)
    #expect(
      BuildKey(document: .rfc(9110), style: style, boldText: true)
        != BuildKey(document: .rfc(9110), style: style, boldText: false))
  }
}
