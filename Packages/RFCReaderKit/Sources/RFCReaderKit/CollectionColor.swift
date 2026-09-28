import Foundation

/// A collection's colour: one of a fixed palette of system colours, stored by name
/// (#349). A name rather than a colour value adapts to dark mode and increased
/// contrast, and syncs as a word.
public enum CollectionColor: String, CaseIterable, Sendable, Identifiable {
  case blue, green, orange, red, purple, pink, teal, yellow, gray

  public static let `default`: CollectionColor = .blue

  /// The colour a stored name names, or the default for one this version does not
  /// know, which is what a newer device may sync to an older one.
  public init(name: String) {
    self = CollectionColor(rawValue: name) ?? .default
  }

  public var id: Self { self }

  public var title: String {
    switch self {
    case .blue: "Blue"
    case .green: "Green"
    case .orange: "Orange"
    case .red: "Red"
    case .purple: "Purple"
    case .pink: "Pink"
    case .teal: "Teal"
    case .yellow: "Yellow"
    case .gray: "Grey"
    }
  }
}
