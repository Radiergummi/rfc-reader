import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's own colors under the system's Increase Contrast (#867): the system's
/// colors follow it by themselves, and the cards, strokes, links and syntax colors
/// the reader states take High Contrast's.
@Suite("Increased contrast")
struct IncreasedContrastTests {
  @Test func `each appearance picks its own value`() {
    let variants = AppearanceVariants(
      light: "light", dark: "dark", increasedLight: "increased light",
      increasedDark: "increased dark")
    #expect(variants.value(dark: false, increasedContrast: false) == "light")
    #expect(variants.value(dark: true, increasedContrast: false) == "dark")
    #expect(variants.value(dark: false, increasedContrast: true) == "increased light")
    #expect(variants.value(dark: true, increasedContrast: true) == "increased dark")
  }

  #if !canImport(UIKit)
    /// macOS names the appearance Increase Contrast draws in only through
    /// `bestMatch(from:)`, which `NSAppearance(named:)` cannot make, so the
    /// mapping from what it matched is what is tested.
    @Test func `a high-contrast appearance picks the increased value`() {
      let variants = AppearanceVariants(
        light: "light", dark: "dark", increasedLight: "increased light",
        increasedDark: "increased dark")
      #expect(variants.value(matching: .aqua) == "light")
      #expect(variants.value(matching: .darkAqua) == "dark")
      #expect(variants.value(matching: .accessibilityHighContrastAqua) == "increased light")
      #expect(variants.value(matching: .accessibilityHighContrastDarkAqua) == "increased dark")
      #expect(variants.value(matching: nil) == "light")
    }
  #else
    /// iOS can make the traits Increase Contrast draws in, so the colors themselves
    /// are resolved in them.
    @Test(arguments: [false, true])
    func `the cards resolve to High Contrast's under Increase Contrast`(dark: Bool) {
      let traits = UITraitCollection { traits in
        traits.userInterfaceStyle = dark ? .dark : .light
        traits.accessibilityContrast = .high
      }
      let expected = dark ? PaletteColors.highContrast.dark : PaletteColors.highContrast.light
      var alpha: CGFloat = -1
      _ = RFCColors.cardFill.resolvedColor(with: traits).getRed(
        nil, green: nil, blue: nil, alpha: &alpha)
      #expect(abs(Double(alpha) - expected.cardOpacity) < 0.001)
    }

    /// A page theme's colors are its own: Increase Contrast leaves them.
    @Test(arguments: [false, true])
    func `a theme's colors are the same under Increase Contrast`(dark: Bool) {
      let style: UIUserInterfaceStyle = dark ? .dark : .light
      let standard = UITraitCollection { $0.userInterfaceStyle = style }
      let increased = UITraitCollection { traits in
        traits.userInterfaceStyle = style
        traits.accessibilityContrast = .high
      }
      let color = ReaderPalette.highContrast.link
      #expect(color.resolvedColor(with: standard) == color.resolvedColor(with: increased))
    }
  #endif

  /// The cards are High Contrast's, a stronger tint than at the standard contrast,
  /// so that their edges show; the stroke is its secondary text color.
  @Test func `cards and strokes take High Contrast's colors`() {
    let increased = PaletteColors.highContrast
    for (variants, opacity) in [
      (RFCColors.cardFillVariants, \PaletteColors.cardOpacity),
      (RFCColors.asideFillVariants, \PaletteColors.asideOpacity),
    ] {
      #expect(variants.increasedLight.cgColor.alpha > variants.light.cgColor.alpha)
      #expect(variants.increasedDark.cgColor.alpha > variants.dark.cgColor.alpha)
      #expect(
        abs(variants.increasedLight.cgColor.alpha - increased.light[keyPath: opacity]) < 0.001)
      #expect(abs(variants.increasedDark.cgColor.alpha - increased.dark[keyPath: opacity]) < 0.001)
    }
    #expect(RFCColors.strokeVariants.increasedLight == PlatformColor(increased.light.secondaryText))
    #expect(RFCColors.strokeVariants.increasedDark == PlatformColor(increased.dark.secondaryText))
  }

  /// The pages the reader draws on with no theme chosen: white in light; in dark,
  /// black (iOS), macOS's dark text background, and iOS's elevated background, as
  /// in an iPad's Slide Over, at the standard contrast and under Increase Contrast.
  static let pages: [(dark: Bool, page: SRGBColor)] = [
    (false, .white),
    (true, SRGBColor(red: 0, green: 0, blue: 0)),
    (true, SRGBColor(hex: 0x1E_1E1E)),
    (true, SRGBColor(hex: 0x1C_1C1E)),
    (true, SRGBColor(hex: 0x24_2426)),
  ]

  /// The reader's links clear 7:1 on the page and on both High Contrast cards, as
  /// High Contrast's own do on its page (#704). On a card, the link drawn: the
  /// page's in light, where `cardLink(over:)` keeps it.
  @Test(arguments: pages)
  func `the links clear 7 to 1`(dark: Bool, page: SRGBColor) {
    let increased = dark ? PaletteColors.highContrast.dark : PaletteColors.highContrast.light
    let link =
      dark
      ? AccentContrast.increasedContrastReaderLink.dark
      : AccentContrast.increasedContrastReaderLink.light
    let cardLink = dark ? AccentContrast.increasedContrastDarkCardLink : link
    let pairs: KeyValuePairs<String, (color: SRGBColor, background: SRGBColor)> = [
      "a link on the page": (link, page),
      "a link on a card": (cardLink, Self.card(increased.cardOpacity, of: increased, over: page)),
      "a link in an aside": (
        cardLink, Self.card(increased.asideOpacity, of: increased, over: page)
      ),
    ]
    for (role, pair) in pairs {
      let ratio = pair.color.contrast(with: pair.background)
      #expect(ratio >= 7, "\(role) is \(ratio):1 on \(page)")
    }
  }

  /// Every syntax color clears 7:1 on High Contrast's card, as the #704 comment
  /// asked of the pair, where at the standard contrast it clears 4.5:1 on the
  /// standard card (`SyntaxThemeTests`).
  @Test(arguments: pages)
  func `every syntax color clears 7 to 1 on the card`(dark: Bool, page: SRGBColor) {
    let increased = dark ? PaletteColors.highContrast.dark : PaletteColors.highContrast.light
    let card = Self.card(increased.cardOpacity, of: increased, over: page)
    for (kind, variants) in SyntaxTheme.standardColors {
      let color = variants.value(dark: dark, increasedContrast: true)
      let ratio = color.contrast(with: card)
      #expect(ratio >= 7, "\(kind) is \(ratio):1 on \(card)")
    }
  }

  private static func card(_ opacity: Double, of colors: PaletteColors, over page: SRGBColor)
    -> SRGBColor
  {
    colors.cardTint.composited(opacity: opacity, over: page)
  }
}
