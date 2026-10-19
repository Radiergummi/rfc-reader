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
/// `ReaderPaletteBox` each layout manager of built text is given, and the text
/// views draw the page and the text in it: the builder keeps storing the system's
/// dynamic label colors, and a text view maps them to the palette's as each
/// fragment comes into view (`recoloredRuns(in:range:)`), and its links through
/// `LinkRendering`. See
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
  /// Whether the text is drawn in the colors the builder stored, and the links in
  /// the text view's own: the automatic palette, whose text roles are those
  /// colors, so that a text view sets no rendering attributes for it and the
  /// default draws exactly as the reader always has.
  public let drawsStoredColors: Bool
  /// Behind the text, or nil to draw none and let the window's background show, as
  /// the automatic palette does.
  public var pageBackground: PlatformColor?
  /// Body text, in place of the stored `RFCColors.label`.
  public var text: PlatformColor
  /// Quieter text, in place of the stored `RFCColors.secondaryLabel`: list markers,
  /// section numbers, captions, the abstract.
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
    drawsStoredColors: Bool = false, pageBackground: PlatformColor? = nil,
    text: PlatformColor = RFCColors.label, secondaryText: PlatformColor = RFCColors.secondaryLabel,
    link: PlatformColor = RFCColors.readerLink,
    cardLink: PlatformColor = RFCColors.cardLink(over: RFCColors.readerLink),
    selection: PlatformColor? = nil, cardFill: PlatformColor, asideFill: PlatformColor,
    rule: PlatformColor, stroke: PlatformColor, chipTint: PlatformColor,
    stated: [PaletteAppearance: PaletteColors] = [:]
  ) {
    self.id = id
    self.appearances = appearances
    self.drawsStoredColors = drawsStoredColors
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
    drawsStoredColors: true,
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

  /// The color a run whose stored foreground is `stored` is drawn in: the palette's
  /// text and secondary text in place of the system's label colors, and its text
  /// where nothing is stored. Nil to draw what is stored as it is: any other color,
  /// such as a syntax color (#707) or a hidden border's, and every color under a
  /// palette that `drawsStoredColors`.
  public func foreground(for stored: PlatformColor?) -> PlatformColor? {
    guard !drawsStoredColors else { return nil }
    guard let stored else { return text }
    if Self.isSame(stored, RFCColors.label) { return text }
    if Self.isSame(stored, RFCColors.secondaryLabel) { return secondaryText }
    return nil
  }

  /// The same color: the one instance `RFCColors` keeps, which the builder stores,
  /// or an equal one.
  private static func isSame(_ color: PlatformColor, _ other: PlatformColor) -> Bool {
    color === other || color == other
  }

  /// The runs of `range` of `text` a text view draws in another color than the
  /// one stored, each with that color, neighbors of one color joined: what it sets
  /// as rendering attributes as a fragment comes into view. A link is left out: a
  /// text view colors its links itself (`LinkRendering`). Empty for a palette that
  /// `drawsStoredColors`, so the default costs a text view nothing.
  public func recoloredRuns(in text: NSAttributedString, range: NSRange)
    -> [(range: NSRange, color: PlatformColor)]
  {
    guard !drawsStoredColors, range.length > 0 else { return [] }
    var runs: [(range: NSRange, color: PlatformColor)] = []
    text.enumerateAttributes(in: range) { attributes, run, _ in
      guard attributes[.link] == nil,
        let color = foreground(for: attributes[.foregroundColor] as? PlatformColor)
      else { return }
      if let last = runs.last, NSMaxRange(last.range) == run.location, last.color === color {
        runs[runs.count - 1].range.length += run.length
      } else {
        runs.append((run, color))
      }
    }
    return runs
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
