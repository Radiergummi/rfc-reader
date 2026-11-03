import Foundation

/// The reader settings a Focus filter sets while its Focus is on (#714): a layer
/// over the reader's own, which `ReaderSettings(defaults:)` puts on top of them and
/// nothing writes over them. Leaving the Focus removes it, and the reader's own
/// settings are back exactly as they were.
///
/// Each field is nil where the filter leaves that setting alone. Stored as JSON
/// under `ReaderPreferences.focusOverrideKey`, absent while no filter is active.
public struct FocusOverride: Codable, Sendable, Hashable {
  public var appearance: AppearancePreference?
  /// A `ReaderPalette.id` offered in light.
  public var lightPalette: String?
  /// A `ReaderPalette.id` offered in dark.
  public var darkPalette: String?
  public var fontSize: Double?

  public init(
    appearance: AppearancePreference? = nil, lightPalette: String? = nil,
    darkPalette: String? = nil, fontSize: Double? = nil
  ) {
    self.appearance = appearance
    self.lightPalette = lightPalette
    self.darkPalette = darkPalette
    self.fontSize = fontSize
  }

  /// Whether it overrides nothing, which is no Focus at all.
  public var isEmpty: Bool { self == FocusOverride() }

  /// Whether it sets the appearance or a theme, which Settings says under their
  /// pickers. A theme it names that this version does not know sets nothing.
  public var overridesAppearance: Bool {
    appearance != nil || ownedPalette(lightPalette, in: .light) != nil
      || ownedPalette(darkPalette, in: .dark) != nil
  }

  /// Whether it sets the text size, which Settings says under the slider.
  public var overridesFontSize: Bool { fontSize != nil }

  /// Sets `palette` in the slots `ReaderPalette.slots(for:)` gives, as
  /// `ReaderSettings.setTheme` does.
  public mutating func setTheme(_ palette: ReaderPalette) {
    for slot in palette.slots(for: nil) {
      switch slot {
      case .light: lightPalette = palette.id
      case .dark: darkPalette = palette.id
      }
    }
  }

  /// The override `defaults` holds, or nil while no Focus filter is active.
  public static func stored(in defaults: UserDefaults) -> FocusOverride? {
    decoded(defaults.data(forKey: ReaderPreferences.focusOverrideKey))
  }

  /// The override in what its key holds, or nil for nothing, garbage or an empty one.
  static func decoded(_ data: Data?) -> FocusOverride? {
    guard let data, let stored = try? JSONDecoder().decode(FocusOverride.self, from: data),
      !stored.isEmpty
    else { return nil }
    return stored
  }

  /// Stores it in `defaults`; an empty one is removed instead.
  public func write(to defaults: UserDefaults) {
    guard !isEmpty, let data = try? JSONEncoder().encode(self) else {
      Self.remove(from: defaults)
      return
    }
    defaults.set(data, forKey: ReaderPreferences.focusOverrideKey)
  }

  /// Ends the Focus's settings: the reader's own are drawn again.
  public static func remove(from defaults: UserDefaults) {
    defaults.removeObject(forKey: ReaderPreferences.focusOverrideKey)
  }

  /// Ends the Focus's settings only if `defaults` still holds `expected`: for a check
  /// that read the override, then waited, during which a Focus may have started or
  /// the reader stepped its size, neither of which it may wipe.
  public static func remove(from defaults: UserDefaults, ifStill expected: FocusOverride) {
    guard stored(in: defaults) == expected else { return }
    remove(from: defaults)
  }

  /// `settings`, a change made while the Focus is on, split between the two layers:
  /// what the Focus overrides goes into the Focus, and the rest is the reader's own,
  /// whose overridden settings stay what `stored` holds.
  func absorbing(
    _ settings: ReaderSettings, over stored: ReaderSettings
  ) -> (stored: ReaderSettings, focus: FocusOverride) {
    var own = settings
    var focus = self
    if appearance != nil {
      focus.appearance = settings.appearance
      own.appearance = stored.appearance
    }
    // A slot is the Focus's only where its theme resolves, as `overridden(by:)`
    // draws it: under a theme this version does not know, the reader's own shows,
    // and a change to it is the reader's.
    if ownedPalette(lightPalette, in: .light) != nil {
      focus.lightPalette = settings.lightPalette.id
      own.lightPalette = stored.lightPalette
    }
    if ownedPalette(darkPalette, in: .dark) != nil {
      focus.darkPalette = settings.darkPalette.id
      own.darkPalette = stored.darkPalette
    }
    if fontSize != nil {
      focus.fontSize = settings.fontSize
      own.fontSize = stored.fontSize
    }
    return (own, focus)
  }
}

extension ReaderSettings {
  /// These settings with `focus` on top: what the reader draws while a Focus filter
  /// is active. A theme the version does not know, or one of the other appearance,
  /// leaves the reader's own.
  public func overridden(by focus: FocusOverride?) -> ReaderSettings {
    guard let focus else { return self }
    var settings = self
    if let appearance = focus.appearance { settings.appearance = appearance }
    if let palette = ownedPalette(focus.lightPalette, in: .light) {
      settings.lightPalette = palette
    }
    if let palette = ownedPalette(focus.darkPalette, in: .dark) {
      settings.darkPalette = palette
    }
    if let fontSize = focus.fontSize { settings.fontSize = fontSize }
    return settings
  }

  /// Sets `palette` in the slots `ReaderPalette.slots(for:)` gives for `slot` (#714),
  /// and returns them: empty when it is not offered in the slot asked for.
  @discardableResult
  public mutating func setTheme(
    _ palette: ReaderPalette, for slot: PaletteAppearance? = nil
  ) -> Set<PaletteAppearance> {
    let slots = palette.slots(for: slot)
    for slot in slots {
      switch slot {
      case .light: lightPalette = palette
      case .dark: darkPalette = palette
      }
    }
    return slots
  }

  /// The appearance `init(defaults:)` would decode, without decoding the rest: what
  /// the macOS appearance observer reads on every write to user defaults.
  public static func appearance(in defaults: UserDefaults) -> AppearancePreference {
    FocusOverride.stored(in: defaults)?.appearance
      ?? defaults.string(forKey: ReaderPreferences.appearanceKey)
      .flatMap(AppearancePreference.init) ?? ReaderPreferences.defaultAppearance
  }
}

extension ReaderPalette {
  /// The slots, the light theme and the dark one, that setting it fills (#714): those
  /// of the appearances it is made for, or, when `slot` is asked for, that one alone
  /// if it is made for it. A theme of both appearances fills both unless asked for
  /// one, which is how Get Reader Settings' two themes are set back.
  public func slots(for slot: PaletteAppearance?) -> Set<PaletteAppearance> {
    guard let slot else { return appearances }
    return appearances.intersection([slot])
  }
}

/// The theme called `id` among those offered in `appearance`, or nil for no id or
/// one this version does not know there: what decides whether a Focus's slot is
/// drawn, and so whether it is the Focus's.
private func ownedPalette(_ id: String?, in appearance: PaletteAppearance) -> ReaderPalette? {
  guard let id else { return nil }
  return ReaderPalette.offered(in: appearance).first { $0.id == id }
}
