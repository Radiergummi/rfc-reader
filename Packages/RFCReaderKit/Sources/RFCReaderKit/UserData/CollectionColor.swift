import Foundation

/// A collection's color: one of a fixed palette of system colors, stored by name
/// (#349). A name rather than a color value adapts to dark mode and increased
/// contrast, and syncs as a word.
public enum CollectionColor: String, CaseIterable, Sendable, Identifiable {
  case blue, green, orange, red, purple, pink, teal, yellow, gray

  public static let `default`: CollectionColor = .blue

  /// The color a stored name names, or the default for one this version does not
  /// know, which is what a newer device may sync to an older one.
  public init(name: String) {
    self = CollectionColor(rawValue: name) ?? .default
  }

  public var id: Self { self }

  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .blue: String(kit: "Blue", locale: locale)
    case .green: String(kit: "Green", locale: locale)
    case .orange: String(kit: "Orange", locale: locale)
    case .red: String(kit: "Red", locale: locale)
    case .purple: String(kit: "Purple", locale: locale)
    case .pink: String(kit: "Pink", locale: locale)
    case .teal: String(kit: "Teal", locale: locale)
    case .yellow: String(kit: "Yellow", locale: locale)
    case .gray: String(kit: "Gray", locale: locale)
    }
  }
}
