import RFCKit

/// The status badges' colors: a text color on a fill, for each status and for an
/// obsolete document, in light and dark appearance (#317).
///
/// Stated rather than taken from the system colors, as the author monograms' are
/// (`AuthorMonogram.palette`). The badges drew each status's system color on a 15%
/// tint of itself, which measured 1.95:1 (Experimental) to 3.42:1 (BCP) in light
/// appearance, and a system color resolves differently by appearance, platform and
/// OS release, so no one measurement would hold. These keep those hues:
///
/// - **Light:** the fill is the iOS light system color at 15% over white, as the
///   badge drew it; the text is the same color darkened, by scaling its
///   linear-light channels equally, which keeps the hue, until it clears
///   ``minimumContrast`` on the fill.
/// - **Dark:** the fill is the dark system color at 20% opacity, so the pill takes
///   the color of what is behind it: pure black in the iOS document header,
///   `#1C1C1E` in a list cell (``darkBackgrounds``). The text is the same color
///   lightened toward white until it clears the fill over `#1C1C1E`, the lighter of
///   the two, which is the harder one. Standards and Experimental passed as they
///   were.
///
/// The light fill is opaque, as the badge has always drawn it.
public enum StatusPalette {
  /// What text at standard sizes needs, per Apple's Human Interface Guidelines, as
  /// the monograms are held to.
  public static let minimumContrast = AuthorMonogram.minimumContrast

  public enum Appearance: CaseIterable, Sendable {
    case light, dark
  }

  public struct Colors: Hashable, Sendable {
    public let text: SRGBColor
    /// The fill's color, drawn at ``fillOpacity`` over whatever is behind it.
    public let fill: SRGBColor
    public let fillOpacity: Double

    /// The fill as it shows over `background`: blended in sRGB, as the compositor
    /// blends it.
    public func fill(over background: SRGBColor) -> SRGBColor {
      func blend(_ fill: Double, _ background: Double) -> Double {
        fillOpacity * fill + (1 - fillOpacity) * background
      }
      return SRGBColor(
        red: blend(fill.red, background.red),
        green: blend(fill.green, background.green),
        blue: blend(fill.blue, background.blue))
    }
  }

  /// What a dark badge is drawn over: the iOS document header's pure black, and a
  /// list cell's `#1C1C1E`.
  public static let darkBackgrounds = [SRGBColor.black, SRGBColor(hex: 0x1C_1C1E)]

  /// The backgrounds a fill in `appearance` is measured over: white for the opaque
  /// light fills, where it makes no difference, and ``darkBackgrounds``.
  public static func backgrounds(in appearance: Appearance) -> [SRGBColor] {
    appearance == .light ? [.white] : darkBackgrounds
  }

  public static func colors(for status: PublicationStatus, in appearance: Appearance) -> Colors {
    let (light, dark) = pair(for: status)
    return appearance == .light ? light : dark
  }

  /// The Info pane's Obsolete box, which is red: made the same way as a status's.
  public static func obsolete(in appearance: Appearance) -> Colors {
    // 4.51:1 light (the system color's 2.90:1); dark 4.54:1 over #1C1C1E and 5.88:1
    // over black (3.94:1 and 5.10:1).
    appearance == .light
      ? colors(0xC7_2C23, on: 0xFF_E2E0) : colors(0xFF_6158, over: 0xFF_453A)
  }

  private static func pair(for status: PublicationStatus) -> (light: Colors, dark: Colors) {
    // Dark contrasts are over #1C1C1E and over black.
    switch status {
    // Green: 4.62:1 light (the system color's 1.97:1), 5.67:1 and 7.70:1 dark (unchanged).
    case .internetStandard, .draftStandard:
      (colors(0x1D_7D35, on: 0xE1_F7E6), colors(0x30_D158, over: 0x30_D158))
    // Blue: 4.65:1 light (3.30:1), 4.63:1 and 6.08:1 dark (3.64:1).
    case .proposedStandard:
      (colors(0x00_63D2, on: 0xD9_EBFF), colors(0x5A_97FF, over: 0x0A_84FF))
    // Purple: 4.66:1 light (3.42:1), 4.62:1 and 6.09:1 dark (3.74:1).
    case .bestCurrentPractice:
      (colors(0x92_43BA, on: 0xF3_E5FA), colors(0xC6_78F3, over: 0xBF_5AF2))
    // Orange: 4.66:1 light (1.95:1), 5.57:1 and 7.59:1 dark (unchanged).
    case .experimental:
      (colors(0xA0_5B00, on: 0xFF_EFD9), colors(0xFF_9F0A, over: 0xFF_9F0A))
    // Brown: 4.64:1 light (3.00:1), 4.61:1 and 6.20:1 dark (4.05:1).
    case .historic:
      (colors(0x7E_6648, on: 0xF1_EDE7), colors(0xB3_997A, over: 0xAC_8E68))
    // Gray: 4.64:1 light (2.81:1), 4.65:1 and 6.29:1 dark (4.26:1). An unknown
    // status, which was the secondary label color, is gray too.
    case .informational, .unknown:
      (colors(0x6A_6A6E, on: 0xEE_EEEF), colors(0x9F_9FA3, over: 0x98_989D))
    }
  }

  /// Text on an opaque fill.
  private static func colors(_ text: UInt32, on fill: UInt32) -> Colors {
    Colors(text: SRGBColor(hex: text), fill: SRGBColor(hex: fill), fillOpacity: 1)
  }

  /// Text on the dark system color `system` at 20%, over whatever is behind it.
  private static func colors(_ text: UInt32, over system: UInt32) -> Colors {
    Colors(text: SRGBColor(hex: text), fill: SRGBColor(hex: system), fillOpacity: 0.2)
  }
}
