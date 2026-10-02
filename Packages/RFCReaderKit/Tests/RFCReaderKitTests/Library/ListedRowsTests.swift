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

  private func listed(_ list: LibraryList, indexVersion: Int = 1) -> ListedRows {
    ListedRows(list, in: index, indexVersion: indexVersion, search: IndexSearch(index: index))
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

  @Test func `the hits of an earlier listing are listed from rather than searched again`() {
    let earlier = listed(LibraryList(filter: .all, query: "host"))
    #expect(Set(earlier.hits.map(\.number)) == [1, 2])
    // Hits the search would not find: these rows can only have come from them.
    let known = [index[4]!, index[3]!]
    let again = ListedRows(
      LibraryList(filter: .all, query: "host"), in: index, indexVersion: 1,
      search: IndexSearch(index: index), hits: known)
    #expect(again.rows.map(\.number) == [4, 3])
  }

  @Test func `an unsearched listing keeps no hits`() {
    #expect(listed(LibraryList(filter: .all, query: "")).hits.isEmpty)
  }

  @Test func `a list is on show only when it was made over the same index`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [2])
    let shown = listed(list, indexVersion: 3)
    #expect(shown.shows(list, indexVersion: 3))
    #expect(!shown.shows(list, indexVersion: 4))
    #expect(!shown.shows(LibraryList(filter: .all, query: "host"), indexVersion: 3))
  }

  @Test func `hits are reused for the same query over the same index`() {
    let shown = listed(
      LibraryList(filter: .bookmarks, query: "host", bookmarked: [2]), indexVersion: 3)
    let otherFilter = LibraryList(filter: .all, query: "host")
    #expect(
      shown.hits(for: otherFilter, indexVersion: 3)?.map(\.number) == shown.hits.map(\.number))
    #expect(shown.hits(for: otherFilter, indexVersion: 4) == nil)
    #expect(shown.hits(for: LibraryList(filter: .all, query: "software"), indexVersion: 3) == nil)
  }
}

/// A list reads only the inputs its filter lists from, so a tab that observes what
/// it reads is not asked to list again for a change it does not show.
@Suite("Library list inputs")
struct LibraryListInputsTests {
  /// Records which inputs were read.
  private final class Sources: ListSources {
    var reads: [String] = []
    var bookmarked: Set<Int> {
      reads.append("bookmarked")
      return [1]
    }
    var recentlyRead: [Int] {
      reads.append("recentlyRead")
      return [2]
    }
    var downloaded: Set<Int> {
      reads.append("downloaded")
      return [3]
    }
    func members(of collection: UUID) -> [Int] {
      reads.append("members")
      return [4]
    }
  }

  private func reading(_ filter: LibraryFilter, from sources: Sources) -> LibraryList {
    LibraryList.reading(filter, query: "", options: ListOptions(), from: sources)
  }

  @Test(arguments: [
    (LibraryFilter.bookmarks, "bookmarked"),
    (.recent, "recentlyRead"),
    (.downloaded, "downloaded"),
    (.collection(UUID()), "members"),
  ])
  func `a filter reads its own input and no other`(filter: LibraryFilter, input: String) {
    let sources = Sources()
    _ = reading(filter, from: sources)
    #expect(sources.reads == [input])
  }

  @Test(arguments: [LibraryFilter.all, .standards, .workingGroup("httpbis")])
  func `a filter of the index reads none of them`(filter: LibraryFilter) {
    let sources = Sources()
    _ = reading(filter, from: sources)
    #expect(sources.reads.isEmpty)
  }

  @Test func `what is read is what is listed from`() {
    let sources = Sources()
    #expect(
      reading(.bookmarks, from: sources)
        == LibraryList(filter: .bookmarks, query: "", bookmarked: [1]))
    #expect(
      reading(.downloaded, from: sources)
        == LibraryList(filter: .downloaded, query: "", downloaded: [3]))
  }
}
