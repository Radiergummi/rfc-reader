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
    #expect(!box.replace(with: .automatic, outlinesEveryChip: false))
    let other = ReaderPalette(
      id: "other", cardFill: RFCColors.label, asideFill: RFCColors.label, rule: RFCColors.label,
      stroke: RFCColors.label, chipTint: RFCColors.label)
    #expect(box.replace(with: other, outlinesEveryChip: false))
    #expect(box.palette == other)
    #expect(!box.replace(with: other, outlinesEveryChip: false))
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
}
