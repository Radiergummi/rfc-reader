import Foundation
import Testing

@testable import RFCReaderKit

/// The accent-colored chrome held to the contrast the HIG asks for (#317): the
/// inspector's selected tab, reference chips, the reader's links and the status
/// banner. The accents and system colors are stated as macOS 27 resolves them, in
/// light and in dark; the app resolves the live ones where it draws.
@Suite("Accent contrast")
struct AccentContrastTests {
  /// macOS 27's accents: blue, purple, pink, red, orange, yellow, green, graphite.
  static let lightAccents: [UInt32] = [
    0x00_88FF, 0xCB_30E0, 0xFF_2D55, 0xFF_383C, 0xFF_8D28, 0xFF_CC00, 0x34_C759, 0x8E_8E93,
  ]
  static let darkAccents: [UInt32] = [
    0x00_91FF, 0xDB_34F2, 0xFF_375F, 0xFF_4245, 0xFF_9230, 0xFF_D600, 0x30_D158, 0x98_989D,
  ]
  /// The pages a chip is drawn on: white in light on both platforms, macOS's dark
  /// text background and iOS's black.
  static let lightPages: [UInt32] = [0xFF_FFFF]
  static let darkPages: [UInt32] = [0x1E_1E1E, 0x00_0000]

  /// What else a chip is drawn on: a table's or figure's card (black at 3% in light,
  /// white at 8.5% in dark) and an aside's (4.5%, 12%), over each page.
  static let lightBackdrops =
    lightPages.map(color)
    + lightPages.flatMap { page in
      [0.03, 0.045].map { color(0x00_0000).composited(opacity: $0, over: color(page)) }
    }
  static let darkBackdrops =
    darkPages.map(color)
    + darkPages.flatMap { page in
      [0.085, 0.12].map { color(0xFF_FFFF).composited(opacity: $0, over: color(page)) }
    }

  private static func color(_ hex: UInt32) -> SRGBColor { SRGBColor(hex: hex) }

  // MARK: - Compositing and darkening

  @Test func `a fill at no opacity is the page and at full opacity the fill`() {
    let fill = Self.color(0x00_88FF)
    let page = SRGBColor.white
    #expect(fill.composited(opacity: 0, over: page) == page)
    #expect(fill.composited(opacity: 1, over: page) == fill)
    let half = fill.composited(opacity: 0.5, over: page)
    #expect(abs(half.red - 0.5) < 1e-9)
  }

  @Test func `a color that already contrasts enough is not darkened`() {
    let dark = Self.color(0x00_3366)
    #expect(dark.darkened(toContrast: 4.5, against: .white) == dark)
  }

  /// Darkened by scaling its linear-light channels equally, which keeps the hue,
  /// as the badge palette was made (#516).
  @Test(arguments: lightAccents + darkAccents)
  func `a darkened color clears the contrast and keeps its hue`(hex: UInt32) {
    let accent = Self.color(hex)
    let darkened = accent.darkened(toContrast: 4.5, against: .white)
    #expect(darkened.contrast(with: .white) >= 4.5)
    #expect(darkened.contrast(with: .white) < 4.6, "no darker than it has to be")
    let original = accent.linearChannels
    let scaled = darkened.linearChannels
    let factor = scaled.max()! / original.max()!
    for (before, after) in zip(original, scaled) {
      #expect(abs(before * factor - after) < 1e-6)
    }
  }

  // MARK: - The selected tab

  /// White text stays, as on a macOS selected segment, and the capsule darkens
  /// until it is legible on it.
  @Test(arguments: lightAccents + darkAccents)
  func `white text on the selected tab clears the minimum`(hex: UInt32) {
    let fill = AccentContrast.selectedTabFill(accent: Self.color(hex))
    #expect(fill.contrast(with: .white) >= AccentContrast.minimumContrast)
  }

  // MARK: - Chips

  /// A link on its chip's tint, for every accent on every page the reader draws.
  /// On a page and on a card: the tint is worked out against what the chip is drawn
  /// on. Only where the link itself clears the minimum there; one that does not is a
  /// problem of the link color, not of a chip.
  @Test(arguments: lightAccents)
  func `a link clears the minimum on its chip in light`(hex: UInt32) {
    for backdrop in Self.lightBackdrops {
      Self.expectLegibleChip(hex, link: AccentContrast.readerLink.light, on: backdrop)
    }
  }

  @Test(arguments: darkAccents)
  func `a link clears the minimum on its chip in dark`(hex: UInt32) {
    for backdrop in Self.darkBackdrops {
      Self.expectLegibleChip(hex, link: AccentContrast.readerLink.dark, on: backdrop)
    }
  }

  private static func expectLegibleChip(_ hex: UInt32, link: SRGBColor, on backdrop: SRGBColor) {
    guard link.contrast(with: backdrop) >= AccentContrast.minimumContrast else { return }
    let accent = color(hex)
    let opacity = AccentContrast.chipTintOpacity(accent: accent, link: link, page: backdrop)
    #expect(opacity >= 0 && opacity <= AccentContrast.chipTint)
    // A normative chip, and an informative one at half the tint (#184).
    for drawn in [opacity, opacity / 2] {
      let tint = accent.composited(opacity: drawn, over: backdrop)
      #expect(
        link.contrast(with: tint) >= AccentContrast.minimumContrast,
        "accent \(String(hex, radix: 16)) on \(backdrop) at \(drawn)")
    }
  }

  /// Only an accent that fails gets a lighter tint: orange keeps the 15% it had.
  @Test func `an accent that passes keeps the full tint`() {
    let opacity = AccentContrast.chipTintOpacity(
      accent: Self.color(0xFF_8D28), link: AccentContrast.readerLink.light, page: .white)
    #expect(opacity == AccentContrast.chipTint)
  }

  @Test func `blue, which fails at the full tint, gets a lighter one`() {
    let opacity = AccentContrast.chipTintOpacity(
      accent: Self.color(0x00_88FF), link: AccentContrast.readerLink.light, page: .white)
    #expect(opacity < AccentContrast.chipTint)
    #expect(opacity > 0)
  }

  // MARK: - The reader's links

  @Test func `the reader's link clears the minimum on every page`() {
    for page in Self.lightPages {
      #expect(AccentContrast.readerLink.light.contrast(with: Self.color(page)) >= 4.5)
    }
    for page in Self.darkPages {
      #expect(AccentContrast.readerLink.dark.contrast(with: Self.color(page)) >= 4.5)
    }
  }

  // MARK: - The status banner

  /// The banner's fill is the quaternary label color at half its opacity over the
  /// page: macOS's is black or white at 9.8%, iOS's #3C3C43 or #EBEBF5 at 18%.
  static let lightBannerFills = [
    color(0x00_0000).composited(opacity: 0.049, over: .white),
    color(0x3C_3C43).composited(opacity: 0.09, over: .white),
  ]
  static let darkBannerFills = [
    color(0xFF_FFFF).composited(opacity: 0.049, over: color(0x1E_1E1E)),
    color(0xEB_EBF5).composited(opacity: 0.09, over: color(0x00_0000)),
  ]

  @Test func `the banner's links clear the minimum`() {
    for fill in Self.lightBannerFills {
      #expect(AccentContrast.readerLink.light.contrast(with: fill) >= 4.5)
    }
    for fill in Self.darkBannerFills {
      #expect(AccentContrast.readerLink.dark.contrast(with: fill) >= 4.5)
    }
  }

  /// A symbol is not text, and needs 3:1 (WCAG 1.4.11).
  @Test(arguments: [AccentContrast.BannerSymbol.obsoleted, .updated])
  func `the banner's symbols clear the minimum for a symbol`(symbol: AccentContrast.BannerSymbol) {
    for fill in Self.lightBannerFills {
      #expect(symbol.colors.light.contrast(with: fill) >= AccentContrast.symbolContrast)
    }
    for fill in Self.darkBannerFills {
      #expect(symbol.colors.dark.contrast(with: fill) >= AccentContrast.symbolContrast)
    }
  }
}
