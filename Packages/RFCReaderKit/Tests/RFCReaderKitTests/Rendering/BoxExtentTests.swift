import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A boxed attribute value — `VerbatimBox`, `ReferenceBox` — is one instance per
/// block or reference, carried across several storage runs: a chip is three, and a
/// verbatim block shares its decoration with its neighbor. Its extent is the
/// longest range carrying that same instance, which holds only if a Swift class
/// bridges to `isEqual:` by identity. These pin that it does, and the helper every
/// extent lookup goes through.
@Suite("Boxed attribute extents")
struct BoxExtentTests {
  /// Two blocks with equal content, each boxed on its own, and the first split into
  /// two storage runs by an attribute that differs between its halves.
  private func twoAdjacentBlocks() -> NSAttributedString {
    let content = Preformatted(kind: .artwork, text: "AAAA")
    let first = VerbatimBox(content)
    let second = VerbatimBox(content)
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: "AA", attributes: [.rfcVerbatim: first]))
    text.append(
      NSAttributedString(
        string: "AA\n", attributes: [.rfcVerbatim: first, .rfcChip: 1]))
    text.append(NSAttributedString(string: "AAAA\n", attributes: [.rfcVerbatim: second]))
    return text
  }

  @Test func `one box across two storage runs is one longest range`() {
    let text = twoAdjacentBlocks()
    var storageRun = NSRange()
    _ = text.attribute(.rfcVerbatim, at: 0, effectiveRange: &storageRun)
    #expect(storageRun == NSRange(location: 0, length: 2), "the block must span two storage runs")

    var longest = NSRange()
    _ = text.attribute(
      .rfcVerbatim, at: 0, longestEffectiveRange: &longest,
      in: NSRange(location: 0, length: text.length))
    #expect(longest == NSRange(location: 0, length: 5))
  }

  @Test func `two boxes of equal content are two longest ranges`() {
    let text = twoAdjacentBlocks()
    var longest = NSRange()
    _ = text.attribute(
      .rfcVerbatim, at: 5, longestEffectiveRange: &longest,
      in: NSRange(location: 0, length: text.length))
    #expect(longest == NSRange(location: 5, length: 5))
  }

  @Test func `a box's extent is its own block, from any character of it`() {
    let text = twoAdjacentBlocks()
    for location in 0..<5 {
      #expect(text.extent(ofBox: .rfcVerbatim, at: location) == NSRange(location: 0, length: 5))
    }
    for location in 5..<10 {
      #expect(text.extent(ofBox: .rfcVerbatim, at: location) == NSRange(location: 5, length: 5))
    }
  }

  @Test func `there is no extent where there is no box, or no character`() {
    let text = NSMutableAttributedString(string: "prose ")
    text.append(
      NSAttributedString(
        string: "RFC 9110",
        attributes: [
          .rfcReference: ReferenceBox(CrossReference(target: .document(.rfc(9110), section: nil)))
        ]))
    #expect(text.extent(ofBox: .rfcReference, at: 0) == nil)
    #expect(text.extent(ofBox: .rfcReference, at: -1) == nil)
    #expect(text.extent(ofBox: .rfcReference, at: text.length) == nil)
    #expect(text.extent(ofBox: .rfcReference, at: 6) == NSRange(location: 6, length: 8))
  }
}
