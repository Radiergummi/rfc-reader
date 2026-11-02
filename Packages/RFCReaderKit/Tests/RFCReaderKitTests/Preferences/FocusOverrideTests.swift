import Foundation
import Testing

@testable import RFCReaderKit

/// A Focus filter's reader settings (#714): a layer over the reader's own, which it
/// overrides while the Focus is on and never writes over.
@Suite("Focus override")
struct FocusOverrideTests {
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "FocusOverrideTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  @Test func `no override leaves the settings as they are`() {
    let settings = ReaderSettings(fontSize: 20, appearance: .light, lightPalette: .sepia)
    #expect(settings.overridden(by: nil) == settings)
    #expect(settings.overridden(by: FocusOverride()) == settings)
  }

  @Test func `each field overrides alone`() {
    let settings = ReaderSettings(
      fontSize: 20, appearance: .light, lightPalette: .sepia, darkPalette: .night)

    let appearance = settings.overridden(by: FocusOverride(appearance: .dark))
    #expect(appearance.appearance == .dark)
    #expect(appearance.fontSize == 20)
    #expect(appearance.lightPalette == .sepia)
    #expect(appearance.darkPalette == .night)

    let size = settings.overridden(by: FocusOverride(fontSize: 24))
    #expect(size.fontSize == 24)
    #expect(size.appearance == .light)

    let dark = settings.overridden(by: FocusOverride(darkPalette: ReaderPalette.black.id))
    #expect(dark.darkPalette == .black)
    #expect(dark.lightPalette == .sepia)
  }

  @Test func `a theme it does not know, or of the other appearance, is not applied`() {
    let settings = ReaderSettings(lightPalette: .sepia, darkPalette: .night)
    let overridden = settings.overridden(
      by: FocusOverride(lightPalette: "no-such-theme", darkPalette: ReaderPalette.paper.id))
    #expect(overridden.lightPalette == .sepia)
    #expect(overridden.darkPalette == .night)
  }

  @Test func `a size outside the range is clamped`() {
    #expect(ReaderSettings().overridden(by: FocusOverride(fontSize: 99)).fontSize == 28)
    #expect(ReaderSettings().overridden(by: FocusOverride(fontSize: 1)).fontSize == 12)
  }

  @Test func `a theme sets the slot it belongs to`() {
    var settings = ReaderSettings(lightPalette: .paper, darkPalette: .night)
    settings.setTheme(.sepia)
    #expect(settings.lightPalette == .sepia)
    #expect(settings.darkPalette == .night)
    settings.setTheme(.black)
    #expect(settings.lightPalette == .sepia)
    #expect(settings.darkPalette == .black)
    settings.setTheme(.highContrast)
    #expect(settings.lightPalette == .highContrast)
    #expect(settings.darkPalette == .highContrast)

    var focus = FocusOverride()
    focus.setTheme(.black)
    #expect(focus == FocusOverride(darkPalette: ReaderPalette.black.id))
    focus.setTheme(.automatic)
    #expect(
      focus
        == FocusOverride(
          lightPalette: ReaderPalette.automatic.id, darkPalette: ReaderPalette.automatic.id))
  }

  /// Get Reader Settings returns two themes; setting each back in its own slot
  /// must not touch the other, even for a theme made for both (#714).
  @Test func `a theme asked for one slot sets that slot alone`() {
    #expect(ReaderPalette.sepia.slots(for: nil) == [.light])
    #expect(ReaderPalette.highContrast.slots(for: nil) == [.light, .dark])
    #expect(ReaderPalette.automatic.slots(for: .dark) == [.dark])
    #expect(ReaderPalette.sepia.slots(for: .dark).isEmpty)

    var settings = ReaderSettings(lightPalette: .sepia, darkPalette: .night)
    #expect(settings.setTheme(.automatic, for: .dark) == [.dark])
    #expect(settings.lightPalette == .sepia)
    #expect(settings.darkPalette == .automatic)
    #expect(settings.setTheme(.highContrast, for: .light) == [.light])
    #expect(settings.lightPalette == .highContrast)
    #expect(settings.darkPalette == .automatic)
    #expect(settings.setTheme(.paper, for: .dark).isEmpty)
    #expect(settings.lightPalette == .highContrast)
    #expect(settings.darkPalette == .automatic)
  }

  @Test func `the controls a Focus sets are the ones Settings marks`() {
    #expect(FocusOverride(appearance: .dark).overridesAppearance)
    #expect(FocusOverride(darkPalette: ReaderPalette.black.id).overridesAppearance)
    #expect(!FocusOverride(darkPalette: "no-such-theme").overridesAppearance)
    #expect(!FocusOverride(appearance: .dark).overridesFontSize)
    #expect(FocusOverride(fontSize: 20).overridesFontSize)
    #expect(!FocusOverride(fontSize: 20).overridesAppearance)
  }

  @Test func `the settings read from defaults are the stored ones under the override`() throws {
    try withDefaults { defaults in
      defaults.set(20.0, forKey: ReaderPreferences.fontSizeKey)
      defaults.set(ReaderPalette.sepia.id, forKey: ReaderPreferences.lightPaletteKey)
      FocusOverride(appearance: .dark, darkPalette: ReaderPalette.black.id).write(to: defaults)

      let settings = ReaderSettings(defaults: defaults)
      #expect(settings.fontSize == 20)
      #expect(settings.lightPalette == .sepia)
      #expect(settings.appearance == .dark)
      #expect(settings.darkPalette == .black)
      #expect(ReaderSettings(storedIn: defaults).appearance == .system)
      #expect(ReaderSettings(storedIn: defaults).darkPalette == .automatic)
      #expect(
        FocusOverride.stored(in: defaults)
          == FocusOverride(appearance: .dark, darkPalette: ReaderPalette.black.id))
    }
  }

  @Test func `the appearance alone reads as the whole settings do`() throws {
    try withDefaults { defaults in
      #expect(ReaderSettings.appearance(in: defaults) == .system)
      defaults.set(AppearancePreference.light.rawValue, forKey: ReaderPreferences.appearanceKey)
      #expect(ReaderSettings.appearance(in: defaults) == .light)
      FocusOverride(appearance: .dark).write(to: defaults)
      #expect(ReaderSettings.appearance(in: defaults) == .dark)
      FocusOverride(fontSize: 20).write(to: defaults)
      #expect(ReaderSettings.appearance(in: defaults) == .light)
    }
  }

  @Test func `ending the Focus restores the stored settings exactly`() throws {
    try withDefaults { defaults in
      defaults.set(20.0, forKey: ReaderPreferences.fontSizeKey)
      let before = ReaderSettings(defaults: defaults)
      FocusOverride(appearance: .dark, fontSize: 26).write(to: defaults)
      #expect(ReaderSettings(defaults: defaults) != before)

      FocusOverride.remove(from: defaults)
      #expect(FocusOverride.stored(in: defaults) == nil)
      #expect(ReaderSettings(defaults: defaults) == before)
      #expect(defaults.object(forKey: ReaderPreferences.appearanceKey) == nil)
    }
  }

  @Test func `an override changed since it was read is not removed`() throws {
    try withDefaults { defaults in
      let read = FocusOverride(fontSize: 20)
      read.write(to: defaults)
      FocusOverride(fontSize: 21).write(to: defaults)
      FocusOverride.remove(from: defaults, ifStill: read)
      #expect(FocusOverride.stored(in: defaults) == FocusOverride(fontSize: 21))

      FocusOverride.remove(from: defaults, ifStill: FocusOverride(fontSize: 21))
      #expect(FocusOverride.stored(in: defaults) == nil)
    }
  }

  @Test func `an empty override is no Focus`() throws {
    try withDefaults { defaults in
      FocusOverride().write(to: defaults)
      #expect(FocusOverride.stored(in: defaults) == nil)
      #expect(defaults.object(forKey: ReaderPreferences.focusOverrideKey) == nil)
    }
  }

  @Test func `garbage in the override's key is no Focus`() throws {
    try withDefaults { defaults in
      defaults.set("not an override", forKey: ReaderPreferences.focusOverrideKey)
      #expect(FocusOverride.stored(in: defaults) == nil)
      #expect(ReaderSettings(defaults: defaults) == ReaderSettings())
    }
  }

  /// The ruling on #714: a change to a setting the Focus overrides changes the
  /// Focus's value only, so leaving the Focus restores the reader's own; any other
  /// change is stored as usual.
  @Test func `a change while a Focus is on goes to the Focus where it overrides`() throws {
    try withDefaults { defaults in
      defaults.set(ReaderPalette.sepia.id, forKey: ReaderPreferences.lightPaletteKey)
      FocusOverride(appearance: .dark, fontSize: 24).write(to: defaults)

      let old = ReaderSettings(defaults: defaults)
      var new = old
      new.fontSize = 26
      new.underlineLinks = true
      new.setTheme(.paper)
      new.write(to: defaults, replacing: old)

      #expect(FocusOverride.stored(in: defaults) == FocusOverride(appearance: .dark, fontSize: 26))
      #expect(defaults.object(forKey: ReaderPreferences.fontSizeKey) == nil)
      #expect(ReaderSettings(defaults: defaults) == new)

      FocusOverride.remove(from: defaults)
      let after = ReaderSettings(defaults: defaults)
      #expect(after.fontSize == ReaderPreferences.defaultFontSize)
      #expect(after.appearance == .system)
      #expect(after.underlineLinks)
      #expect(after.lightPalette == .paper)
    }
  }

  @Test func `a change to a theme the Focus sets goes to the Focus`() throws {
    try withDefaults { defaults in
      defaults.set(ReaderPalette.night.id, forKey: ReaderPreferences.darkPaletteKey)
      FocusOverride(darkPalette: ReaderPalette.black.id).write(to: defaults)

      ReaderSettings.change(in: defaults) { $0.setTheme(.highContrast) }

      #expect(
        FocusOverride.stored(in: defaults)
          == FocusOverride(darkPalette: ReaderPalette.highContrast.id))
      #expect(defaults.string(forKey: ReaderPreferences.darkPaletteKey) == ReaderPalette.night.id)
      #expect(
        defaults.string(forKey: ReaderPreferences.lightPaletteKey)
          == ReaderPalette.highContrast.id)
    }
  }

  /// A theme the Focus names that this version does not know is not drawn, so the
  /// reader's own shows, and a change to it is the reader's, not the Focus's.
  @Test func `a change to a slot whose Focus theme is unknown is the reader's`() throws {
    try withDefaults { defaults in
      FocusOverride(darkPalette: "no-such-theme", fontSize: 20).write(to: defaults)

      ReaderSettings.change(in: defaults) { $0.setTheme(.black) }

      #expect(defaults.string(forKey: ReaderPreferences.darkPaletteKey) == ReaderPalette.black.id)
      #expect(
        FocusOverride.stored(in: defaults)
          == FocusOverride(darkPalette: "no-such-theme", fontSize: 20))
      #expect(ReaderSettings(defaults: defaults).darkPalette == .black)
    }
  }

  @Test func `a size step while a Focus is on steps the Focus's size`() throws {
    try withDefaults { defaults in
      FocusOverride(fontSize: 24).write(to: defaults)
      ReaderPreferences.stepFontSizeUp(in: defaults)
      #expect(FocusOverride.stored(in: defaults) == FocusOverride(fontSize: 25))
      #expect(defaults.object(forKey: ReaderPreferences.fontSizeKey) == nil)
    }
  }
}
