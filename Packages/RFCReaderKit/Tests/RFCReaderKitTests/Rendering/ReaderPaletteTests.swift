import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The draw-time colors (#703) and the page themes made of them (#704).
@Suite("Reader palette")
struct ReaderPaletteTests {
  /// The automatic palette is what the reader drew before there was a palette, so
  /// its colors are `RFCColors`' own, and it draws no page: the default draws
  /// exactly as before page themes.
  @Test func `the automatic palette draws the system colors`() {
    let palette = ReaderPalette.automatic
    #expect(palette.drawsSystemColors)
    #expect(palette.pageBackground == nil)
    #expect(palette.selection == nil)
    #expect(palette.text == RFCColors.label)
    #expect(palette.secondaryText == RFCColors.secondaryLabel)
    #expect(palette.stroke === RFCColors.stroke)
    #expect(palette.stated.isEmpty)
  }

  /// Its colors resolve as `RFCColors`' do, in each appearance: the links as the
  /// reader's, the cards as the page tint.
  @Test(arguments: PaletteAppearance.allCases)
  func `the automatic palette resolves to the system colors`(appearance: PaletteAppearance)
    throws
  {
    let palette = ReaderPalette.automatic
    let pairs: [(PlatformColor, PlatformColor)] = [
      (palette.text, RFCColors.label),
      (palette.secondaryText, RFCColors.secondaryLabel),
      (palette.link, RFCColors.readerLink),
      (palette.cardLink, RFCColors.cardLink(over: RFCColors.readerLink)),
      (palette.cardFill, RFCColors.cardFill),
      (palette.asideFill, RFCColors.asideFill),
      (palette.rule, RFCColors.rule),
      (palette.chipTint, RFCColors.accent),
    ]
    for (color, system) in pairs {
      let resolved = try #require(Self.resolved(color, in: appearance))
      let expected = try #require(Self.resolved(system, in: appearance))
      #expect(resolved == expected, "\(resolved) in \(appearance)")
    }
  }

  @Test func `an unknown palette is the automatic one`() {
    #expect(ReaderPalette.named("tartan", in: .light) == .automatic)
    #expect(ReaderPalette.named(nil, in: .dark) == .automatic)
    #expect(ReaderPalette.named(ReaderPalette.automatic.id, in: .light) == .automatic)
    #expect(ReaderPalette.named(ReaderPalette.sepia.id, in: .light) == .sepia)
  }

  /// Settings' two pickers: the light themes and the dark ones, Automatic first and
  /// High Contrast in both (#704).
  @Test func `each appearance offers its own themes`() {
    #expect(
      ReaderPalette.offered(in: .light).map(\.id) == [
        "automatic", "paper", "sepia", "gray", "high-contrast",
      ])
    #expect(
      ReaderPalette.offered(in: .dark).map(\.id) == [
        "automatic", "night", "black", "high-contrast",
      ])
    #expect(ReaderPalette.named(ReaderPalette.night.id, in: .light) == .automatic)
  }

  /// Every theme but Automatic draws a page of its own, in every appearance it has,
  /// in the colors it states.
  @Test func `every theme but automatic draws a page`() throws {
    for palette in ReaderPalette.all where palette != .automatic {
      #expect(!palette.drawsSystemColors, "\(palette.id)")
      #expect(Set(palette.stated.keys) == palette.appearances, "\(palette.id)")
      let page = try #require(palette.pageBackground, "\(palette.id)")
      for (appearance, colors) in palette.stated {
        let drawn = try #require(Self.resolved(page, in: appearance))
        #expect(Self.matches(drawn, colors.page), "\(palette.id) in \(appearance)")
        let text = try #require(Self.resolved(palette.text, in: appearance))
        #expect(Self.matches(text, colors.text), "\(palette.id) in \(appearance)")
      }
    }
  }

  /// A theme with both appearances draws each one's colors in it: its colors are
  /// dynamic, so dark mode is a redraw.
  @Test func `a theme with both appearances is dynamic`() throws {
    let palette = ReaderPalette.highContrast
    let light = try #require(Self.resolved(palette.text, in: .light))
    let dark = try #require(Self.resolved(palette.text, in: .dark))
    #expect(light != dark)
  }

  /// Every text role of every theme clears 4.5:1 against its page and against both
  /// its cards, in every appearance it has; High Contrast's clear 7:1. #694, a
  /// link in an aside at 4.04:1, is the bug this keeps out. The automatic palette
  /// draws the system's colors, which are the system's to hold to a contrast.
  @Test func `every theme's text clears the minimum contrast`() {
    for palette in ReaderPalette.all {
      let minimum = palette == .highContrast ? 7 : AccentContrast.minimumContrast
      for (appearance, colors) in palette.stated {
        let pairs: KeyValuePairs<String, (color: SRGBColor, background: SRGBColor)> = [
          "text on the page": (colors.text, colors.page),
          "secondary text on the page": (colors.secondaryText, colors.page),
          "a link on the page": (colors.link, colors.page),
          "text on a card": (colors.text, colors.card),
          "secondary text on a card": (colors.secondaryText, colors.card),
          "a link on a card": (colors.cardLink, colors.card),
          "text in an aside": (colors.text, colors.aside),
          "secondary text in an aside": (colors.secondaryText, colors.aside),
          "a link in an aside": (colors.cardLink, colors.aside),
        ]
        for (role, pair) in pairs {
          let ratio = pair.color.contrast(with: pair.background)
          #expect(ratio >= minimum, "\(palette.id) in \(appearance): \(role) is \(ratio):1")
        }
      }
    }
  }

  // MARK: - Text

  /// The text colors the builder stores resolve, as they are drawn, to the theme
  /// chosen for the appearance they are drawn in: a theme switch is a redraw (#704).
  @Test(arguments: PaletteAppearance.allCases)
  func `the themed text colors resolve to the theme chosen`(appearance: PaletteAppearance)
    throws
  {
    let chosen: @Sendable (PaletteAppearance) -> ReaderPalette = {
      $0 == .light ? .sepia : .black
    }
    let theme = chosen(appearance)
    for (role, color) in [
      (theme.text, ReaderPalette.themed(\.text, from: chosen)),
      (theme.secondaryText, ReaderPalette.themed(\.secondaryText, from: chosen)),
    ] {
      let resolved = try #require(Self.resolved(color, in: appearance))
      let expected = try #require(Self.resolved(role, in: appearance))
      #expect(resolved == expected, "\(theme.id) in \(appearance)")
    }
  }

  /// Under the automatic theme, which nothing has replaced, the stored text colors
  /// draw as the system's label colors: the default is unchanged.
  @Test(arguments: PaletteAppearance.allCases)
  func `the themed text colors are the system's under the automatic theme`(
    appearance: PaletteAppearance
  ) throws {
    for (color, system) in [
      (ReaderPalette.themedText, RFCColors.label),
      (ReaderPalette.themedSecondaryText, RFCColors.secondaryLabel),
    ] {
      let resolved = try #require(Self.resolved(color, in: appearance))
      let expected = try #require(Self.resolved(system, in: appearance))
      #expect(resolved == expected, "in \(appearance)")
    }
  }

  /// The reader's build stores the themed text colors, which follow a theme switch;
  /// a print's stores the system's, so paper keeps the paper palette whatever the
  /// screen's theme.
  @Test func `the screen's text follows the theme and paper's does not`() throws {
    let document = try Fixtures.rfc8999()
    let screen = DocumentTextBuilder.build(document, style: ReadingStyle()).text
    let paper = DocumentTextBuilder.build(
      document, style: PrintLayout(paperSize: PrintLayout.letter).style
    ).text
    func colors(in text: NSAttributedString) -> [PlatformColor] {
      var colors: [PlatformColor] = []
      text.enumerateAttribute(
        .foregroundColor, in: NSRange(location: 0, length: text.length)
      ) { value, _, _ in
        if let color = value as? PlatformColor { colors.append(color) }
      }
      return colors
    }
    let onScreen = colors(in: screen)
    #expect(onScreen.contains { $0 === ReaderPalette.themedText })
    #expect(onScreen.contains { $0 === ReaderPalette.themedSecondaryText })
    #expect(!onScreen.contains { $0 == RFCColors.label || $0 == RFCColors.secondaryLabel })
    let onPaper = colors(in: paper)
    #expect(onPaper.contains { $0 == RFCColors.label })
    #expect(!onPaper.contains { $0 === ReaderPalette.themedText })
    #expect(!onPaper.contains { $0 === ReaderPalette.themedSecondaryText })
  }

  /// A theme colors the links itself, on the page and on a card, and a hovered
  /// section number in its text color, while a resting one and the backlink
  /// caption keep the stored, themed, secondary color (#704). The automatic
  /// palette leaves them as the text view draws them, which the backlink and
  /// section number tests pin.
  @Test func `a theme colors the links`() throws {
    let palette = ReaderPalette.night
    let defaults: [NSAttributedString.Key: Any] = [.foregroundColor: RFCColors.accent]
    let jump = try #require(ReaderLinkScheme.url("two", scheme: ReaderLinkScheme.anchorScheme))
    let page = LinkRendering.attributes(for: jump, defaults: defaults, palette: palette)
    #expect(page[.foregroundColor] as? PlatformColor === palette.link)
    let card = LinkRendering.attributes(
      for: jump, defaults: defaults, palette: palette, onCard: true)
    #expect(card[.foregroundColor] as? PlatformColor === palette.cardLink)
    let caption = try #require(
      ReaderLinkScheme.url("two", scheme: ReaderLinkScheme.backlinksScheme))
    let kept = LinkRendering.attributes(for: caption, defaults: defaults, palette: palette)
    #expect(kept[.foregroundColor] == nil)
    let resting = LinkRendering.attributes(
      for: jump, defaults: defaults, sectionNumber: .resting, palette: palette)
    #expect(resting[.foregroundColor] == nil)
    let hovered = LinkRendering.attributes(
      for: jump, defaults: defaults, sectionNumber: .hovered, palette: palette)
    #expect(hovered[.foregroundColor] as? PlatformColor === palette.text)
    let automatic = LinkRendering.attributes(for: jump, defaults: defaults)
    #expect(automatic[.foregroundColor] as? PlatformColor === RFCColors.accent)
  }

  // MARK: - The box

  /// The caller redraws only when the palette changed.
  @Test func `the box says whether a replacement changed it`() {
    let box = ReaderPaletteBox()
    #expect(!box.replace(with: .automatic, outlinesEveryChip: false))
    #expect(box.replace(with: .sepia, outlinesEveryChip: false))
    #expect(box.palette == .sepia)
    #expect(!box.replace(with: .sepia, outlinesEveryChip: false))
  }

  /// An informative chip is drawn as an outline, and a normative one filled; with
  /// Increase Contrast, a normative one is outlined over its fill too (#457).
  @Test func `what a chip draws, by its kind and by Increase Contrast`() {
    #expect(
      ChipMarks(informative: false, outlinesEveryChip: false)
        == ChipMarks(fills: true, outlines: false))
    #expect(
      ChipMarks(informative: true, outlinesEveryChip: false)
        == ChipMarks(fills: false, outlines: true))
    #expect(
      ChipMarks(informative: false, outlinesEveryChip: true)
        == ChipMarks(fills: true, outlines: true))
    #expect(
      ChipMarks(informative: true, outlinesEveryChip: true)
        == ChipMarks(fills: false, outlines: true))
  }

  /// Turning Increase Contrast on is a change the box redraws for, and leaves the
  /// palette the reader chose as it was.
  @Test func `increasing the contrast is a change the box redraws for`() {
    let box = ReaderPaletteBox()
    #expect(box.replace(with: .automatic, outlinesEveryChip: true))
    #expect(box.outlinesEveryChip)
    #expect(box.palette == .automatic)
    #expect(!box.replace(with: .automatic, outlinesEveryChip: true))
    #expect(box.replace(with: .automatic, outlinesEveryChip: false))
    #expect(!box.outlinesEveryChip)
  }

  // MARK: - Resolving

  private struct Resolved: Equatable, CustomStringConvertible {
    var color: SRGBColor
    var opacity: Double
    var description: String { "\(color) at \(opacity)" }
  }

  /// Opaque, and `color` within a rounding of 8-bit components.
  private static func matches(_ resolved: Resolved, _ color: SRGBColor) -> Bool {
    resolved.opacity == 1 && abs(resolved.color.red - color.red) < 0.002
      && abs(resolved.color.green - color.green) < 0.002
      && abs(resolved.color.blue - color.blue) < 0.002
  }

  /// `color` as `appearance` resolves it, with its opacity, so that two fills that
  /// differ only by it differ here.
  private static func resolved(_ color: PlatformColor, in appearance: PaletteAppearance)
    -> Resolved?
  {
    var resolved: (color: SRGBColor, opacity: Double)?
    #if canImport(UIKit)
      UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
        .performAsCurrent {
          resolved = SRGBColor.resolvingWithOpacity(color)
        }
    #else
      NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)?
        .performAsCurrentDrawingAppearance {
          resolved = SRGBColor.resolvingWithOpacity(color)
        }
    #endif
    return resolved.map { Resolved(color: $0.color, opacity: $0.opacity) }
  }
}
