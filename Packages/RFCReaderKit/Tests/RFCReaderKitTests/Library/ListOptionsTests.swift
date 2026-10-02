import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The iOS list's view options (#348).
@Suite("List options")
struct ListOptionsTests {
  private let rows = [9110, 7231, 2616].map { number in
    LibraryRow.rfc(Fixtures.metadata(number, obsoletedBy: number == 9110 ? [] : [.rfc(9110)]))
  }

  @Test func `the defaults change nothing`() {
    let listed = ListOptions().apply(to: rows, filter: .all, query: "")

    #expect(listed.map(\.id.number) == [9110, 7231, 2616])
  }

  @Test func `oldest first reverses a list in order of publication`() {
    let options = ListOptions(order: .oldestFirst)

    #expect(options.apply(to: rows, filter: .all, query: "").map(\.id.number) == [2616, 7231, 9110])
  }

  /// Recently Read is in reading order and a search in order of relevance:
  /// reversing either would not put the oldest first.
  @Test func `the order leaves other orders alone`() {
    let options = ListOptions(order: .oldestFirst)

    #expect(
      options.apply(to: rows, filter: .recent, query: "").map(\.id.number) == [9110, 7231, 2616])
    #expect(
      options.apply(to: rows, filter: .all, query: "http").map(\.id.number) == [9110, 7231, 2616])
  }

  @Test func `hiding the obsolete keeps what is current`() {
    let options = ListOptions(showsObsolete: false)

    #expect(options.apply(to: rows, filter: .all, query: "").map(\.id.number) == [9110])
    #expect(options.apply(to: rows, filter: .bookmarks, query: "http").map(\.id.number) == [9110])
  }

  @Test func `the order applies only where it can`() {
    #expect(ListOptions.canReorder(.all, query: ""))
    #expect(!ListOptions.canReorder(.recent, query: ""))
    #expect(!ListOptions.canReorder(.all, query: "http"))
  }

  private let dated = [
    Fixtures.metadata(2616, title: "HTTP/1.1", year: 1999),
    Fixtures.metadata(9110, title: "HTTP Semantics", year: 2022),
    Fixtures.metadata(7231, title: "HTTP/1.1 Semantics", year: 2014),
  ].map(LibraryRow.rfc)

  @Test func `a collection keeps its own order by default`() {
    let listed = ListOptions().apply(to: dated, filter: .collection(UUID()), query: "")
    #expect(listed.map(\.id.number) == [2616, 9110, 7231])
  }

  @Test func `a collection sorts by publication date, not by reversing`() {
    let collection = LibraryFilter.collection(UUID())
    let newest = ListOptions(collectionSort: .newestFirst)
      .apply(to: dated, filter: collection, query: "")
    let oldest = ListOptions(collectionSort: .oldestFirst)
      .apply(to: dated, filter: collection, query: "")
    #expect(newest.map(\.id.number) == [9110, 7231, 2616])
    #expect(oldest.map(\.id.number) == [2616, 7231, 9110])
  }

  /// A tab set to Oldest First for the library still opens a collection in its
  /// own order.
  @Test func `the library's order leaves a collection alone`() {
    let options = ListOptions(order: .oldestFirst)
    let listed = options.apply(to: dated, filter: .collection(UUID()), query: "")
    #expect(listed.map(\.id.number) == [2616, 9110, 7231])
  }

  @Test func `a searched collection stays in order of relevance`() {
    let options = ListOptions(collectionSort: .oldestFirst)
    let listed = options.apply(to: dated, filter: .collection(UUID()), query: "http")
    #expect(listed.map(\.id.number) == [2616, 9110, 7231])
  }

  @Test func `only an unsearched collection in its own order can be rearranged`() {
    let collection = LibraryFilter.collection(UUID())
    #expect(ListOptions().allowsMoving(in: collection, query: ""))
    #expect(!ListOptions().allowsMoving(in: collection, query: "quic"))
    #expect(!ListOptions(collectionSort: .newestFirst).allowsMoving(in: collection, query: ""))
    #expect(!ListOptions().allowsMoving(in: .all, query: ""))
  }
}
