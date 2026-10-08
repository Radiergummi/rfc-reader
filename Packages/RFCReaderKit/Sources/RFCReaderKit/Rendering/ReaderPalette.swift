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
/// `ReaderPaletteBox` each layout manager of built text is given. See
/// `docs/decisions/2026-10-03-reader-settings-are-a-build-time-style-and-a-draw-time-palette.md`.
///
/// Every color must be dynamic, resolved by appearance when drawn, as `RFCColors`'
/// are: dark mode is a redraw, and print's forced light appearance needs no palette
/// of its own. Page themes (#704) add palettes beside `automatic`.
///
/// Equal by `id` alone, for the reason `SyntaxTheme` is: dynamic colors compare by
/// identity.
public struct ReaderPalette: Sendable, Hashable, Identifiable {
  public let id: String
  /// Behind the text, or nil to draw none and let the window's background show, as
  /// the reader always has.
  public var pageBackground: PlatformColor?
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
  /// Whether every chip is outlined, a normative one over its fill: the system's
  /// Increase Contrast, read where the reader is drawn (`increasingContrast(_:)`).
  public private(set) var outlinesEveryChip = false

  public init(
    id: String, pageBackground: PlatformColor? = nil, cardFill: PlatformColor,
    asideFill: PlatformColor, rule: PlatformColor, stroke: PlatformColor,
    chipTint: PlatformColor
  ) {
    self.id = id
    self.pageBackground = pageBackground
    self.cardFill = cardFill
    self.asideFill = asideFill
    self.rule = rule
    self.stroke = stroke
    self.chipTint = chipTint
  }

  public static func == (lhs: ReaderPalette, rhs: ReaderPalette) -> Bool {
    lhs.id == rhs.id && lhs.outlinesEveryChip == rhs.outlinesEveryChip
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(outlinesEveryChip)
  }

  /// This palette, with every chip outlined where the system asks for more
  /// contrast: a redraw, as any change of palette is, and never a rebuild.
  public func increasingContrast(_ increases: Bool) -> ReaderPalette {
    var palette = self
    palette.outlinesEveryChip = increases
    return palette
  }

  /// What a chip is drawn with (#457).
  public struct ChipMarks: Equatable, Sendable {
    public var fills: Bool
    public var outlines: Bool

    public init(fills: Bool, outlines: Bool) {
      self.fills = fills
      self.outlines = outlines
    }
  }

  /// An informative chip is an outline with no fill: it differs from a normative
  /// one by shape, not by an amount of tint that the light cards leave almost none
  /// of (#457, replacing #184's half tint). A normative chip is filled, and outlined
  /// over its fill as well under Increase Contrast. A chip whose kind no list says
  /// is drawn as a normative one.
  public func chipMarks(informative: Bool) -> ChipMarks {
    informative
      ? ChipMarks(fills: false, outlines: true)
      : ChipMarks(fills: true, outlines: outlinesEveryChip)
  }

  /// The system's colors, and what a print draws with: its light appearance
  /// resolves them to a white page's.
  public static let automatic = ReaderPalette(
    id: "automatic",
    cardFill: RFCColors.cardFill,
    asideFill: RFCColors.asideFill,
    rule: RFCColors.rule,
    stroke: RFCColors.stroke,
    chipTint: RFCColors.accent
  )

  /// Every palette the reader offers, the automatic one first.
  public static let all: [ReaderPalette] = [.automatic]

  /// The palette called `id`, or the automatic one where there is none by that name.
  public static func named(_ id: String?) -> ReaderPalette {
    all.first { $0.id == id } ?? .automatic
  }
}

/// The palette a layout manager's fragments draw with, read on whatever thread
/// TextKit draws on and replaced on the main actor when the setting changes.
///
/// A box rather than a value handed to each fragment, because fragments outlive a
/// change of palette: TextKit keeps the ones it laid out, and a theme switch must
/// recolor them without laying anything out again. Whoever replaces the palette
/// asks the text view to redraw.
public final class ReaderPaletteBox: Sendable {
  private let value: Mutex<ReaderPalette>

  public init(_ palette: ReaderPalette = .automatic) {
    value = Mutex(palette)
  }

  public var palette: ReaderPalette {
    value.withLock { $0 }
  }

  /// Replaces the palette, and says whether it changed, so that the caller redraws
  /// only then.
  @discardableResult
  public func replace(with palette: ReaderPalette) -> Bool {
    value.withLock { current in
      guard current != palette else { return false }
      current = palette
      return true
    }
  }
}
