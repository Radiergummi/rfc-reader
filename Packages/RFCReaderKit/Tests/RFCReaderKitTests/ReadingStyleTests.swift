import SwiftUI
import Testing

@testable import RFCReaderKit

/// The reader's sizes follow the system's text size, with the reader's own size as a
/// multiplier on top (#153).
@Suite("Reading style")
struct ReadingStyleTests {
  /// The system's default size changes nothing about the body, so the Mac — which
  /// has no Dynamic Type and always reports it — reads at the size it did.
  @Test func `at the default text size the body is the reader's own size`() {
    #expect(ReadingStyle(bodySize: 17).bodySize == 17)
    #expect(ReadingStyle(bodySize: 20, textSize: .large).bodySize == 20)
  }

  #if os(macOS)
    /// The Mac's own Title 2 and Title 3 against its 13 pt body, 17/13 and 15/13,
    /// as the reader has always rounded them: its headings do not move.
    @Test func `headings keep the Mac's own title ratios`() {
      let style = ReadingStyle(bodySize: 17)
      #expect(abs(style.headingFont(depth: 1).pointSize - 22.1) < 0.001)
      #expect(abs(style.headingFont(depth: 2).pointSize - 19.55) < 0.001)
      #expect(style.headingFont(depth: 3).pointSize == 17)
    }
  #else
    @Test func `headings follow the system's title and headline sizes`() {
      let style = ReadingStyle(bodySize: 17)
      #expect(style.headingFont(depth: 1).pointSize == 22)
      #expect(style.headingFont(depth: 2).pointSize == 20)
      #expect(style.headingFont(depth: 3).pointSize == 17)
    }

    @Test func `headings grow with the text size`() {
      let style = ReadingStyle(bodySize: 17, textSize: .accessibility5)
      #expect(style.headingFont(depth: 1).pointSize == 56)
      #expect(style.headingFont(depth: 2).pointSize == 55)
      #expect(style.headingFont(depth: 3).pointSize == 53)
    }
  #endif

  @Test func `the largest accessibility size scales the body the way the system does`() {
    #expect(ReadingStyle(bodySize: 17, textSize: .accessibility5).bodySize == 53)
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

  /// An iPhone's column at the largest text size: a paragraph indented five steps —
  /// an authored indent inside a list inside a definition list — would be set in
  /// past the column's width if the step grew with the body. It stops at a share of
  /// the column instead, so the text keeps most of the line.
  @Test func `five indent steps leave most of a phone's column at the largest text size`() {
    let style = ReadingStyle(bodySize: 17, measure: 345, textSize: .accessibility5)
    #expect(style.indentStep * 5 <= style.measure * 0.4)
  }

  @Test func `the indent step follows the body at ordinary sizes`() {
    for measure: CGFloat in [345, 712] {
      let style = ReadingStyle(bodySize: 17, measure: measure)
      #expect(abs(style.indentStep - 23.8) < 0.001)
    }
  }

  /// The weight the face states, read off its descriptor, independently of
  /// `PlatformFont.weight`, which the code under test relies on.
  private func stated(_ font: PlatformFont) -> CGFloat {
    let traits =
      font.fontDescriptor.object(forKey: .traits) as? [PlatformFontDescriptor.TraitKey: Any]
    return traits?[.weight] as? CGFloat ?? 0
  }

  @Test func `the body is regular and headings semibold`() {
    let style = ReadingStyle(bodySize: 17)
    #expect(stated(style.bodyFont) == stated(.systemFont(ofSize: 17, weight: .regular)))
    #expect(
      stated(style.headingFont(depth: 1)) == stated(.systemFont(ofSize: 17, weight: .semibold)))
  }

  /// The abstract is set a little smaller; scaling must not apply the text size a
  /// second time.
  @Test func `scaling keeps the text size`() {
    let style = ReadingStyle(bodySize: 17, textSize: .accessibility5)
    let scaled = style.scaled(by: 0.5)
    #expect(scaled.bodySize == 26.5)
    #expect(scaled.headingFont(depth: 1).pointSize == style.headingFont(depth: 1).pointSize / 2)
  }

  @Test func `strong text is heavier than the body`() {
    let style = ReadingStyle(bodySize: 17)
    #expect(stated(style.strongFont(matching: style.bodyFont)) > stated(style.bodyFont))
  }

  /// A heading is semibold, and the bold trait on a semibold face leaves it
  /// semibold: strong text in a heading would read the same as the heading.
  @Test func `strong text is heavier than a heading around it`() {
    let style = ReadingStyle(bodySize: 17)
    let heading = style.headingFont(depth: 1)
    #expect(stated(style.strongFont(matching: heading)) > stated(heading))
    #expect(style.strongFont(matching: heading).pointSize == heading.pointSize)
  }

  @Test func `strong text keeps an italic slant`() {
    let style = ReadingStyle(bodySize: 17)
    let italic = style.bodyFont.adding(traits: RFCTraits.italic)
    #expect(
      style.strongFont(matching: italic).fontDescriptor.symbolicTraits.contains(RFCTraits.italic))
  }

  /// Code takes the weight of the prose around it, and a semibold face is not a
  /// bold one just because it carries the bold trait.
  @Test func `inline code in a heading takes the heading's semibold weight`() {
    let style = ReadingStyle(bodySize: 17)
    let code = style.codeFont(matching: style.headingFont(depth: 1))
    #expect(stated(code) == stated(.monospacedSystemFont(ofSize: 17, weight: .semibold)))
  }
}
