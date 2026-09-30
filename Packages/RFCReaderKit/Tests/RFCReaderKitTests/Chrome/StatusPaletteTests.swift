import RFCKit
import Testing

@testable import RFCReaderKit

/// The status badges' colors, held to the contrast text at standard sizes needs
/// (#317). The system colors they used measured 1.95:1 (Experimental) to 3.42:1
/// (BCP) in light appearance.
@Suite("Status palette")
struct StatusPaletteTests {
  /// A dark fill is translucent, so the text is measured over each background a
  /// badge is drawn on: pure black in the iOS document header, `#1C1C1E` in a list cell.
  @Test(arguments: PublicationStatus.allCases)
  func `a badge's text clears the minimum on its fill in both appearances`(
    status: PublicationStatus
  ) {
    for appearance in StatusPalette.Appearance.allCases {
      Self.expectReadable(StatusPalette.colors(for: status, in: appearance), in: appearance)
    }
  }

  /// The Info pane's Obsolete box is red, and held to the same minimum.
  @Test(arguments: StatusPalette.Appearance.allCases)
  func `the obsolete box's text clears the minimum on its fill`(
    appearance: StatusPalette.Appearance
  ) {
    Self.expectReadable(StatusPalette.obsolete(in: appearance), in: appearance)
  }

  /// A light fill is opaque, as the badge has always drawn it; a dark one is
  /// translucent, so the pill takes the color of what is behind it.
  @Test func `the light fills are opaque and the dark ones translucent`() {
    let palettes = PublicationStatus.allCases.map { status in
      { StatusPalette.colors(for: status, in: $0) }
    }
    for colors in palettes + [StatusPalette.obsolete(in:)] {
      #expect(colors(.light).fillOpacity == 1)
      #expect(colors(.dark).fillOpacity < 1)
    }
  }

  /// A light fill in light appearance and a dark one in dark, over whatever it is
  /// drawn on.
  @Test func `the fills are light in light appearance and dark in dark`() {
    for status in PublicationStatus.allCases {
      let light = StatusPalette.colors(for: status, in: .light)
      #expect(light.fill(over: .white).relativeLuminance > 0.7)
      let dark = StatusPalette.colors(for: status, in: .dark)
      for background in StatusPalette.darkBackgrounds {
        #expect(dark.fill(over: background).relativeLuminance < 0.1)
      }
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

  private static func expectReadable(
    _ colors: StatusPalette.Colors, in appearance: StatusPalette.Appearance,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for background in StatusPalette.backgrounds(in: appearance) {
      let contrast = colors.text.contrast(with: colors.fill(over: background))
      #expect(
        contrast >= StatusPalette.minimumContrast, "\(appearance) over \(background): \(contrast)",
        sourceLocation: sourceLocation)
    }
  }
}
