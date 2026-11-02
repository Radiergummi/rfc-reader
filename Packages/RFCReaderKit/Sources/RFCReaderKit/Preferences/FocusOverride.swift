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

  /// Sets `palette` in the slot or slots it belongs to, as `ReaderSettings.setTheme`
  /// does.
  public mutating func setTheme(_ palette: ReaderPalette) {
    if palette.appearances.contains(.light) { lightPalette = palette.id }
    if palette.appearances.contains(.dark) { darkPalette = palette.id }
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
    if lightPalette != nil {
      focus.lightPalette = settings.lightPalette.id
      own.lightPalette = stored.lightPalette
    }
    if darkPalette != nil {
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
    if let id = focus.lightPalette, let palette = Self.palette(id, in: .light) {
      settings.lightPalette = palette
    }
    if let id = focus.darkPalette, let palette = Self.palette(id, in: .dark) {
      settings.darkPalette = palette
    }
    if let fontSize = focus.fontSize { settings.fontSize = fontSize }
    return settings
  }

  /// Sets `palette` in the slot or slots it belongs to (#714): a light theme the
  /// light one, a dark theme the dark one, and one of both appearances both.
  public mutating func setTheme(_ palette: ReaderPalette) {
    if palette.appearances.contains(.light) { lightPalette = palette }
    if palette.appearances.contains(.dark) { darkPalette = palette }
  }

  private static func palette(_ id: String, in appearance: PaletteAppearance) -> ReaderPalette? {
    ReaderPalette.offered(in: appearance).first { $0.id == id }
  }
}
