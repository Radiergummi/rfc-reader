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
    list.rows(in: index, search: searching ? IndexSearch(index: index) : nil).map(\.id.number)
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
      numbers(LibraryList(filter: .bookmarks, query: "", bookmarked: [.rfc(1), .rfc(4), .rfc(2)]))
        == [4, 2, 1])
    #expect(numbers(LibraryList(filter: .downloaded, query: "", downloaded: [3, 1])) == [3, 1])
  }

  @Test func `recently read and a collection keep their own order`() {
    #expect(
      numbers(LibraryList(filter: .recent, query: "", recentlyRead: [.rfc(2), .rfc(4), .rfc(1)]))
        == [2, 4, 1])
    let collection = LibraryList(filter: .collection(UUID()), query: "", members: [3, 1, 4])
    #expect(numbers(collection) == [3, 1, 4])
  }

  @Test func `a series lists its members in its own order`() {
    let series = LibraryList(filter: .series(DocumentID(series: .bcp, number: 1)), query: "")
    #expect(numbers(series) == [3, 1])
  }

  @Test func `a number the index does not know is left out`() {
    #expect(
      numbers(LibraryList(filter: .bookmarks, query: "", bookmarked: [.rfc(9999), .rfc(2)])) == [2])
  }

  @Test func `a search inside a filter finds only what the filter lists`() {
    let all = Set(numbers(LibraryList(filter: .all, query: "host")))
    #expect(all == [1, 2])
    let bookmarks = LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2), .rfc(3)])
    #expect(numbers(bookmarks) == [2])
  }

  @Test func `without a search index a query leaves the filter's list as it is`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2), .rfc(3)])
    #expect(numbers(list, searching: false) == [3, 2])
  }

  @Test func `a query differing only in the spaces around it is the same list`() {
    #expect(
      LibraryList(filter: .all, query: "  host \n") == LibraryList(filter: .all, query: "host"))
  }

  // MARK: - A bookmarked or read BCP, STD or FYI (#321)

  private static let bcp14 = DocumentID(series: .bcp, number: 14)

  private let seriesIndex = RFCIndex(
    rfcs: [
      Fixtures.metadata(2026, title: "The Standards Process", year: 1996, month: 10),
      Fixtures.metadata(2119, title: "Requirement Levels", year: 1997, month: 3),
      Fixtures.metadata(8174, title: "Uppercase Key Words", year: 2017, month: 5),
      Fixtures.metadata(9110, title: "HTTP Semantics", year: 2022, month: 6),
    ],
    series: [SeriesEntry(id: bcp14, members: [.rfc(2119), .rfc(8174)])])

  private func ids(_ list: LibraryList) -> [DocumentID] {
    list.rows(in: seriesIndex, search: IndexSearch(index: seriesIndex)).map(\.id)
  }

  @Test func `a bookmarked series is a row of its own, for the document bookmarked`() {
    let rows = LibraryList(filter: .bookmarks, query: "", bookmarked: [Self.bcp14])
      .rows(in: seriesIndex, search: nil)

    #expect(rows.map(\.id) == [Self.bcp14])
    #expect(rows.first?.members.map(\.number) == [2119, 8174])
  }

  @Test func `a bookmarked series sorts by its newest member's date`() {
    let list = LibraryList(
      filter: .bookmarks, query: "", bookmarked: [.rfc(2026), Self.bcp14, .rfc(9110)])

    #expect(ids(list) == [.rfc(9110), Self.bcp14, .rfc(2026)])
  }

  @Test func `a read series keeps its place in reading order`() {
    let list = LibraryList(
      filter: .recent, query: "", recentlyRead: [.rfc(2026), Self.bcp14, .rfc(9110)])

    #expect(ids(list) == [.rfc(2026), Self.bcp14, .rfc(9110)])
  }

  @Test func `a search finds a series row through any of its members`() {
    let bookmarks = LibraryList(
      filter: .bookmarks, query: "uppercase", bookmarked: [Self.bcp14, .rfc(9110)])
    let recent = LibraryList(
      filter: .recent, query: "requirement", recentlyRead: [.rfc(9110), Self.bcp14])

    #expect(ids(bookmarks) == [Self.bcp14])
    #expect(ids(recent) == [Self.bcp14])
  }

  @Test func `a series the index does not know is left out`() {
    let unknown = DocumentID(series: .std, number: 99)
    let list = LibraryList(filter: .bookmarks, query: "", bookmarked: [unknown, .rfc(9110)])

    #expect(ids(list) == [.rfc(9110)])
  }

  @Test func `hiding the obsolete keeps a series row`() {
    let list = LibraryList(
      filter: .bookmarks, query: "", bookmarked: [Self.bcp14],
      options: ListOptions(showsObsolete: false))

    #expect(ids(list) == [Self.bcp14])
  }

  @Test func `a field of only spaces and newlines is unsearched`() {
    #expect(" \t\n".isUnsearchedQuery)
    #expect("".isUnsearchedQuery)
    #expect(!" host ".isUnsearchedQuery)
    #expect(" host \n".normalizedQuery == "host")
  }
}
