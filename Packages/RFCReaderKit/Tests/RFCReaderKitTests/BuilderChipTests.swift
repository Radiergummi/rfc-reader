import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Builder: reference chips")
@MainActor
struct BuilderChipTests {
  private let style = ReadingStyle()

  private func run(_ xref: CrossReference) -> NSAttributedString {
    Fixtures.inlineRun([.crossReference(xref)], style: style)
  }

  @Test func aCanonicalLabelLosesItsBrackets() {
    let xref = CrossReference(target: .document(.rfc(9110), section: nil))
    #expect(run(xref).string == "\u{FFFC}\u{2060}RFC\u{00A0}9110")
  }

  /// A reference to a section of another document is one reference, so it reads as
  /// one chip with the section as a suffix -- not as a sentence fragment with the
  /// document buried in the middle of it.
  @Test func aSectionReferenceBecomesOneChipWithASectionSuffix() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(run(xref).string == "\u{FFFC}\u{2060}RFC\u{00A0}9110\u{00A0}§\u{00A0}4.2")
  }

  /// Nothing in the label may break across a line: not the series word from its
  /// number, and not the section mark from its number.
  @Test func aSectionLabelIsBoundTogether() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(xref.displayLabel == "RFC\u{00A0}9110\u{00A0}§\u{00A0}4.2")
    #expect(!xref.displayLabel.contains(" "), "an ordinary space would let the chip wrap mid-label")
  }

  /// The screen and a copied selection say the same thing.
  @Test func whatIsCopiedIsWhatIsShown() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    // The rendered run is the display label plus the chip's own symbol and joiner.
    #expect(run(xref).string == Self.chipPrefix + xref.displayLabel)
    #expect([Inline.crossReference(xref)].plainText == xref.displayLabel)
  }

  /// An author's own words for a link are not a composed label, so they are left
  /// exactly as written — no chip, no restyling.
  @Test func anAuthorsOwnLinkTextIsLeftAlone() {
    let xref = CrossReference(
      target: .document(.rfc(9110), section: "4.2"), text: "the caching rules")
    #expect(xref.displayLabel == "the caching rules")
    #expect(run(xref).string == "the caching rules")
    #expect(run(xref).attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
  }

  private static let chipPrefix = "\u{FFFC}\u{2060}"

  @Test func theWholeSectionReferenceIsOneChipRun() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    let attributed = run(xref)
    var range = NSRange(location: 0, length: 0)
    let chip = attributed.attribute(
      .rfcChip, at: 0, longestEffectiveRange: &range,
      in: NSRange(location: 0, length: attributed.length))
    #expect(chip != nil, "the chip starts at the symbol, not part way through")
    #expect(range.length == attributed.length, "every character belongs to the one chip")
  }

  @Test func anAuthorTagKeepsItsBracketsAndGetsNoChip() {
    let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]")
    let attributed = run(xref)
    #expect(attributed.string == "[QUIC-TRANSPORT]")
    #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
  }

  /// `NSAttributedString` merges contiguous runs whose attribute value compares
  /// equal, so two directly adjacent chips (`[RFC9110][RFC9111]`) sharing
  /// `.rfcChip == true` would report one `effectiveRange` spanning both and draw
  /// as a single rounded rect. Each chip carries its own serial number instead.
  @Test func adjacentChipsDoNotMergeIntoOneEffectiveRange() throws {
    let first = CrossReference(target: .document(.rfc(9110), section: nil))
    let second = CrossReference(target: .document(.rfc(9111), section: nil))
    let attributed = Fixtures.inlineRun(
      [.crossReference(first), .crossReference(second)], style: style)

    // `enumerateAttribute` is what `RFCTextLayoutFragment.chipRects(at:)` uses to
    // find each chip's own piece to draw — unlike `attribute(at:effectiveRange:)`,
    // it computes the *longest* equal-value range, merging across the two chips'
    // separately-appended runs when their `.rfcChip` values compare equal.
    var pieces: [NSRange] = []
    attributed.enumerateAttribute(.rfcChip, in: NSRange(location: 0, length: attributed.length)) {
      value, range, _ in
      guard value != nil else { return }
      pieces.append(range)
    }
    #expect(
      pieces.count == 2,
      "two adjacent chips must draw as two pieces, not one merged blob: \(pieces)")
  }

  @Test func theWholeLabelStaysALinkEitherWay() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: nil))
    let attributed = run(xref)
    let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
    #expect(url.absoluteString == "rfc://9110")
  }
}
