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
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2), .rfc(3)])
    #expect(
      listed(list).rows.map(\.id.number)
        == list.rows(in: index, search: IndexSearch(index: index)).map(\.id.number))
  }

  @Test func `the library's results ignore the filter`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2)])
    #expect(listed(list).rows.map(\.id.number) == [2])
    #expect(Set(listed(list).librarySearch.map(\.id.number)) == [1, 2])
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
    #expect(again.rows.map(\.id.number) == [4, 3])
  }

  @Test func `an unsearched listing keeps no hits`() {
    #expect(listed(LibraryList(filter: .all, query: "")).hits.isEmpty)
  }

  @Test func `a list is on show only when it was made over the same index`() {
    let list = LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2)])
    let shown = listed(list, indexVersion: 3)
    #expect(shown.shows(list, indexVersion: 3))
    #expect(!shown.shows(list, indexVersion: 4))
    #expect(!shown.shows(LibraryList(filter: .all, query: "host"), indexVersion: 3))
  }

  @Test func `hits are reused for the same query over the same index`() {
    let shown = listed(
      LibraryList(filter: .bookmarks, query: "host", bookmarked: [.rfc(2)]), indexVersion: 3)
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
    var bookmarked: Set<DocumentID> {
      reads.append("bookmarked")
      return [.rfc(1)]
    }
    var recentlyRead: [DocumentID] {
      reads.append("recentlyRead")
      return [.rfc(2)]
    }
    var downloaded: Set<Int> {
      reads.append("downloaded")
      return [3]
    }
    func members(of collection: UUID) -> [Int] {
      reads.append("members")
      return [4]
    }
    func collection(named name: String) -> UUID? {
      reads.append("collection \(name)")
      return name == "Mine" ? UUID() : nil
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

  /// A query asking for the reader's data or a collection reads it, whatever the
  /// filter, and only that.
  @Test(arguments: [
    ("is:bookmarked", ["bookmarked"]),
    ("is:read", ["recentlyRead"]),
    ("sort:last-read", ["recentlyRead"]),
    ("is:offline", ["downloaded"]),
    (#"in:"Mine""#, ["collection Mine", "members"]),
    (#"in:"Gone""#, ["collection Gone"]),
    ("in:9110 status:bcp", []),
  ])
  func `a query reads the input it asks for`(query: String, inputs: [String]) {
    let sources = Sources()
    _ = LibraryList.reading(.all, query: query, options: ListOptions(), from: sources)
    #expect(sources.reads == inputs)
  }

  @Test func `what is read is what is listed from`() {
    let sources = Sources()
    #expect(
      reading(.bookmarks, from: sources)
        == LibraryList(filter: .bookmarks, query: "", bookmarked: [.rfc(1)]))
    #expect(
      reading(.downloaded, from: sources)
        == LibraryList(filter: .downloaded, query: "", downloaded: [3]))
  }
}
