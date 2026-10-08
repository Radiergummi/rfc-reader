import Testing

@testable import RFCReaderKit

/// The draw-time colors (#703).
@Suite("Reader palette")
struct ReaderPaletteTests {
  /// The automatic palette is what the reader drew before there was a palette, so
  /// its colors are `RFCColors`' own.
  @Test func `the automatic palette draws the system colors`() {
    let palette = ReaderPalette.automatic
    #expect(palette.pageBackground == nil)
    #expect(palette.stroke === RFCColors.stroke)
  }

  @Test func `an unknown palette is the automatic one`() {
    #expect(ReaderPalette.named("tartan") == .automatic)
    #expect(ReaderPalette.named(nil) == .automatic)
    #expect(ReaderPalette.named(ReaderPalette.automatic.id) == .automatic)
  }

  /// The caller redraws only when the palette changed.
  @Test func `the box says whether a replacement changed it`() {
    let box = ReaderPaletteBox()
    #expect(!box.replace(with: .automatic))
    let other = ReaderPalette(
      id: "other", cardFill: RFCColors.label, asideFill: RFCColors.label, rule: RFCColors.label,
      stroke: RFCColors.label, chipTint: RFCColors.label)
    #expect(box.replace(with: other))
    #expect(box.palette == other)
    #expect(!box.replace(with: other))
  }

  /// An informative chip is drawn as an outline, and a normative one filled; with
  /// Increase Contrast, a normative one is outlined over its fill too (#457).
  @Test func `what a chip draws, by its kind and by Increase Contrast`() {
    let palette = ReaderPalette.automatic
    #expect(palette.chipMarks(informative: false) == .init(fills: true, outlines: false))
    #expect(palette.chipMarks(informative: true) == .init(fills: false, outlines: true))
    let increased = palette.increasingContrast(true)
    #expect(increased.chipMarks(informative: false) == .init(fills: true, outlines: true))
    #expect(increased.chipMarks(informative: true) == .init(fills: false, outlines: true))
  }

  /// Turning Increase Contrast on is a change the box redraws for.
  @Test func `increasing the contrast changes the palette`() {
    let box = ReaderPaletteBox()
    #expect(box.replace(with: ReaderPalette.automatic.increasingContrast(true)))
    #expect(!box.replace(with: ReaderPalette.automatic.increasingContrast(true)))
    #expect(box.replace(with: .automatic))
  }
}
