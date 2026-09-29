import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a library list shows for its filter, query and options.
@Suite("Library list")
struct LibraryListTests {
  private let index = RFCIndex(
    rfcs: [
      Fixtures.metadata(1, title: "Host Software", year: 1969),
      Fixtures.metadata(2, title: "Host Software Protocol", year: 1969),
      Fixtures.metadata(3, title: "Documentation Conventions", year: 1969),
      Fixtures.metadata(4, title: "Network Timetable", year: 1969),
    ],
    series: [
      SeriesEntry(id: DocumentID(series: .bcp, number: 1), members: [.rfc(3), .rfc(1)])
    ])

  private func numbers(_ list: LibraryList, searching: Bool = true) -> [Int] {
    list.rows(in: index, search: searching ? IndexSearch(index: index) : nil).map(\.number)
  }

  @Test func `the whole library is newest first`() {
    #expect(numbers(LibraryList(filter: .all, query: "")) == [4, 3, 2, 1])
  }

  @Test func `oldest first reverses a list in order of publication`() {
    let list = LibraryList(filter: .all, query: "", options: ListOptions(order: .oldestFirst))
    #expect(numbers(list) == [1, 2, 3, 4])
  }

  @Test func `bookmarks and offline copies are newest first, whatever order they were given in`() {
    #expect(
      numbers(LibraryList(filter: .bookmarks, query: "", bookmarked: [1, 4, 2])) == [4, 2, 1])
    #expect(numbers(LibraryList(filter: .downloaded, query: "", downloaded: [3, 1])) == [3, 1])
  }

  @Test func `recently read and a collection keep their own order`() {
    #expect(
      numbers(LibraryList(filter: .recent, query: "", recentlyRead: [2, 4, 1])) == [2, 4, 1])
    let collection = LibraryList(filter: .collection(UUID()), query: "", members: [3, 1, 4])
    #expect(numbers(collection) == [3, 1, 4])
  }

  @Test func `a series lists its members in its own order`() {
    let series = LibraryList(filter: .series(DocumentID(series: .bcp, number: 1)), query: "")
    #expect(numbers(series) == [3, 1])
  }

  @Test func `a number the index does not know is left out`() {
    #expect(numbers(LibraryList(filter: .bookmarks, query: "", bookmarked: [9999, 2])) == [2])
  }

  @Test func `a search inside a filter finds only what the filter lists`() {
    let all = Set(numbers(LibraryList(filter: .all, query: "host")))
    #expect(all == [1, 2])
    let bookmarks = LibraryList(filter: .bookmarks, query: "host", bookmarked: [2, 3])
    #expect(numbers(bookmarks) == [2])
  }

  @Test func `without a search index a query leaves the filter's list as it is`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [2, 3])
    #expect(numbers(list, searching: false) == [3, 2])
  }

  @Test func `a query differing only in the spaces around it is the same list`() {
    #expect(
      LibraryList(filter: .all, query: "  host \n") == LibraryList(filter: .all, query: "host"))
  }

  @Test func `a field of only spaces and newlines is unsearched`() {
    #expect(" \t\n".isUnsearchedQuery)
    #expect("".isUnsearchedQuery)
    #expect(!" host ".isUnsearchedQuery)
    #expect(" host \n".normalizedQuery == "host")
  }
}
