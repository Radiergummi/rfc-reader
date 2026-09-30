import RFCKit

/// The status badges' colors: a text color on an opaque fill, for each status, in
/// light and dark appearance (#317).
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
/// - **Dark:** the fill is the dark system color at 20% over the dark window
///   background, `#1C1C1E`; the text is the same color lightened toward white until
///   it clears it. Standards and Experimental passed as they were.
///
/// The fill is opaque, so a badge reads the same on a selected row as on a plain one.
public enum StatusPalette {
  /// What text at standard sizes needs, per Apple's Human Interface Guidelines, as
  /// the monograms are held to.
  public static let minimumContrast = AuthorMonogram.minimumContrast

  public enum Appearance: CaseIterable, Sendable {
    case light, dark
  }

  public struct Colors: Hashable, Sendable {
    public let text: SRGBColor
    public let fill: SRGBColor
  }

  public static func colors(for status: PublicationStatus, in appearance: Appearance) -> Colors {
    let (light, dark) = pair(for: status)
    return appearance == .light ? light : dark
  }

  private static func pair(for status: PublicationStatus) -> (light: Colors, dark: Colors) {
    switch status {
    // Green: 4.62:1 light (the system color's 1.97:1), 5.68:1 dark (unchanged).
    case .internetStandard, .draftStandard:
      (colors(0x1D_7D35, on: 0xE1_F7E6), colors(0x30_D158, on: 0x20_402A))
    // Blue: 4.65:1 light (3.30:1), 4.62:1 dark (3.64:1).
    case .proposedStandard:
      (colors(0x00_63D2, on: 0xD9_EBFF), colors(0x5A_97FF, on: 0x18_314B))
    // Purple: 4.66:1 light (3.42:1), 4.63:1 dark (3.74:1).
    case .bestCurrentPractice:
      (colors(0x92_43BA, on: 0xF3_E5FA), colors(0xC6_78F3, on: 0x3D_2848))
    // Orange: 4.66:1 light (1.95:1), 5.59:1 dark (unchanged).
    case .experimental:
      (colors(0xA0_5B00, on: 0xFF_EFD9), colors(0xFF_9F0A, on: 0x49_361A))
    // Brown: 4.64:1 light (3.00:1), 4.60:1 dark (4.05:1).
    case .historic:
      (colors(0x7E_6648, on: 0xF1_EDE7), colors(0xB3_997A, on: 0x39_332D))
    // Gray: 4.64:1 light (2.81:1), 4.64:1 dark (4.26:1). An unknown status, which
    // was the secondary label color, is gray too.
    case .informational, .unknown:
      (colors(0x6A_6A6E, on: 0xEE_EEEF), colors(0x9F_9FA3, on: 0x35_3537))
    }
  }

  private static func colors(_ text: UInt32, on fill: UInt32) -> Colors {
    Colors(text: SRGBColor(hex: text), fill: SRGBColor(hex: fill))
  }
}
