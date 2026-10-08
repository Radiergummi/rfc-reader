import Foundation

/// A color as its sRGB components, each in 0...1, for the arithmetic a platform
/// color does not expose: a system color resolves differently by appearance,
/// platform and OS release, so a color whose contrast is checked has to be one the
/// code states itself.
public struct SRGBColor: Hashable, Sendable {
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

  public static let white = SRGBColor(red: 1, green: 1, blue: 1)
  /// For the tests, which check the contrast formula against its extremes.
  static let black = SRGBColor(red: 0, green: 0, blue: 0)

  /// WCAG 2.x relative luminance: each channel linearized from the sRGB curve, then
  /// weighted by how bright the eye finds it. 0 is black, 1 is white.
  public var relativeLuminance: Double {
    0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
  }

  /// WCAG 2.x contrast ratio, (L1 + 0.05) / (L2 + 0.05) with L1 the lighter: from
  /// 1:1 for a color against itself to 21:1 for white against black. Symmetric.
  public func contrast(with other: SRGBColor) -> Double {
    let lighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// This color drawn at `opacity` over `page`: what a translucent fill looks like
  /// where it is drawn, blended in sRGB as the platforms composite.
  public func composited(opacity: Double, over page: SRGBColor) -> SRGBColor {
    SRGBColor(
      red: red * opacity + page.red * (1 - opacity),
      green: green * opacity + page.green * (1 - opacity),
      blue: blue * opacity + page.blue * (1 - opacity))
  }

  /// This color, darkened just enough to contrast `minimum` with `other`, a lighter
  /// color; itself when it already does. Darkened by scaling its linear-light
  /// channels equally, which keeps the hue, as the badge palette was made (#516).
  public func darkened(toContrast minimum: Double, against other: SRGBColor) -> SRGBColor {
    guard contrast(with: other) < minimum else { return self }
    let channels = linearChannels
    func scaled(_ factor: Double) -> SRGBColor {
      SRGBColor(
        red: Self.encoded(channels[0] * factor), green: Self.encoded(channels[1] * factor),
        blue: Self.encoded(channels[2] * factor))
    }
    // The largest factor that still clears it: contrast with a lighter color only
    // grows as the factor falls, so a bisection finds it.
    var clears = 0.0
    var fails = 1.0
    for _ in 0..<50 {
      let factor = (clears + fails) / 2
      if scaled(factor).contrast(with: other) >= minimum {
        clears = factor
      } else {
        fails = factor
      }
    }
    return scaled(clears)
  }

  /// This color, lightened just enough to contrast `minimum` with `other`, a darker
  /// color; itself when it already does. Lightened by mixing it with white, which
  /// keeps its hue as it pales; white itself where nothing short of it clears.
  public func lightened(toContrast minimum: Double, against other: SRGBColor) -> SRGBColor {
    guard contrast(with: other) < minimum else { return self }
    // The least white that clears it: contrast with a darker color only grows as
    // the mix does, so a bisection finds it.
    var fails = 0.0
    var clears = 1.0
    for _ in 0..<50 {
      let amount = (fails + clears) / 2
      if SRGBColor.white.composited(opacity: amount, over: self).contrast(with: other) >= minimum {
        clears = amount
      } else {
        fails = amount
      }
    }
    return SRGBColor.white.composited(opacity: clears, over: self)
  }

  /// The channels with the sRGB curve undone.
  var linearChannels: [Double] { [red, green, blue].map(Self.linear) }

  /// The sRGB transfer function undone: linear below 0.04045, a 2.4 power above.
  private static func linear(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
  }

  /// The sRGB transfer function, the inverse of `linear`.
  private static func encoded(_ linear: Double) -> Double {
    linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
  }
}
