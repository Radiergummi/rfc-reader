import Testing

@testable import RFCReaderKit

/// WCAG 2.x relative luminance and contrast ratio, which the author monograms' tints
/// are held to (#19).
@Suite("Contrast")
struct ContrastTests {
  @Test func `a hex value splits into its channels`() {
    let color = SRGBColor(hex: 0x33_66FF)
    #expect(color == SRGBColor(red: 0.2, green: 0.4, blue: 1))
  }

  @Test func `luminance weights the linearised channels`() {
    #expect(SRGBColor.white.relativeLuminance == 1)
    #expect(SRGBColor.black.relativeLuminance == 0)
    #expect(abs(SRGBColor(hex: 0xFF_0000).relativeLuminance - 0.2126) < 1e-12)
    #expect(abs(SRGBColor(hex: 0x00_FF00).relativeLuminance - 0.7152) < 1e-12)
    #expect(abs(SRGBColor(hex: 0x00_00FF).relativeLuminance - 0.0722) < 1e-12)
  }

  /// Below 0.04045 sRGB is linear, a straight division by 12.92; above it, the
  /// 2.4 power curve. Mid grey is 0.2159, not the 0.5 its channels say.
  @Test func `both segments of the sRGB curve are linearised`() {
    #expect(abs(SRGBColor(hex: 0x0A_0A0A).relativeLuminance - 10 / 255 / 12.92) < 1e-12)
    #expect(abs(SRGBColor(hex: 0x80_8080).relativeLuminance - 0.2159) < 1e-4)
  }

  @Test func `white on black is 21 to 1`() {
    #expect(abs(SRGBColor.white.contrast(with: .black) - 21) < 1e-9)
  }

  @Test func `contrast is the same either way round`() {
    let grey = SRGBColor(hex: 0x77_7777)
    #expect(grey.contrast(with: .white) == SRGBColor.white.contrast(with: grey))
  }

  @Test func `a color against itself is 1 to 1`() {
    let grey = SRGBColor(hex: 0x77_7777)
    #expect(grey.contrast(with: grey) == 1)
  }

  /// The pair the threshold is usually taught with: #777777 is the lightest grey
  /// that looks like it should pass and does not, #767676 the lightest that does.
  @Test func `white on 777777 falls just short of 4.5 to 1`() {
    let contrast = SRGBColor.white.contrast(with: SRGBColor(hex: 0x77_7777))
    #expect(abs(contrast - 4.48) < 0.005)
    #expect(contrast < 4.5)
    #expect(SRGBColor.white.contrast(with: SRGBColor(hex: 0x76_7676)) >= 4.5)
  }
}
