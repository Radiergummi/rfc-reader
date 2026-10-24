import Foundation
import Testing

@testable import RFCReaderKit

/// A highlight's fill keeps the text over it readable, on the page and on every card,
/// in light and in dark (#522): 4.5:1, the rule the author monograms are held to; a
/// link over it 3.5:1, since a fill faint enough for a link's 4.5:1 cannot be seen.
@Suite("Annotations: the highlight palette")
struct HighlightColorTests {
  private static func color(_ hex: UInt32) -> SRGBColor { SRGBColor(hex: hex) }

  /// White and the Mac's and iOS's dark pages, and a card's tint over each.
  private static let lightBackdrops: [SRGBColor] = [
    .white, color(0x00_0000).composited(opacity: 0.03, over: .white),
    color(0x00_0000).composited(opacity: 0.045, over: .white),
  ]
  private static let darkPages: [SRGBColor] = [color(0x1E_1E1E), color(0x00_0000)]
  private static var darkBackdrops: [SRGBColor] {
    darkPages + darkPages.map { SRGBColor.white.composited(opacity: 0.085, over: $0) }
      + darkPages.map { SRGBColor.white.composited(opacity: 0.12, over: $0) }
  }

  @Test(arguments: HighlightColor.allCases.filter { !$0.isUnderline })
  func `the text clears the minimum on a fill, and a link its floor`(highlight: HighlightColor) {
    let fill = highlight.fill
    for backdrop in Self.lightBackdrops {
      let filled = fill.light.color.composited(opacity: fill.light.opacity, over: backdrop)
      #expect(Self.color(0x00_0000).contrast(with: filled) >= 4.5, "\(highlight) \(filled)")
      #expect(AccentContrast.readerLink.light.contrast(with: filled) >= 3.5, "\(highlight) link")
    }
    for backdrop in Self.darkBackdrops {
      let filled = fill.dark.color.composited(opacity: fill.dark.opacity, over: backdrop)
      #expect(Self.color(0xFF_FFFF).contrast(with: filled) >= 4.5, "\(highlight) \(filled)")
      #expect(AccentContrast.cardLink.dark.contrast(with: filled) >= 3.5, "\(highlight) link")
    }
  }

  /// Faint, but there: a highlight no one can see marks nothing.
  @Test(arguments: HighlightColor.allCases.filter { !$0.isUnderline })
  func `a fill shows on the page`(highlight: HighlightColor) {
    let fill = highlight.fill
    let light = fill.light.color.composited(opacity: fill.light.opacity, over: .white)
    #expect(SRGBColor.white.contrast(with: light) >= 1.15, "\(highlight)")
    for page in Self.darkPages {
      let dark = fill.dark.color.composited(opacity: fill.dark.opacity, over: page)
      #expect(dark.contrast(with: page) >= 1.15, "\(highlight)")
    }
  }

  @Test func `an unknown name reads as the default`() {
    #expect(HighlightColor(name: "chartreuse") == .yellow)
    #expect(HighlightColor(name: "underline") == .underline)
  }
}
