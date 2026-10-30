import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Index overlay: the A–Z rail")
struct IndexRailTests {
  static let letters = (65...90).map { String(Character(Unicode.Scalar($0)!)) }

  @Test func `with room, every letter has a row of the ideal height`() {
    let rail = IndexRail(labels: ["A", "B", "C"], available: 500)
    #expect(rail.rows.map(\.text) == ["A", "B", "C"])
    #expect(rail.height == 3 * IndexRail.idealRowHeight)
    #expect(rail.rows.map(\.center) == [8, 24, 40])
  }

  @Test func `short of room, the rows shrink to fit, down to the minimum`() {
    let rail = IndexRail(labels: Self.letters, available: 26 * 13)
    #expect(rail.rows.count == 26)
    #expect(abs(rail.height - 26 * 13) < 0.001)
  }

  @Test func `shorter still, every other row is a dot, and the ends are letters`() {
    let rail = IndexRail(labels: Self.letters, available: 10 * IndexRail.minimumRowHeight)
    #expect(rail.rows.count == 9)
    #expect(rail.rows.first?.text == "A")
    #expect(rail.rows.last?.text == "Z")
    #expect(
      rail.rows.enumerated().allSatisfy {
        ($0.offset % 2 == 1) == ($0.element.text == IndexRail.dot)
      })
  }

  @Test func `a point falls on the group in its share of the rail, clamped to the ends`() {
    let rail = IndexRail(labels: ["A", "B", "C", "D"], available: 500)
    #expect(rail.group(at: -40) == 0)
    #expect(rail.group(at: 0) == 0)
    #expect(rail.group(at: 17) == 1)
    #expect(rail.group(at: 63) == 3)
    #expect(rail.group(at: 900) == 3)
  }

  @Test func `an elided rail still reaches every group by its share`() {
    let rail = IndexRail(labels: Self.letters, available: 10 * IndexRail.minimumRowHeight)
    let groups = stride(from: 0, to: rail.height, by: 1).compactMap { rail.group(at: $0) }
    #expect(Set(groups).count == 26)
  }

  @Test func `no labels make no rail`() {
    let rail = IndexRail(labels: [], available: 500)
    #expect(rail.rows.isEmpty)
    #expect(rail.group(at: 10) == nil)
  }

  @Test func `the rail sits in the trailing gutter, clear of what covers its edge`() {
    // A 1000-point view, a 712-point column: a 144-point gutter each side.
    #expect(IndexRail.centerX(viewWidth: 1000, column: 712, trailingObstruction: 0) == 928)
    #expect(IndexRail.centerX(viewWidth: 1000, column: 712, trailingObstruction: 16) == 920)
  }

  @Test func `in a gutter narrower than the rail, it keeps its width against the edge`() {
    // A 24-point gutter, 16 of it under a scroller: the rail's 18 points end at the scroller.
    #expect(IndexRail.centerX(viewWidth: 760, column: 712, trailingObstruction: 16) == 735)
  }
}
