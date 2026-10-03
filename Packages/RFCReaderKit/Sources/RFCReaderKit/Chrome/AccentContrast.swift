import Foundation

/// The colors of the accent-colored chrome, held to the contrast the HIG asks for
/// (#317), as the status badges are by `StatusPalette`.
///
/// The accent is the user's and resolves differently by appearance, platform and OS
/// release, so what depends on it is a rule the app applies to the accent it
/// resolves where it draws: the selected tab's capsule darkens, and a chip's tint
/// lightens. What does not depend on it is stated: the reader's link color and the
/// status banner's symbols.
public enum AccentContrast {
  /// What text at standard sizes needs, as the monograms and badges are held to.
  public static let minimumContrast = AuthorMonogram.minimumContrast
  /// What a symbol needs: it is not text (WCAG 1.4.11).
  public static let symbolContrast = 3.0
  /// A reference chip's tint where the link on it stays legible.
  public static let chipTint = 0.15

  /// The inspector's selected tab: white text, as on a macOS selected segment, on
  /// the accent darkened until the text clears the minimum. macOS 27's default blue
  /// carries white at 3.52:1 and yellow at 1.51:1.
  public static func selectedTabFill(accent: SRGBColor) -> SRGBColor {
    accent.darkened(toContrast: minimumContrast, against: .white)
  }

  /// The opacity of a chip's accent tint over `page`: ``chipTint`` where the link
  /// stays legible on it, and otherwise the largest, in steps of half a percent,
  /// that keeps it so. The link stays the link color. In light, macOS 27's blue,
  /// purple, pink and red need less than 15%; in dark, yellow and green do.
  public static func chipTintOpacity(accent: SRGBColor, link: SRGBColor, page: SRGBColor)
    -> Double
  {
    var opacity = chipTint
    while opacity > 0,
      link.contrast(with: accent.composited(opacity: opacity, over: page)) < minimumContrast
    {
      opacity -= 0.005
    }
    return max(0, opacity)
  }

  /// The reader's link color: macOS's own link color, stated so that iOS's reader
  /// uses it too. iOS colored links with the system tint, `#0088FF`, which is 3.52:1
  /// on a white page.
  public static let readerLink = (light: SRGBColor(hex: 0x00_68DA), dark: SRGBColor(hex: 0x41_9CFF))

  /// The status banner's row symbols, stated as `StatusPalette`'s colors are.
  public enum BannerSymbol: Sendable, CaseIterable {
    /// Red: the system red, which already clears 3:1 on the banner.
    case obsoleted
    /// Orange: the system orange is 1.98:1 on the banner in light, so it is
    /// darkened there until it clears 3:1; the dark one is 6.51:1 as it is.
    case updated

    public var colors: (light: SRGBColor, dark: SRGBColor) {
      switch self {
      case .obsoleted: (SRGBColor(hex: 0xFF_383C), SRGBColor(hex: 0xFF_4245))
      case .updated: (SRGBColor(hex: 0xCE_711E), SRGBColor(hex: 0xFF_9230))
      }
    }
  }
}
