import Foundation

/// A highlight's color (#522): a fixed, named palette, stored by name, as
/// `CollectionColor` is. `underline` is one of them, and draws a rule under the text
/// rather than a fill.
public enum HighlightColor: String, CaseIterable, Sendable, Identifiable {
  case yellow, green, blue, pink, purple, underline

  public static let `default`: HighlightColor = .yellow

  /// The color a stored name names, or the default for one this version does not
  /// know, which is what a newer device may sync to an older one.
  public init(name: String) {
    self = HighlightColor(rawValue: name) ?? .default
  }

  public var id: Self { self }

  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .yellow: String(kit: "Yellow", locale: locale)
    case .green: String(kit: "Green", locale: locale)
    case .blue: String(kit: "Blue", locale: locale)
    case .pink: String(kit: "Pink", locale: locale)
    case .purple: String(kit: "Purple", locale: locale)
    case .underline: String(kit: "Underline", locale: locale)
    }
  }

  /// A color and how opaque it is drawn.
  public typealias Tint = (color: SRGBColor, opacity: Double)

  /// The fill, a fixed sRGB color with an opacity per appearance, drawn translucent
  /// beneath the text so a selection inside it shows, and blending with a card's
  /// fill where it lies over one. Faint enough that the text over it keeps 4.5:1 on
  /// the page and on every card, in light and in dark, and a link 3.5:1: a link held
  /// to 4.5:1 as well left fills too faint to find again, the most any could take
  /// being 1.05:1 against white (`HighlightColorTests`). The underline's is its rule's
  /// color, drawn opaque.
  public var fill: (light: Tint, dark: Tint) {
    switch self {
    case .yellow:
      (light: (SRGBColor(hex: 0xFF_D60A), 0.4), dark: (SRGBColor(hex: 0xFF_D60A), 0.16))
    case .green:
      (light: (SRGBColor(hex: 0x34_C759), 0.3), dark: (SRGBColor(hex: 0x30_D158), 0.2))
    case .blue:
      (light: (SRGBColor(hex: 0x0A_84FF), 0.22), dark: (SRGBColor(hex: 0x40_9CFF), 0.24))
    case .pink:
      (light: (SRGBColor(hex: 0xFF_2D55), 0.2), dark: (SRGBColor(hex: 0xFF_375F), 0.26))
    case .purple:
      (light: (SRGBColor(hex: 0xAF_52DE), 0.22), dark: (SRGBColor(hex: 0xBF_5AF2), 0.26))
    case .underline:
      (light: (SRGBColor(hex: 0xE6_8A00), 1), dark: (SRGBColor(hex: 0xFF_B340), 1))
    }
  }

  /// Whether this color draws a rule under the text rather than a fill.
  public var isUnderline: Bool { self == .underline }
}
