import SwiftUI
import Testing

@testable import RFCReaderKit

/// The reader's sizes and weights follow the system's text size and Bold Text, with
/// the reader's own size as a multiplier on top (#153).
@Suite("Reading style")
struct ReadingStyleTests {
  /// The system's default size changes nothing, so the Mac — which has no Dynamic
  /// Type and always reports it — reads exactly as it did.
  @Test func `at the default text size the body is the reader's own size`() {
    #expect(ReadingStyle(bodySize: 17).bodySize == 17)
    #expect(ReadingStyle(bodySize: 20, textSize: .large).bodySize == 20)
  }

  @Test func `headings follow the system's title and headline sizes`() {
    let style = ReadingStyle(bodySize: 17)
    #expect(style.headingFont(depth: 1).pointSize == 22)
    #expect(style.headingFont(depth: 2).pointSize == 20)
    #expect(style.headingFont(depth: 3).pointSize == 17)
  }

  @Test func `the largest accessibility size scales the body the way the system does`() {
    #expect(ReadingStyle(bodySize: 17, textSize: .accessibility5).bodySize == 53)
  }

  @Test func `headings grow with the text size`() {
    let style = ReadingStyle(bodySize: 17, textSize: .accessibility5)
    #expect(style.headingFont(depth: 1).pointSize == 56)
    #expect(style.headingFont(depth: 2).pointSize == 55)
    #expect(style.headingFont(depth: 3).pointSize == 53)
  }

  /// Someone at a large system size who nudges the reader up a step expects it to
  /// stay large, and larger: the two multiply.
  @Test func `the reader's own size multiplies the system's`() {
    let style = ReadingStyle(bodySize: 34, textSize: .xxxLarge)
    #expect(style.bodySize == 46)
  }

  @Test func `everything measured from the body scales with it`() {
    let small = ReadingStyle(bodySize: 17)
    let large = ReadingStyle(bodySize: 17, textSize: .accessibility1)
    let ratio = large.bodySize / small.bodySize
    #expect(large.paragraphSpacing == small.paragraphSpacing * ratio)
    #expect(large.captionFont.pointSize == small.captionFont.pointSize * ratio)
  }

  /// The weight the face states, read off its descriptor. Not `PlatformFont.weight`,
  /// which counts anything carrying the bold trait — semibold included — as bold.
  private func stated(_ font: PlatformFont) -> CGFloat {
    let traits =
      font.fontDescriptor.object(forKey: .traits) as? [PlatformFontDescriptor.TraitKey: Any]
    return traits?[.weight] as? CGFloat ?? 0
  }

  @Test func `without bold text the body is regular and headings semibold`() {
    let style = ReadingStyle(bodySize: 17)
    #expect(stated(style.bodyFont) == stated(.systemFont(ofSize: 17, weight: .regular)))
    #expect(
      stated(style.headingFont(depth: 1)) == stated(.systemFont(ofSize: 17, weight: .semibold)))
  }

  @Test func `bold text makes the body semibold and headings bold`() {
    let style = ReadingStyle(bodySize: 17, boldText: true)
    #expect(stated(style.bodyFont) == stated(.systemFont(ofSize: 17, weight: .semibold)))
    for depth in 1...3 {
      #expect(
        stated(style.headingFont(depth: depth)) == stated(.systemFont(ofSize: 17, weight: .bold)))
    }
  }

  /// The abstract is set a little smaller; scaling must not apply the text size a
  /// second time, or lose Bold Text on the way.
  @Test func `scaling keeps the text size and the weight`() {
    let style = ReadingStyle(bodySize: 17, textSize: .accessibility5, boldText: true)
    let scaled = style.scaled(by: 0.5)
    #expect(scaled.bodySize == 26.5)
    #expect(scaled.headingFont(depth: 1).pointSize == 28)
    #expect(stated(scaled.bodyFont) == stated(style.bodyFont))
  }
}
