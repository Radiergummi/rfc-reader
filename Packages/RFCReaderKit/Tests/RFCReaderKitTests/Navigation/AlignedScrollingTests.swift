import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Aligned scrolling")
struct AlignedScrollingTests {
  private let old = DocumentID.rfc(7231)
  private let new = DocumentID.rfc(9110)
  private let elsewhere = DocumentID.rfc(9112)

  /// 7231 has sections 1 (100–300), 2 (300–500) and 3 (500–700), and ends at 800.
  private var oldSide: AlignedScrolling.Side {
    AlignedScrolling.Side(
      document: old,
      sections: AnchorIndex([
        .init(anchor: "old-1", offset: 100, heading: "1. One"),
        .init(anchor: "old-2", offset: 300, heading: "2. Two"),
        .init(anchor: "old-3", offset: 500, heading: "3. Three"),
      ]),
      length: 800)
  }

  /// 9110 has sections 1 (50–450), 2 (450–1050) and 3 (1050–1200), and ends there.
  private var newSide: AlignedScrolling.Side {
    AlignedScrolling.Side(
      document: new,
      sections: AnchorIndex([
        .init(anchor: "new-1", offset: 50, heading: "1. Eins"),
        .init(anchor: "new-2", offset: 450, heading: "2. Zwei"),
        .init(anchor: "new-3", offset: 1050, heading: "3. Drei"),
      ]),
      length: 1200)
  }

  private func row(_ oldSection: String, _ newSection: String, score: Double = 0.5)
    -> AlignedSection
  {
    AlignedSection(old: old, oldSection: oldSection, new: new, newSection: newSection, score: score)
  }

  @Test func `a place lands as far through the counterpart as it is through its section`() {
    let scrolling = AlignedScrolling(rows: [row("old-2", "new-2")], between: old, and: new)
    // A quarter of the way through 7231 §2 is a quarter of the way through 9110 §2.
    #expect(scrolling.follow(350, from: oldSide, to: newSide) == .offset(600))
  }

  @Test func `either side can lead`() {
    let scrolling = AlignedScrolling(rows: [row("old-2", "new-2")], between: old, and: new)
    #expect(scrolling.follow(600, from: newSide, to: oldSide) == .offset(350))
  }

  @Test func `the last section runs to the end of its document`() {
    let scrolling = AlignedScrolling(rows: [row("old-3", "new-3")], between: old, and: new)
    // Halfway through 500–800 is halfway through 1050–1200.
    #expect(scrolling.follow(650, from: oldSide, to: newSide) == .offset(1125))
  }

  @Test func `a section without a counterpart holds the other side still`() {
    let scrolling = AlignedScrolling(rows: [row("old-2", "new-2")], between: old, and: new)
    #expect(scrolling.follow(120, from: oldSide, to: newSide) == .unaligned(section: "old-1"))
  }

  @Test func `ahead of the first section the other side goes to its top`() {
    let scrolling = AlignedScrolling(rows: [row("old-1", "new-1")], between: old, and: new)
    #expect(scrolling.follow(40, from: oldSide, to: newSide) == .top)
    #expect(scrolling.follow(nil, from: oldSide, to: newSide) == .top)
  }

  @Test func `a section split in two follows its best match`() {
    let scrolling = AlignedScrolling(
      rows: [row("old-2", "new-2", score: 0.4), row("old-2", "new-3", score: 0.7)],
      between: old, and: new)
    #expect(scrolling.follow(300, from: oldSide, to: newSide) == .offset(1050))
  }

  @Test func `rows of another document are not this pair's`() {
    // 7230's rows with 9112 are aligned alongside, so that they are not taken for
    // 9110's; they are no counterpart in 9110.
    let other = AlignedSection(
      old: old, oldSection: "old-1", new: elsewhere, newSection: "new-1", score: 0.9)
    let scrolling = AlignedScrolling(rows: [other], between: old, and: new)
    #expect(scrolling.follow(120, from: oldSide, to: newSide) == .unaligned(section: "old-1"))
  }

  @Test func `a counterpart the other build lacks holds still`() {
    let scrolling = AlignedScrolling(rows: [row("old-2", "gone")], between: old, and: new)
    #expect(scrolling.follow(350, from: oldSide, to: newSide) == .unaligned(section: "old-2"))
  }

  @Test func `the counterpart of a section is its best match on the other side`() {
    let scrolling = AlignedScrolling(
      rows: [row("old-2", "new-2", score: 0.4), row("old-3", "new-2", score: 0.6)],
      between: old, and: new)
    #expect(scrolling.counterpart(of: "old-2", in: old) == "new-2")
    #expect(scrolling.counterpart(of: "new-2", in: new) == "old-3")
    #expect(scrolling.counterpart(of: "old-1", in: old) == nil)
  }
}
