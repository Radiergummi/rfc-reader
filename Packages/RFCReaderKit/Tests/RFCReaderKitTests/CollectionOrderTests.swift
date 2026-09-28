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
}
