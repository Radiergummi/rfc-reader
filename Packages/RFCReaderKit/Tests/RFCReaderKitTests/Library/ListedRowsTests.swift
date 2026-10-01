import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a tab stores of its list (#597): the rows, and the whole library's results
/// for the same query, from one search.
@Suite("Listed rows")
struct ListedRowsTests {
  private let index = RFCIndex(
    rfcs: [
      Fixtures.metadata(1, title: "Host Software", year: 1969),
      Fixtures.metadata(2, title: "Host Software Protocol", year: 1969),
      Fixtures.metadata(3, title: "Documentation Conventions", year: 1969),
      Fixtures.metadata(4, title: "Network Timetable", year: 1969),
    ],
    series: [])

  private func listed(_ list: LibraryList) -> ListedRows {
    ListedRows(list, in: index, search: IndexSearch(index: index))
  }

  @Test func `the rows are the list's own`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [2, 3])
    #expect(
      listed(list).rows.map(\.number)
        == list.rows(in: index, search: IndexSearch(index: index)).map(\.number))
  }

  @Test func `the library's results ignore the filter`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [2])
    #expect(listed(list).rows.map(\.number) == [2])
    #expect(Set(listed(list).librarySearch.map(\.number)) == [1, 2])
  }

  @Test func `an unsearched list has no library results`() {
    #expect(listed(LibraryList(filter: .all, query: "")).librarySearch.isEmpty)
  }

  @Test func `the empty listing is the whole library unsearched, with nothing in it`() {
    #expect(ListedRows.empty.list == LibraryList(filter: .all, query: ""))
    #expect(ListedRows.empty.rows.isEmpty)
  }
}

/// A list reads only the inputs its filter lists from, so a tab that observes what
/// it reads is not asked to list again for a change it does not show.
@Suite("Library list inputs")
struct LibraryListInputsTests {
  /// Records which inputs were read.
  private final class Reads {
    var names: [String] = []
  }

  private func reading(_ filter: LibraryFilter, into reads: Reads) -> LibraryList {
    LibraryList.reading(
      filter: filter, query: "", options: ListOptions(),
      bookmarked: {
        reads.names.append("bookmarked")
        return [1]
      }(),
      recentlyRead: {
        reads.names.append("recentlyRead")
        return [2]
      }(),
      downloaded: {
        reads.names.append("downloaded")
        return [3]
      }(),
      members: { _ in
        reads.names.append("members")
        return [4]
      })
  }

  @Test(arguments: [
    (LibraryFilter.bookmarks, "bookmarked"),
    (.recent, "recentlyRead"),
    (.downloaded, "downloaded"),
    (.collection(UUID()), "members"),
  ])
  func `a filter reads its own input and no other`(filter: LibraryFilter, input: String) {
    let reads = Reads()
    _ = reading(filter, into: reads)
    #expect(reads.names == [input])
  }

  @Test(arguments: [LibraryFilter.all, .standards, .workingGroup("httpbis")])
  func `a filter of the index reads none of them`(filter: LibraryFilter) {
    let reads = Reads()
    _ = reading(filter, into: reads)
    #expect(reads.names.isEmpty)
  }

  @Test func `what is read is what is listed from`() {
    let reads = Reads()
    #expect(
      reading(.bookmarks, into: reads)
        == LibraryList(filter: .bookmarks, query: "", bookmarked: [1]))
    #expect(
      reading(.downloaded, into: reads)
        == LibraryList(filter: .downloaded, query: "", downloaded: [3]))
  }
}
