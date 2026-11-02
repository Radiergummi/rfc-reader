import CoreText

#if canImport(UIKit)
  import UIKit

  public typealias PlatformFont = UIFont
  public typealias PlatformColor = UIColor
  public typealias PlatformFontDescriptor = UIFontDescriptor
  public typealias PlatformImage = UIImage
#else
  import AppKit

  public typealias PlatformFont = NSFont
  public typealias PlatformColor = NSColor
  public typealias PlatformFontDescriptor = NSFontDescriptor
  public typealias PlatformImage = NSImage

  extension NSImage {
    /// Mirrors `UIImage(systemName:)` so the builder can ask for an SF Symbol
    /// without branching on platform.
    convenience init?(systemName: String) {
      self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }
  }
#endif

/// Dynamic colors, stored in the attributed string unresolved so that a change of
/// appearance or accent costs a redraw rather than a rebuild of the whole document.
public enum RFCColors {
  public static var label: PlatformColor {
    #if canImport(UIKit)
      .label
    #else
      .labelColor
    #endif
  }

  public static var secondaryLabel: PlatformColor {
    #if canImport(UIKit)
      .secondaryLabel
    #else
      .secondaryLabelColor
    #endif
  }

  public static var accent: PlatformColor {
    #if canImport(UIKit)
      .tintColor
    #else
      .controlAccentColor
    #endif
  }

  /// A link, where no text view colors it: an exported PDF's (#376).
  public static var link: PlatformColor {
    #if canImport(UIKit)
      .link
    #else
      .linkColor
    #endif
  }

  /// The reader's links and the status banner's (#317): `AccentContrast.readerLink`,
  /// which on macOS is the system's own link color and on iOS replaces the system
  /// tint, 3.52:1 on a white page; under Increase Contrast,
  /// `AccentContrast.increasedContrastReaderLink` (#867).
  public static var readerLink: PlatformColor {
    let standard = AccentContrast.readerLink
    let increased = AccentContrast.increasedContrastReaderLink
    return dynamic(
      AppearanceVariants(
        light: standard.light, dark: standard.dark,
        increasedLight: increased.light, increasedDark: increased.dark
      ).map(PlatformColor.init))
  }

  /// What a redline marks inserted (#729): `AccentContrast.inserted`.
  public static var inserted: PlatformColor {
    byAppearance(light: AccentContrast.inserted.light, dark: AccentContrast.inserted.dark)
  }

  /// A link on a card, where `link` is the link color on the page: in dark,
  /// `AccentContrast.cardLink`, lighter than the reader's link (#694), or under
  /// Increase Contrast `AccentContrast.increasedContrastCardLink` (#867); in light,
  /// `link` itself, which clears the cards as it does the page, so that a card's
  /// links and the page's stay one color whatever the system makes of it.
  public static func cardLink(over link: PlatformColor) -> PlatformColor {
    dynamic(
      AppearanceVariants(
        light: link, dark: PlatformColor(AccentContrast.cardLink.dark),
        increasedLight: link,
        increasedDark: PlatformColor(AccentContrast.increasedContrastCardLink.dark)))
  }

  /// The page the reader's text is drawn on, which a chip's tint is drawn over.
  public static var page: PlatformColor {
    #if canImport(UIKit)
      .systemBackground
    #else
      .textBackgroundColor
    #endif
  }

  /// The card behind artwork and tables: a faint tint of the page, the way Apple's
  /// documentation sets a code listing. DocC darkens a white page to 247 and lifts a
  /// black one to 22, about 3% towards black and 9% towards white. A system fill
  /// forced to a fixed opacity read far darker than that in light and far lighter
  /// in dark. Under Increase Contrast, High Contrast's card (#867).
  public static var cardFill: PlatformColor { dynamic(cardFillVariants) }

  static let cardFillVariants = pageTint(light: 0.03, dark: 0.085) { $0.cardOpacity }

  /// An aside's card, a step stronger than a figure's.
  public static var asideFill: PlatformColor { dynamic(asideFillVariants) }

  static let asideFillVariants = pageTint(light: 0.045, dark: 0.12) { $0.asideOpacity }

  /// Implementer's band behind a requirement (#700): `RequirementBands.tint`,
  /// translucent, so it tints the page or a card under it.
  public static var requirementBand: PlatformColor {
    let tint = RequirementBands.tint
    return byAppearance(
      light: tint.light.color, dark: tint.dark.color,
      opacity: (light: tint.light.opacity, dark: tint.dark.opacity))
  }

  /// A highlight's fill, or its underline's rule (#522): `HighlightColor.fill`.
  public static func highlight(_ color: HighlightColor) -> PlatformColor {
    let fill = color.fill
    return byAppearance(
      light: fill.light.color, dark: fill.dark.color,
      opacity: (light: fill.light.opacity, dark: fill.dark.opacity))
  }

  /// Black at `light` on a light page, white at `dark` on a dark one, and High
  /// Contrast's card tint at its `increased` opacity under Increase Contrast.
  /// Translucent, so it tints whatever the page is rather than assuming its color.
  private static func pageTint(
    light: CGFloat, dark: CGFloat, increased opacity: (PaletteColors) -> Double
  ) -> AppearanceVariants<PlatformColor> {
    let increased = PaletteColors.highContrast
    return AppearanceVariants(
      light: PlatformColor(white: 0, alpha: light),
      dark: PlatformColor(white: 1, alpha: dark),
      increasedLight: PlatformColor(increased.light.cardTint)
        .withAlphaComponent(opacity(increased.light)),
      increasedDark: PlatformColor(increased.dark.cardTint)
        .withAlphaComponent(opacity(increased.dark)))
  }

  /// `variants`' color for the appearance it is drawn in, resolved when it is
  /// drawn: light or dark, and whether the system's Increase Contrast is on (#867),
  /// which the system's colors follow by themselves and the reader's own through
  /// this.
  static func dynamic(_ variants: AppearanceVariants<PlatformColor>) -> PlatformColor {
    #if canImport(UIKit)
      UIColor { traits in
        variants.value(
          dark: traits.userInterfaceStyle == .dark,
          increasedContrast: traits.accessibilityContrast == .high
        ).resolvedColor(with: traits)
      }
    #else
      NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: AppearanceVariants<PlatformColor>.names)
        return variants.value(matching: match)
      }
    #endif
  }

  /// `light` in light appearance and `dark` in dark, drawn as exactly those sRGB
  /// values, at `opacity` in each, and resolved when drawn: for colors whose
  /// contrast is measured.
  public static func byAppearance(
    light: SRGBColor, dark: SRGBColor, opacity: (light: CGFloat, dark: CGFloat) = (1, 1)
  ) -> PlatformColor {
    #if canImport(UIKit)
      UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        let color = isDark ? dark : light
        return UIColor(
          red: color.red, green: color.green, blue: color.blue,
          alpha: isDark ? opacity.dark : opacity.light)
      }
    #else
      NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = isDark ? dark : light
        return NSColor(
          srgbRed: color.red, green: color.green, blue: color.blue,
          alpha: isDark ? opacity.dark : opacity.light)
      }
    #endif
  }

  /// The rule beside a quote or aside: a line, not a fill. macOS's
  /// `quaternarySystemFill` is about a quarter as opaque as the `quaternaryLabelColor`
  /// the rule used to draw in, which left a rule this thin close to invisible;
  /// `separatorColor` is the line color, at about the old opacity. iOS's
  /// `quaternarySystemFill` is darker, and the rule keeps it.
  public static var rule: PlatformColor {
    #if canImport(UIKit)
      .quaternarySystemFill
    #else
      .separatorColor
    #endif
  }

  /// The lines a decorated block draws over its text: a step back from the label
  /// color, so a grid reads as structure and its field names as the content. Opaque,
  /// where the secondary label color is not: a stroke is drawn in pieces, one per
  /// line's fragment, and translucent pieces meeting on a fractional pixel draw a
  /// lighter band at every line, #31's seam again, and a darker patch wherever a
  /// rule and a delimiter overlap at a corner. Under Increase Contrast, High
  /// Contrast's, its secondary text color (#867).
  public static let stroke = dynamic(strokeVariants)

  static let strokeVariants = AppearanceVariants(
    light: PlatformColor(white: 0.45, alpha: 1), dark: PlatformColor(white: 0.6, alpha: 1),
    increasedLight: PlatformColor(PaletteColors.highContrast.light.secondaryText),
    increasedDark: PlatformColor(PaletteColors.highContrast.dark.secondaryText))

}

/// A value for each appearance the reader's own colors are drawn in: light or dark,
/// each at the standard contrast or under the system's Increase Contrast (#867).
struct AppearanceVariants<Value: Sendable>: Sendable {
  var light: Value
  var dark: Value
  var increasedLight: Value
  var increasedDark: Value

  /// The value for a dark appearance or a light one, under Increase Contrast or not.
  func value(dark: Bool, increasedContrast: Bool) -> Value {
    switch (dark, increasedContrast) {
    case (false, false): light
    case (true, false): self.dark
    case (false, true): increasedLight
    case (true, true): increasedDark
    }
  }

  func map<Other: Sendable>(_ transform: (Value) -> Other) -> AppearanceVariants<Other> {
    AppearanceVariants<Other>(
      light: transform(light), dark: transform(dark),
      increasedLight: transform(increasedLight), increasedDark: transform(increasedDark))
  }

  #if !canImport(UIKit)
    /// What an appearance is matched against. macOS draws in a high-contrast
    /// variant of the light or dark appearance under Increase Contrast, which only
    /// `bestMatch(from:)` tells apart: `NSAppearance(named:)` makes none of them.
    static var names: [NSAppearance.Name] {
      [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
    }

    /// The value for the appearance `bestMatch(from: names)` matched: light where it
    /// matched none, as the reader's colors always took it.
    func value(matching name: NSAppearance.Name?) -> Value {
      value(
        dark: name == .darkAqua || name == .accessibilityHighContrastDarkAqua,
        increasedContrast: name == .accessibilityHighContrastAqua
          || name == .accessibilityHighContrastDarkAqua)
    }
  #endif
}

/// Symbolic traits, which AppKit and UIKit spell differently.
public enum RFCTraits {
  public static var italic: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitItalic
    #else
      .italic
    #endif
  }

  public static var bold: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitBold
    #else
      .bold
    #endif
  }

  /// For the tests, which check that code runs are set monospaced.
  static var monospace: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitMonoSpace
    #else
      .monoSpace
    #endif
  }
}

extension PlatformImage {
  /// An SF Symbol rendered at `pointSize`. AppKit and UIKit spell the
  /// configuration step differently (`withSymbolConfiguration` against
  /// `withConfiguration`); that difference belongs here rather than in the builder.
  static func symbol(named name: String, pointSize: CGFloat) -> PlatformImage? {
    let configuration = SymbolConfiguration(pointSize: pointSize, weight: .regular)
    #if canImport(UIKit)
      return PlatformImage(systemName: name)?.withConfiguration(configuration)
    #else
      return PlatformImage(systemName: name)?.withSymbolConfiguration(configuration)
    #endif
  }
}

extension PlatformFont {
  /// This font with `traits` added, or this font unchanged when it has them already
  /// or cannot have them.
  ///
  /// A copy of the font, made by Core Text, rather than a font resolved again from a
  /// descriptor. A strong run in bold text adds nothing, and is this font.
  func adding(traits: PlatformFontDescriptor.SymbolicTraits) -> PlatformFont {
    let added = traits.subtracting(fontDescriptor.symbolicTraits)
    guard !added.isEmpty else { return self }
    let value = CTFontSymbolicTraits(rawValue: added.rawValue)
    guard let copy = CTFontCreateCopyWithSymbolicTraits(self as CTFont, 0, nil, value, value)
    else { return self }
    return copy as PlatformFont
  }

  /// The font's weight as its descriptor states it. This is what lets a run inside
  /// a semibold heading keep its weight. A face that states no weight at all is
  /// bold if it carries the bold trait and regular otherwise. The trait alone is
  /// not the weight: a semibold face carries it too, and reading that as bold set
  /// inline code in a heading heavier than the heading around it (#153).
  var weight: PlatformFont.Weight {
    let traits = fontDescriptor.object(forKey: .traits) as? [PlatformFontDescriptor.TraitKey: Any]
    if let stated = traits?[.weight] as? CGFloat, stated != 0 {
      return PlatformFont.Weight(rawValue: stated)
    }
    return fontDescriptor.symbolicTraits.contains(RFCTraits.bold) ? .bold : .regular
  }

  /// This font's face and traits at another size: a Core Text copy, for the reason
  /// `adding(traits:)` is one.
  func resized(to size: CGFloat) -> PlatformFont {
    CTFontCreateCopyWithAttributes(self as CTFont, size, nil, nil) as PlatformFont
  }
}

extension SRGBColor {
  /// A platform color as the current appearance resolves it, for a rule that
  /// depends on a color the user picks, such as the accent (#317): on macOS the
  /// drawing appearance, on iOS the current trait collection. Its alpha is dropped.
  public init?(resolving color: PlatformColor) {
    guard let resolved = Self.resolvingWithOpacity(color) else { return nil }
    self = resolved.color
  }

  /// A platform color as the current appearance resolves it, with its opacity: a
  /// translucent fill, such as a card's, to composite over what it is drawn on.
  public static func resolvingWithOpacity(_ color: PlatformColor)
    -> (color: SRGBColor, opacity: Double)?
  {
    #if canImport(UIKit)
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      guard
        color.resolvedColor(with: .current).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      else { return nil }
      return (SRGBColor(red: Double(red), green: Double(green), blue: Double(blue)), Double(alpha))
    #else
      guard let resolved = color.usingColorSpace(.sRGB) else { return nil }
      return (
        SRGBColor(
          red: Double(resolved.redComponent), green: Double(resolved.greenComponent),
          blue: Double(resolved.blueComponent)),
        Double(resolved.alphaComponent)
      )
    #endif
  }
}

extension PlatformColor {
  /// A color RFCReaderKit has measured, as exactly those sRGB values.
  public convenience init(_ color: SRGBColor) {
    #if canImport(UIKit)
      self.init(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    #else
      self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    #endif
  }
}
