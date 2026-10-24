import Synchronization

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The draw-time half of the reader's settings, where `ReadingStyle` is the
/// build-time half: the colors the reader draws rather than stores in the text.
///
/// A change here redraws and never rebuilds, so it never costs the reader's place.
/// `RFCTextLayoutFragment` draws cards, rules, strokes and chips from it, through a
/// `ReaderPaletteBox` each layout manager of built text is given; the text views
/// draw the page behind the text in it, and its links through `LinkRendering`. The
/// text itself is stored in `themedText` and `themedSecondaryText`, dynamic colors
/// that resolve to the theme chosen as they are drawn. See
/// `docs/decisions/2026-10-03-reader-settings-are-a-build-time-style-and-a-draw-time-palette.md`.
///
/// A page theme (#704) belongs to one appearance, or to both: the light theme a
/// reader picks is drawn while the app is light, the dark one while it is dark.
/// Every color of a palette that has both appearances is dynamic, resolved by
/// appearance when drawn, as `RFCColors`' are: dark mode is a redraw, and print's
/// forced light appearance needs no palette of its own.
///
/// Equal by `id` alone, for the reason `SyntaxTheme` is: dynamic colors compare by
/// identity.
public struct ReaderPalette: Sendable, Hashable, Identifiable {
  /// What user defaults hold for it (`ReaderPreferences.lightPaletteKey`,
  /// `darkPaletteKey`): renaming one resets everyone who chose it to automatic.
  public let id: String
  /// The appearances it is offered in: the light theme is one that has `.light`,
  /// the dark theme one that has `.dark`.
  public let appearances: Set<PaletteAppearance>
  /// Whether it draws the system's own colors: the automatic palette, under which
  /// a text view keeps its own link and selection colors and draws no page, so
  /// that the default draws exactly as the reader always has.
  public let drawsSystemColors: Bool
  /// Behind the text, or nil to draw none and let the window's background show, as
  /// the automatic palette does.
  public var pageBackground: PlatformColor?
  /// Body text, which `themedText` resolves to.
  public var text: PlatformColor
  /// Quieter text, which `themedSecondaryText` resolves to: list markers, section
  /// numbers, captions, the abstract.
  public var secondaryText: PlatformColor
  /// A link on the page.
  public var link: PlatformColor
  /// A link on a card, which may need to be lighter than one on the page (#694).
  public var cardLink: PlatformColor
  /// The selection's highlight, or nil for the system's.
  public var selection: PlatformColor?
  /// The card behind artwork, source code and tables.
  public var cardFill: PlatformColor
  /// An aside's card.
  public var asideFill: PlatformColor
  /// The line beside a block quote.
  public var rule: PlatformColor
  /// The lines a decorated block draws over its text, such as a packet diagram's.
  public var stroke: PlatformColor
  /// What a reference chip is tinted with, at `AccentContrast.chipTintOpacity`
  /// (#317), and outlined with, at `AccentContrast.chipOutline` (#457).
  public var chipTint: PlatformColor
  /// The colors it states for each appearance it has, as the sRGB values its
  /// contrast is measured on; empty for the automatic palette, whose colors are the
  /// system's.
  public let stated: [PaletteAppearance: PaletteColors]

  public init(
    id: String, appearances: Set<PaletteAppearance> = [.light, .dark],
    drawsSystemColors: Bool = false, pageBackground: PlatformColor? = nil,
    text: PlatformColor = RFCColors.label, secondaryText: PlatformColor = RFCColors.secondaryLabel,
    link: PlatformColor = RFCColors.readerLink,
    cardLink: PlatformColor = RFCColors.cardLink(over: RFCColors.readerLink),
    selection: PlatformColor? = nil, cardFill: PlatformColor, asideFill: PlatformColor,
    rule: PlatformColor, stroke: PlatformColor, chipTint: PlatformColor,
    stated: [PaletteAppearance: PaletteColors] = [:]
  ) {
    self.id = id
    self.appearances = appearances
    self.drawsSystemColors = drawsSystemColors
    self.pageBackground = pageBackground
    self.text = text
    self.secondaryText = secondaryText
    self.link = link
    self.cardLink = cardLink
    self.selection = selection
    self.cardFill = cardFill
    self.asideFill = asideFill
    self.rule = rule
    self.stroke = stroke
    self.chipTint = chipTint
    self.stated = stated
  }

  /// A page theme from the colors it states for each appearance it has: dynamic
  /// where it has both, and fixed where it has one, since it is only drawn in that
  /// one. The chip keeps the system's accent, which is the reader's own choice.
  init(id: String, light: PaletteColors?, dark: PaletteColors?) {
    var stated: [PaletteAppearance: PaletteColors] = [:]
    stated[.light] = light
    stated[.dark] = dark
    // One role's color in each appearance the palette has.
    func color(
      _ role: (PaletteColors) -> SRGBColor, opacity: (PaletteColors) -> Double = { _ in 1 }
    ) -> PlatformColor {
      switch (light, dark) {
      case (let light?, let dark?):
        RFCColors.byAppearance(
          light: role(light), dark: role(dark), opacity: (opacity(light), opacity(dark)))
      case (let only?, nil), (nil, let only?):
        PlatformColor(role(only)).withAlphaComponent(opacity(only))
      case (nil, nil):
        preconditionFailure("a page theme states its colors for at least one appearance")
      }
    }
    let hasSelection = stated.values.allSatisfy { $0.selection != nil }
    self.init(
      id: id,
      appearances: Set(stated.keys),
      pageBackground: color(\.page),
      text: color(\.text),
      secondaryText: color(\.secondaryText),
      link: color(\.link),
      cardLink: color(\.cardLink),
      selection: hasSelection ? color { $0.selection ?? $0.page } : nil,
      cardFill: color(\.cardTint, opacity: \.cardOpacity),
      asideFill: color(\.cardTint, opacity: \.asideOpacity),
      rule: color(\.secondaryText) { _ in PaletteColors.ruleOpacity },
      stroke: color(\.secondaryText),
      chipTint: RFCColors.accent,
      stated: stated
    )
  }

  public static func == (lhs: ReaderPalette, rhs: ReaderPalette) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }

  /// The system's colors, and what a print draws with: its light appearance
  /// resolves them to a white page's. Exactly what the reader drew before there
  /// were page themes: no page background, and the text and links as stored.
  public static let automatic = ReaderPalette(
    id: "automatic",
    drawsSystemColors: true,
    cardFill: RFCColors.cardFill,
    asideFill: RFCColors.asideFill,
    rule: RFCColors.rule,
    stroke: RFCColors.stroke,
    chipTint: RFCColors.accent
  )

  /// A white page with near-black text, whatever the system's colors are.
  public static let paper = ReaderPalette(
    id: "paper",
    light: PaletteColors(
      page: SRGBColor(hex: 0xFF_FFFF), text: SRGBColor(hex: 0x1D_1D1F),
      secondaryText: SRGBColor(hex: 0x6E_6E73), link: SRGBColor(hex: 0x00_66CC),
      cardTint: SRGBColor(hex: 0x00_0000), cardOpacity: 0.03, asideOpacity: 0.045),
    dark: nil)

  /// A warm page with less glare, as Apple Books' sepia: brown text, and a muted
  /// blue for the links.
  public static let sepia = ReaderPalette(
    id: "sepia",
    light: PaletteColors(
      page: SRGBColor(hex: 0xF8_F1E3), text: SRGBColor(hex: 0x3B_2F23),
      secondaryText: SRGBColor(hex: 0x6B_5A47), link: SRGBColor(hex: 0x28_56A8),
      cardTint: SRGBColor(hex: 0x5C_4320), cardOpacity: 0.05, asideOpacity: 0.075,
      selection: SRGBColor(hex: 0xE8_D3A6)),
    dark: nil)

  /// A soft light gray page: less glare than white, without sepia's warmth.
  public static let gray = ReaderPalette(
    id: "gray",
    light: PaletteColors(
      page: SRGBColor(hex: 0xE9_E9E7), text: SRGBColor(hex: 0x1F_1F1F),
      secondaryText: SRGBColor(hex: 0x55_5553), link: SRGBColor(hex: 0x1E_57A8),
      cardTint: SRGBColor(hex: 0x00_0000), cardOpacity: 0.04, asideOpacity: 0.06,
      selection: SRGBColor(hex: 0xC4_CEDB)),
    dark: nil)

  /// A dark gray page with off-white text: dark mode with the glare taken out.
  public static let night = ReaderPalette(
    id: "night",
    light: nil,
    dark: PaletteColors(
      page: SRGBColor(hex: 0x1E_1E20), text: SRGBColor(hex: 0xE3_E3E6),
      secondaryText: SRGBColor(hex: 0xA0_A0A6), link: SRGBColor(hex: 0x5A_A6FF),
      cardLink: SRGBColor(hex: 0x7A_B8FF),
      cardTint: SRGBColor(hex: 0xFF_FFFF), cardOpacity: 0.07, asideOpacity: 0.10))

  /// A true black page, for OLED screens, with light gray text rather than white,
  /// which glares on black.
  public static let black = ReaderPalette(
    id: "black",
    light: nil,
    dark: PaletteColors(
      page: SRGBColor(hex: 0x00_0000), text: SRGBColor(hex: 0xD6_D6D6),
      secondaryText: SRGBColor(hex: 0x96_9696), link: SRGBColor(hex: 0x4D_9DFF),
      cardLink: SRGBColor(hex: 0x6F_B0FF),
      cardTint: SRGBColor(hex: 0xFF_FFFF), cardOpacity: 0.085, asideOpacity: 0.12))

  /// Black on white or white on black, by the appearance, every text role at 7:1
  /// or more on the page and on the cards.
  public static let highContrast = ReaderPalette(
    id: "high-contrast",
    light: PaletteColors(
      page: SRGBColor(hex: 0xFF_FFFF), text: SRGBColor(hex: 0x00_0000),
      secondaryText: SRGBColor(hex: 0x33_3333), link: SRGBColor(hex: 0x00_40A8),
      cardTint: SRGBColor(hex: 0x00_0000), cardOpacity: 0.05, asideOpacity: 0.07),
    dark: PaletteColors(
      page: SRGBColor(hex: 0x00_0000), text: SRGBColor(hex: 0xFF_FFFF),
      secondaryText: SRGBColor(hex: 0xD0_D0D0), link: SRGBColor(hex: 0x80_BDFF),
      cardTint: SRGBColor(hex: 0xFF_FFFF), cardOpacity: 0.10, asideOpacity: 0.14))

  /// Every palette the reader offers, the automatic one first.
  public static let all: [ReaderPalette] = [
    .automatic, .paper, .sepia, .gray, .night, .black, .highContrast,
  ]

  /// The palettes offered in `appearance`, in the order Settings lists them.
  public static func offered(in appearance: PaletteAppearance) -> [ReaderPalette] {
    all.filter { $0.appearances.contains(appearance) }
  }

  /// The palette called `id` among those offered in `appearance`, or the automatic
  /// one where there is none: a name stored by a later version or removed since,
  /// or a theme of the other appearance.
  public static func named(_ id: String?, in appearance: PaletteAppearance) -> ReaderPalette {
    offered(in: appearance).first { $0.id == id } ?? .automatic
  }

  // MARK: - Text

  /// The light and the dark theme chosen, process-wide, which `text` and
  /// `secondaryText` below draw in. A setting, as the themes are: every reader
  /// draws the same ones (`follow()`).
  private static let chosen = Mutex((light: ReaderPalette.automatic, dark: ReaderPalette.automatic))

  /// The theme chosen for `appearance`.
  public static func chosen(for appearance: PaletteAppearance) -> ReaderPalette {
    chosen.withLock { appearance == .dark ? $0.dark : $0.light }
  }

  /// Makes `light` and `dark` the themes the text is drawn in, from the next
  /// redraw, and says whether either changed.
  @discardableResult
  public static func choose(light: ReaderPalette, dark: ReaderPalette) -> Bool {
    chosen.withLock { chosen in
      guard chosen.light != light || chosen.dark != dark else { return false }
      chosen = (light, dark)
      return true
    }
  }

  /// Keeps the chosen themes to what the standard user defaults hold from now on,
  /// as each change is written, before any view is told of it: so a reader that
  /// redraws for a new theme draws its text in it.
  public static func follow() {
    chooseFromDefaults()
    // No queue: on the thread that wrote, as the write happens.
    NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil
    ) { _ in
      chooseFromDefaults()
    }
  }

  private static func chooseFromDefaults() {
    let settings = ReaderSettings(defaults: .standard)
    choose(light: settings.lightPalette, dark: settings.darkPalette)
  }

  /// Body text, as the theme chosen for the appearance it is drawn in has it: what
  /// the builder stores for the reader's text rather than `RFCColors.label` (#704).
  /// Dynamic, resolved as it is drawn, so a theme switch is a redraw, as a switch
  /// to dark mode is; under the automatic theme, the system's label color.
  public static let themedText = themed(\.text) { chosen(for: $0) }
  /// Quieter text, as `themedText` is body text: list markers, section numbers,
  /// captions, the abstract.
  public static let themedSecondaryText = themed(\.secondaryText) { chosen(for: $0) }

  /// `role` of the theme `chosen` gives for the appearance it is resolved in.
  static func themed(
    _ role: @escaping @Sendable (ReaderPalette) -> PlatformColor,
    from chosen: @escaping @Sendable (PaletteAppearance) -> ReaderPalette
  ) -> PlatformColor {
    #if canImport(UIKit)
      UIColor { traits in
        let palette = chosen(traits.userInterfaceStyle == .dark ? .dark : .light)
        return role(palette).resolvedColor(with: traits)
      }
    #else
      NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return role(chosen(isDark ? .dark : .light))
      }
    #endif
  }
}

/// An appearance a page theme is drawn in.
public enum PaletteAppearance: String, Sendable, Hashable, CaseIterable {
  case light
  case dark
}

/// A page theme's colors in one appearance, as the sRGB values it draws and its
/// contrast is measured on: every text role at 4.5:1 or more against the page and
/// both cards (`ReaderPaletteTests`, #694).
public struct PaletteColors: Sendable, Hashable {
  public var page: SRGBColor
  public var text: SRGBColor
  public var secondaryText: SRGBColor
  public var link: SRGBColor
  /// A link on a card: the page's link where it clears the cards as it does the page.
  public var cardLink: SRGBColor
  /// What a card tints the page with, at `cardOpacity`, and an aside's at
  /// `asideOpacity`: translucent, as `RFCColors.cardFill` is, so that it tints
  /// whatever it is drawn over.
  public var cardTint: SRGBColor
  public var cardOpacity: Double
  public var asideOpacity: Double
  /// The selection's highlight, or nil for the system's.
  public var selection: SRGBColor?

  /// How strongly the rule beside a quote draws the secondary text's color.
  static let ruleOpacity = 0.35

  public init(
    page: SRGBColor, text: SRGBColor, secondaryText: SRGBColor, link: SRGBColor,
    cardLink: SRGBColor? = nil, cardTint: SRGBColor, cardOpacity: Double,
    asideOpacity: Double, selection: SRGBColor? = nil
  ) {
    self.page = page
    self.text = text
    self.secondaryText = secondaryText
    self.link = link
    self.cardLink = cardLink ?? link
    self.cardTint = cardTint
    self.cardOpacity = cardOpacity
    self.asideOpacity = asideOpacity
    self.selection = selection
  }

  /// A figure's or a table's card, as it looks over the page.
  public var card: SRGBColor { cardTint.composited(opacity: cardOpacity, over: page) }
  /// An aside's card, as it looks over the page.
  public var aside: SRGBColor { cardTint.composited(opacity: asideOpacity, over: page) }
}

/// The palette a layout manager's fragments draw with, read on whatever thread
/// TextKit draws on and replaced on the main actor when the setting changes.
///
/// A box rather than a value handed to each fragment, because fragments outlive a
/// change of palette: TextKit keeps the ones it laid out, and a theme switch must
/// recolor them without laying anything out again. Whoever replaces the palette
/// asks the text view to redraw.
///
/// Beside the palette, whether the system asks for more contrast (#457): drawn the
/// same way, and no part of a palette a reader chooses.
public final class ReaderPaletteBox: Sendable {
  private struct Drawing: Equatable {
    var palette: ReaderPalette
    var outlinesEveryChip: Bool
  }

  private let value: Mutex<Drawing>

  public init(_ palette: ReaderPalette = .automatic) {
    value = Mutex(Drawing(palette: palette, outlinesEveryChip: false))
  }

  public var palette: ReaderPalette {
    value.withLock { $0.palette }
  }

  /// Whether every chip is outlined, a normative one over its fill: the system's
  /// Increase Contrast, as the reader was last drawn under it.
  public var outlinesEveryChip: Bool {
    value.withLock { $0.outlinesEveryChip }
  }

  /// Replaces the palette and the contrast, and says whether either changed, so
  /// that the caller redraws only then.
  @discardableResult
  public func replace(with palette: ReaderPalette, outlinesEveryChip: Bool) -> Bool {
    let drawing = Drawing(palette: palette, outlinesEveryChip: outlinesEveryChip)
    return value.withLock { current in
      guard current != drawing else { return false }
      current = drawing
      return true
    }
  }
}

/// What a chip is drawn with (#457).
public struct ChipMarks: Equatable, Sendable {
  public var fills: Bool
  public var outlines: Bool

  public init(fills: Bool, outlines: Bool) {
    self.fills = fills
    self.outlines = outlines
  }

  /// An informative chip is an outline with no fill: it differs from a normative
  /// one by shape, not by an amount of tint that the light cards leave almost none
  /// of (#457, replacing #184's half tint). A normative chip is filled, and outlined
  /// over its fill as well where `outlinesEveryChip`, under Increase Contrast. A chip
  /// whose kind no list says is drawn as a normative one.
  public init(informative: Bool, outlinesEveryChip: Bool) {
    self =
      informative
      ? ChipMarks(fills: false, outlines: true)
      : ChipMarks(fills: true, outlines: outlinesEveryChip)
  }
}
