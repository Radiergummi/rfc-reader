import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Index overlay: showing, current group, pinned letter")
struct IndexOverlayTests {
  /// Two groups: letters at 100 and 200, the index ending at 300.
  static let map = IndexMap(
    range: NSRange(location: 100, length: 200),
    groups: [
      IndexMap.Group(
        label: "A", anchor: "rfc.index.u65", labelRange: NSRange(location: 100, length: 1)),
      IndexMap.Group(
        label: "B", anchor: "rfc.index.u66", labelRange: NSRange(location: 200, length: 1)),
    ],
    entries: [])

  /// Hidden text covering `ranges`, as a folding records it.
  static func hiding(_ ranges: [NSRange]) -> HiddenText {
    HiddenText(paragraphs: ranges.map { (range: $0, isHidden: true) }, length: 400)
  }

  @Test func `the index shows while the viewport meets it`() {
    #expect(Self.map.isShowing(visible: NSRange(location: 250, length: 100), hidden: HiddenText()))
    #expect(!Self.map.isShowing(visible: NSRange(location: 0, length: 100), hidden: HiddenText()))
    #expect(!Self.map.isShowing(visible: NSRange(location: 300, length: 50), hidden: HiddenText()))
  }

  @Test func `a folded index does not show, though the viewport spans it`() {
    let folded = Self.hiding([NSRange(location: 100, length: 200)])
    #expect(!Self.map.isShowing(visible: NSRange(location: 50, length: 300), hidden: folded))
  }

  @Test func `an index partly folded shows by what is left of it`() {
    let partly = Self.hiding([NSRange(location: 100, length: 50)])
    #expect(Self.map.isShowing(visible: NSRange(location: 50, length: 300), hidden: partly))
  }

  @Test func `an empty map never shows`() {
    #expect(
      !IndexMap.empty.isShowing(visible: NSRange(location: 0, length: 1000), hidden: HiddenText()))
  }

  @Test func `the current group is the last whose letter starts at or before the offset`() {
    #expect(Self.map.group(at: 99) == nil)
    #expect(Self.map.group(at: 100) == 0)
    #expect(Self.map.group(at: 199) == 0)
    #expect(Self.map.group(at: 200) == 1)
    #expect(Self.map.group(at: 10_000) == 1)
  }

  @Test func `the letter is pinned while its own label is above the top`() {
    #expect(StickyLetter.offset(currentLabelTop: -30, nextLabelTop: nil, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: nil, nextLabelTop: nil, height: 20) == 0)
  }

  @Test func `the letter hides while its own label is in view at the top`() {
    #expect(StickyLetter.offset(currentLabelTop: 0, nextLabelTop: nil, height: 20) == nil)
    #expect(StickyLetter.offset(currentLabelTop: 12, nextLabelTop: 300, height: 20) == nil)
  }

  @Test func `the next label pushes the letter up as it rises under it`() {
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 25, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 20, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 15, height: 20) == -5)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 0, height: 20) == -20)
  }
}
