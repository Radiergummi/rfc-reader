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
    #expect(settings.palette.id == ReaderPreferences.defaultPalette)
  }

  /// Every key user defaults hold reads into the one value.
  @Test func `every stored key decodes`() throws {
    try withDefaults { defaults in
      defaults.set(21.0, forKey: ReaderPreferences.fontSizeKey)
      defaults.set(true, forKey: ReaderPreferences.underlineLinksKey)
      defaults.set(MeasurePreference.fullWidth.rawValue, forKey: ReaderPreferences.measureKey)
      defaults.set(true, forKey: ReaderPreferences.preferOriginalTextKey)
      defaults.set(false, forKey: ReaderPreferences.drawDiagramsKey)

      let settings = ReaderSettings(defaults: defaults)
      #expect(settings.fontSize == 21)
      #expect(settings.underlineLinks)
      #expect(settings.measure == .fullWidth)
      #expect(settings.preferOriginalText)
      #expect(!settings.drawDiagrams)
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
      defaults.set("tartan", forKey: ReaderPreferences.paletteKey)

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
      settings.write(to: defaults, replacing: ReaderSettings())
      #expect(ReaderSettings(defaults: defaults) == settings)
    }
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
      #expect(defaults.object(forKey: ReaderPreferences.paletteKey) == nil)
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
    repainted.palette = ReaderPalette(
      id: "test", cardFill: RFCColors.label, asideFill: RFCColors.label, rule: RFCColors.label,
      stroke: RFCColors.label, chipTint: RFCColors.label)
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
      BuildKey(document: id, style: settings.style(column: 500, textSize: .large))
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
}
