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
  /// its colors are `RFCColors`' own, and it recolors nothing: the default draws
  /// exactly as before page themes.
  @Test func `the automatic palette draws the system colors`() {
    let palette = ReaderPalette.automatic
    #expect(palette.drawsStoredColors)
    #expect(palette.pageBackground == nil)
    #expect(palette.selection == nil)
    #expect(palette.text === RFCColors.label)
    #expect(palette.secondaryText === RFCColors.secondaryLabel)
    #expect(palette.stroke === RFCColors.stroke)
    #expect(palette.stated.isEmpty)
    #expect(palette.foreground(for: RFCColors.label) == nil)
    #expect(palette.foreground(for: RFCColors.secondaryLabel) == nil)
    #expect(palette.foreground(for: nil) == nil)
  }

  /// Its colors resolve as `RFCColors`' do, in each appearance: the links as the
  /// reader's, the cards as the page tint.
  @Test(arguments: PaletteAppearance.allCases)
  func `the automatic palette resolves to the system colors`(appearance: PaletteAppearance)
    throws
  {
    let palette = ReaderPalette.automatic
    let pairs: [(PlatformColor, PlatformColor)] = [
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
      ReaderPalette.offered(in: .dark).map(\.id) == ["automatic", "night", "black", "high-contrast"])
    #expect(ReaderPalette.named(ReaderPalette.night.id, in: .light) == .automatic)
  }

  /// Every theme but Automatic draws a page of its own, in every appearance it has,
  /// in the colors it states.
  @Test func `every theme but automatic draws a page`() throws {
    for palette in ReaderPalette.all where palette != .automatic {
      #expect(!palette.drawsStoredColors, "\(palette.id)")
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
        let pairs: [(String, SRGBColor, SRGBColor)] = [
          ("text on the page", colors.text, colors.page),
          ("secondary text on the page", colors.secondaryText, colors.page),
          ("a link on the page", colors.link, colors.page),
          ("text on a card", colors.text, colors.card),
          ("secondary text on a card", colors.secondaryText, colors.card),
          ("a link on a card", colors.cardLink, colors.card),
          ("text in an aside", colors.text, colors.aside),
          ("secondary text in an aside", colors.secondaryText, colors.aside),
          ("a link in an aside", colors.cardLink, colors.aside),
        ]
        for (role, color, background) in pairs {
          let ratio = color.contrast(with: background)
          #expect(ratio >= minimum, "\(palette.id) in \(appearance): \(role) is \(ratio):1")
        }
      }
    }
  }

  // MARK: - Text

  /// A theme draws the label colors the builder stores in its own text colors, and
  /// leaves every other color, such as a syntax color, as it is.
  @Test func `a theme maps the stored label colors to its own`() {
    let palette = ReaderPalette.sepia
    #expect(palette.foreground(for: RFCColors.label) === palette.text)
    #expect(palette.foreground(for: RFCColors.secondaryLabel) === palette.secondaryText)
    #expect(palette.foreground(for: nil) === palette.text)
    #expect(palette.foreground(for: DocumentTextBuilder.hiddenColor) == nil)
    #expect(palette.foreground(for: SyntaxTheme.standard.color(for: .keyword)) == nil)
  }

  /// Over a built document, a theme recolors the label-colored text and nothing
  /// else, leaves the links to the text view, and the automatic palette recolors
  /// nothing at all.
  @Test func `the recolored runs are the stored label colors, links aside`() throws {
    let text = try LayoutFixture.built().text
    let whole = NSRange(location: 0, length: text.length)
    #expect(ReaderPalette.automatic.recoloredRuns(in: text, range: whole).isEmpty)

    let palette = ReaderPalette.sepia
    let runs = palette.recoloredRuns(in: text, range: whole)
    #expect(!runs.isEmpty)
    var covered = IndexSet()
    for run in runs {
      covered.insert(integersIn: run.range.location..<NSMaxRange(run.range))
      text.enumerateAttributes(in: run.range) { attributes, _, _ in
        #expect(attributes[.link] == nil)
        let stored = attributes[.foregroundColor] as? PlatformColor
        #expect(palette.foreground(for: stored) === run.color)
      }
    }
    // Every label-colored character that is no link is in a run.
    text.enumerateAttributes(in: whole) { attributes, range, _ in
      guard attributes[.link] == nil,
        palette.foreground(for: attributes[.foregroundColor] as? PlatformColor) != nil
      else { return }
      #expect(covered.contains(integersIn: range.location..<NSMaxRange(range)))
    }
    // Neighbors of one color are one run.
    for (run, next) in zip(runs, runs.dropFirst()) {
      #expect(NSMaxRange(run.range) < next.range.location || run.color !== next.color)
    }
  }

  /// A run that starts or ends outside the range asked for is cut to it: a
  /// fragment is recolored and nothing beyond it.
  @Test func `the recolored runs stay inside the range asked for`() throws {
    let text = try LayoutFixture.built().text
    let range = NSRange(location: 3, length: min(200, text.length - 3))
    for run in ReaderPalette.sepia.recoloredRuns(in: text, range: range) {
      #expect(NSIntersectionRange(run.range, range) == run.range)
    }
  }

  /// A theme colors the links itself, on the page and on a card, and the hung
  /// section number and the backlink caption keep their quieter color in the
  /// theme's secondary text (#704). The automatic palette leaves them as the text
  /// view draws them, which the backlink and section number tests pin.
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
    #expect(kept[.foregroundColor] as? PlatformColor === palette.secondaryText)
    let resting = LinkRendering.attributes(
      for: jump, defaults: defaults, sectionNumber: .resting, palette: palette)
    #expect(resting[.foregroundColor] as? PlatformColor === palette.secondaryText)
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
