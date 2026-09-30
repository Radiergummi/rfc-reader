import RFCKit
import Testing

@testable import RFCReaderKit

/// The status badges' colors, held to the contrast text at standard sizes needs
/// (#317). The system colors they used measured 1.95:1 (Experimental) to 3.42:1
/// (BCP) in light appearance.
@Suite("Status palette")
struct StatusPaletteTests {
  @Test(arguments: PublicationStatus.allCases)
  func `a badge's text clears the minimum on its fill in both appearances`(
    status: PublicationStatus
  ) {
    for appearance in StatusPalette.Appearance.allCases {
      let colors = StatusPalette.colors(for: status, in: appearance)
      let contrast = colors.text.contrast(with: colors.fill)
      #expect(
        contrast >= StatusPalette.minimumContrast, "\(status) \(appearance): \(contrast)")
    }
  }

  /// The Info pane's Obsolete box is red, and held to the same minimum.
  @Test(arguments: StatusPalette.Appearance.allCases)
  func `the obsolete box's text clears the minimum on its fill`(
    appearance: StatusPalette.Appearance
  ) {
    let colors = StatusPalette.obsolete(in: appearance)
    let contrast = colors.text.contrast(with: colors.fill)
    #expect(contrast >= StatusPalette.minimumContrast, "\(appearance): \(contrast)")
  }

  /// A badge draws its own opaque fill, so it reads the same on a selected row as on
  /// a plain one; a light fill in light appearance and a dark one in dark. The
  /// Obsolete box's fill is made the same way.
  @Test func `the fills are light in light appearance and dark in dark`() {
    let palettes = PublicationStatus.allCases.map { status in
      { StatusPalette.colors(for: status, in: $0) }
    }
    for colors in palettes + [StatusPalette.obsolete(in:)] {
      #expect(colors(.light).fill.relativeLuminance > 0.7)
      #expect(colors(.dark).fill.relativeLuminance < 0.1)
    }
  }

  /// The statuses keep the hues they had: the standards share one, and each other
  /// status has its own, in either appearance.
  @Test(arguments: StatusPalette.Appearance.allCases)
  func `standards share a color and the other statuses have their own`(
    appearance: StatusPalette.Appearance
  ) {
    let text = { (status: PublicationStatus) in
      StatusPalette.colors(for: status, in: appearance).text
    }
    #expect(text(.internetStandard) == text(.draftStandard))
    let distinct: [PublicationStatus] = [
      .internetStandard, .proposedStandard, .bestCurrentPractice, .informational, .experimental,
      .historic,
    ]
    #expect(Set(distinct.map(text)).count == distinct.count)
  }
}
