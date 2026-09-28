import Foundation

/// A colour as its sRGB components, each in 0...1, for the arithmetic a platform
/// colour does not expose: a system colour resolves differently by appearance,
/// platform and OS release, so a colour whose contrast is checked has to be one the
/// code states itself.
public struct SRGBColour: Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// `0xRRGGBB`, the way a design tool writes it.
  public init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  public static let white = SRGBColour(red: 1, green: 1, blue: 1)
  public static let black = SRGBColour(red: 0, green: 0, blue: 0)

  /// WCAG 2.x relative luminance: each channel linearised from the sRGB curve, then
  /// weighted by how bright the eye finds it. 0 is black, 1 is white.
  public var relativeLuminance: Double {
    0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
  }

  /// WCAG 2.x contrast ratio, (L1 + 0.05) / (L2 + 0.05) with L1 the lighter: from
  /// 1:1 for a colour against itself to 21:1 for white against black. Symmetric.
  public func contrast(with other: SRGBColour) -> Double {
    let lighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// The sRGB transfer function undone: linear below 0.04045, a 2.4 power above.
  private static func linear(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
  }
}
