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

  @Test func `an informative chip is tinted half as strongly`() {
    #expect(ReaderPalette.informativeChipOpacity * 2 == ReaderPalette.chipOpacity)
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
}
