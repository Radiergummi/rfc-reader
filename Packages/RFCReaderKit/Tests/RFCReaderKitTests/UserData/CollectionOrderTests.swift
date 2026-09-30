import Foundation
import Testing

@testable import RFCReaderKit

/// Where rows sit in a collection and collections in the sidebar (#349).
@Suite("Collection order")
struct CollectionOrderTests {
  @Test func `the first row goes at one spacing`() {
    #expect(CollectionOrder.appending(after: nil) == CollectionOrder.spacing)
  }

  @Test func `a new row goes one spacing after the last`() {
    #expect(CollectionOrder.appending(after: 3) == 3 + CollectionOrder.spacing)
  }

  @Test func `a move between two neighbors takes their midpoint`() {
    #expect(CollectionOrder.placement(between: 1, and: 2) == .position(1.5))
  }

  @Test func `a move to either end steps one spacing past the end`() {
    #expect(
      CollectionOrder.placement(between: nil, and: 1) == .position(1 - CollectionOrder.spacing))
    #expect(
      CollectionOrder.placement(between: 4, and: nil) == .position(4 + CollectionOrder.spacing))
    #expect(CollectionOrder.placement(between: nil, and: nil) == .position(CollectionOrder.spacing))
  }

  /// Two devices appending offline both write "after the last".
  @Test func `equal neighbors call for a renumber`() {
    #expect(CollectionOrder.placement(between: 2, and: 2) == .renumberFirst)
  }

  @Test func `a gap too narrow to split calls for a renumber`() {
    let before = 1.0
    let after = before + CollectionOrder.minimumGap / 2
    #expect(CollectionOrder.placement(between: before, and: after) == .renumberFirst)
  }

  @Test func `renumbering spaces rows evenly in their order`() {
    #expect(
      CollectionOrder.renumbered(count: 3) == [1, 2, 3].map { $0 * CollectionOrder.spacing })
    #expect(CollectionOrder.renumbered(count: 0).isEmpty)
  }

  /// Obsolete documents hidden: the drop lands after the visible row above it,
  /// not somewhere among the hidden rows beyond it.
  @Test func `a drop below a visible row lands right after it`() {
    let full = ["a", "hidden", "b"]
    let neighbors = CollectionOrder.neighbors(above: "a", below: "b", in: full)
    #expect(neighbors.before == "a")
    #expect(neighbors.after == "hidden")
  }

  /// The list pages its rows in (`ListWindow`): a drop at the end of what is on
  /// screen lands after the last visible row, ahead of the rows not paged in yet.
  @Test func `a drop at the end of the window lands ahead of unpaged rows`() {
    let full = ["a", "b", "unpaged"]
    let neighbors = CollectionOrder.neighbors(above: "b", below: nil, in: full)
    #expect(neighbors.before == "b")
    #expect(neighbors.after == "unpaged")
  }

  @Test func `a drop at the top lands right before the visible row below it`() {
    let full = ["hidden", "a", "b"]
    let neighbors = CollectionOrder.neighbors(above: nil, below: "a", in: full)
    #expect(neighbors.before == "hidden")
    #expect(neighbors.after == "a")
  }

  @Test func `a drop into an empty list lands first`() {
    let neighbors = CollectionOrder.neighbors(above: nil, below: nil, in: ["a"])
    #expect(neighbors.before == nil)
    #expect(neighbors.after == "a")
  }

  /// `List.onMove` reports the offset the row is dropped *before*, counted before
  /// the row is taken out: dragging the first of four rows below the third is a
  /// drop at 3.
  @Test func `a drag down lands between the rows it was dropped between`() {
    let drop = CollectionOrder.drop(from: [0], to: 3, in: ["a", "b", "c", "d"])
    #expect(drop?.moved == "a")
    #expect(drop?.above == "c")
    #expect(drop?.below == "d")
  }

  @Test func `a drag up to the top has nothing above it`() {
    let drop = CollectionOrder.drop(from: [3], to: 0, in: ["a", "b", "c", "d"])
    #expect(drop?.moved == "d")
    #expect(drop?.above == nil)
    #expect(drop?.below == "a")
  }

  @Test func `a drag to the end has nothing below it`() {
    let drop = CollectionOrder.drop(from: [0], to: 4, in: ["a", "b", "c", "d"])
    #expect(drop?.moved == "a")
    #expect(drop?.above == "d")
    #expect(drop?.below == nil)
  }

  @Test func `a drag of nothing, or from outside the rows, is no drop`() {
    #expect(CollectionOrder.drop(from: [], to: 1, in: ["a", "b"]) == nil)
    #expect(CollectionOrder.drop(from: [5], to: 1, in: ["a", "b"]) == nil)
  }

  /// VoiceOver's Move Up and Move Down.
  @Test func `a step moves one row past its neighbor`() {
    let downward = CollectionOrder.step("b", by: 1, in: ["a", "b", "c"])
    #expect(downward?.moved == "b")
    #expect(downward?.above == "c")
    #expect(downward?.below == nil)

    let upward = CollectionOrder.step("b", by: -1, in: ["a", "b", "c"])
    #expect(upward?.above == nil)
    #expect(upward?.below == "a")
  }

  @Test func `a step past either end is no drop`() {
    #expect(CollectionOrder.step("a", by: -1, in: ["a", "b"]) == nil)
    #expect(CollectionOrder.step("b", by: 1, in: ["a", "b"]) == nil)
    #expect(CollectionOrder.step("z", by: 1, in: ["a", "b"]) == nil)
  }
}
