import SwiftUI

/// The appearance the whole app is drawn in (#704): the system's, or one the reader
/// chose, as Apple Books lets them. The whole app rather than the page alone, since
/// a light sidebar beside a black page looks broken; the page theme drawn is the
/// light or the dark one by the appearance this makes effective.
///
/// A setting, stored by its raw value, so the case names are what user defaults
/// hold.
public enum AppearancePreference: String, CaseIterable, Sendable {
  case system
  case light
  case dark

  /// The appearance it forces, or nil to follow the system's.
  public var forced: PaletteAppearance? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

extension PaletteAppearance {
  /// The appearance SwiftUI draws in: under an override, the one forced.
  public init(_ scheme: ColorScheme) {
    self = scheme == .dark ? .dark : .light
  }
}
