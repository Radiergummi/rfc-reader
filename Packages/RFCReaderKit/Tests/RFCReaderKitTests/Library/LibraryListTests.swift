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

  @Test func `a series and its member both bookmarked are both found`() {
    let list = LibraryList(
      filter: .bookmarks, query: "requirement", bookmarked: [Self.bcp14, .rfc(2119)])

    #expect(ids(list) == [.rfc(2119), Self.bcp14])
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

  // MARK: - The reader's data, collections and sort in a query (#355)

  private func ids(_ list: LibraryList, in index: RFCIndex) -> [DocumentID] {
    list.rows(in: index, search: IndexSearch(index: index)).map(\.id)
  }

  /// `is:bookmarked` lists what Bookmarks does, a series row included, whatever the
  /// filter it is typed in.
  @Test func `is bookmarked lists the bookmarks`() {
    let list = LibraryList(
      filter: .all, query: "is:bookmarked", bookmarked: [.rfc(2026), Self.bcp14, .rfc(9110)])

    #expect(ids(list) == [.rfc(9110), Self.bcp14, .rfc(2026)])
  }

  @Test func `is bookmarked narrows with the rest of the query`() {
    let list = LibraryList(
      filter: .all, query: "is:bookmarked uppercase", bookmarked: [Self.bcp14, .rfc(9110)])

    #expect(ids(list) == [Self.bcp14])
  }

  @Test func `is read sorted by last read is Recently Read`() {
    let list = LibraryList(
      filter: .all, query: "is:read sort:last-read",
      recentlyRead: [.rfc(2026), Self.bcp14, .rfc(9110)])

    #expect(ids(list) == [.rfc(2026), Self.bcp14, .rfc(9110)])
  }

  @Test func `is offline lists the offline copies`() {
    let list = LibraryList(filter: .all, query: "is:offline", downloaded: [2119, 9110])

    #expect(ids(list) == [.rfc(9110), .rfc(2119)])
  }

  /// A collection by its name, whatever its case, and a document beside it: `in:` is
  /// a union.
  @Test func `in a collection lists its members`() {
    let named = LibraryList(
      filter: .all, query: #"in:"key words""#, collections: ["key words": [8174, 2119]])
    let withDocument = LibraryList(
      filter: .all, query: #"in:"Key Words" in:9110"#, collections: ["key words": [8174]])

    #expect(ids(named, in: seriesIndex) == [.rfc(8174), .rfc(2119)])
    #expect(ids(withDocument, in: seriesIndex) == [.rfc(9110), .rfc(8174)])
  }

  /// A series row is in when one of its members is in the collection, as a search
  /// finds it through any of them.
  @Test func `in a collection keeps a series row through its members`() {
    let list = LibraryList(
      filter: .bookmarks, query: #"in:"key words""#, bookmarked: [Self.bcp14, .rfc(9110)],
      collections: ["key words": [2119]])

    #expect(ids(list, in: seriesIndex) == [Self.bcp14])
  }

  /// Several kinds of the reader's data are one list, newest first.
  @Test func `a union of the reader's data is newest first`() {
    let list = LibraryList(
      filter: .all, query: "is:bookmarked,offline", bookmarked: [.rfc(2026)],
      downloaded: [9110, 2119])

    #expect(ids(list, in: seriesIndex) == [.rfc(9110), .rfc(2119), .rfc(2026)])
  }

  @Test func `sort orders a list by date`() {
    let oldest = LibraryList(filter: .all, query: "sort:oldest")
    let newest = LibraryList(filter: .all, query: "sort:newest s")

    #expect(ids(oldest, in: seriesIndex) == [.rfc(2026), .rfc(2119), .rfc(8174), .rfc(9110)])
    #expect(ids(newest, in: seriesIndex) == [.rfc(9110), .rfc(8174), .rfc(2119), .rfc(2026)])
  }

  /// A query naming something unknown lists nothing and says why, rather than more
  /// than it means.
  @Test func `a query naming something unknown lists nothing and says why`() {
    let collection = LibraryList(filter: .all, query: #"in:"Gone" status:bcp"#)
    let group = LibraryList(filter: .all, query: "wg:gone")
    let qualifier = LibraryList(filter: .all, query: "released:2024 http")

    #expect(ids(collection, in: seriesIndex).isEmpty)
    #expect(
      collection.unknownTerms(in: seriesIndex)
        == [UnknownSearchTerm(word: #"in:"Gone""#, reason: .collection)])
    #expect(ids(group, in: seriesIndex).isEmpty)
    #expect(group.unknownTerms(in: seriesIndex).map(\.reason) == [.workingGroup])
    #expect(ids(qualifier, in: seriesIndex).isEmpty)
    #expect(qualifier.unknownTerms(in: seriesIndex).map(\.reason) == [.qualifier])
  }

  // MARK: - Dynamic collections (#355)

  /// What its query lists in the whole library, whatever members it once had.
  @Test func `a dynamic collection lists what its query matches`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "", bookmarked: [.rfc(2026), Self.bcp14, .rfc(9110)],
      members: [2119], definition: "is:bookmarked")

    #expect(ids(list) == [.rfc(9110), Self.bcp14, .rfc(2026)])
  }

  /// A search typed into its tab narrows what its query matches, as both were one.
  @Test func `a search in a dynamic collection narrows what its query matches`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "uppercase",
      bookmarked: [Self.bcp14, .rfc(9110)], definition: "is:bookmarked")

    #expect(ids(list) == [Self.bcp14])
  }

  @Test func `a dynamic collection naming something unknown lists nothing and says why`() {
    let list = LibraryList(filter: .collection(UUID()), query: "", definition: "wg:gone")

    #expect(ids(list).isEmpty)
    #expect(list.unknownTerms(in: seriesIndex).map(\.reason) == [.workingGroup])
  }

  /// In the order of publication, as the whole library is, which View Options turns
  /// round: it has no order of its own to keep.
  @Test func `a dynamic collection is newest first, and oldest first reverses it`() {
    let newest = LibraryList(filter: .collection(UUID()), query: "", definition: "s")
    let oldest = LibraryList(
      filter: .collection(UUID()), query: "",
      options: ListOptions(order: .oldestFirst, collectionSort: .manual), definition: "s")

    #expect(ids(newest) == [.rfc(9110), .rfc(8174), .rfc(2119), .rfc(2026)])
    #expect(ids(oldest) == [.rfc(2026), .rfc(2119), .rfc(8174), .rfc(9110)])
  }

  /// A collection made from a query has no members to search in, so `in:` naming one
  /// is an unknown term rather than a list that is silently empty (answered on #355,
  /// 2026-10-17).
  @Test func `in a dynamic collection lists nothing and says why`() {
    let list = LibraryList(
      filter: .all, query: #"in:"QUIC" in:9110"#, dynamicCollections: ["quic"])

    #expect(ids(list, in: seriesIndex).isEmpty)
    #expect(
      list.unknownTerms(in: seriesIndex) == [
        UnknownSearchTerm(word: #"in:"QUIC""#, reason: .dynamicCollection)
      ])
  }

  /// A query that orders the collection orders it whatever View Options says.
  @Test func `a dynamic collection's own sort is not reversed`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "",
      options: ListOptions(order: .oldestFirst, collectionSort: .manual),
      definition: "s sort:newest")

    #expect(ids(list) == [.rfc(9110), .rfc(8174), .rfc(2119), .rfc(2026)])
  }

  /// A collection's query that leaves a quote open would otherwise take the tab's
  /// words into its last value, and the search would change the collection rather
  /// than narrow it.
  @Test func `a dynamic collection's open quote does not take the tab's search`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "cache", definition: #"by:"Fielding"#)

    #expect(SearchQuery.words(in: list.searchedQuery) == [#"by:"Fielding""#, "cache"])
  }

  /// View Options offers the order where it turns the list round: not where the
  /// collection's own query sorts it.
  @Test func `a dynamic collection can be reordered unless its query sorts it`() {
    let collection = LibraryFilter.collection(UUID())

    #expect(LibraryList.canReorder(collection, definition: "s", query: ""))
    #expect(!LibraryList.canReorder(collection, definition: "s sort:newest", query: ""))
    #expect(!LibraryList.canReorder(collection, definition: "s", query: "uppercase"))
    #expect(!LibraryList.canReorder(collection, definition: nil, query: ""))
  }

  /// Its rows are matched, not placed, so there is no order to drag them into.
  @Test func `a dynamic collection's rows cannot be moved`() {
    let manual = LibraryList(filter: .collection(UUID()), query: "", members: [2119])
    let dynamic = LibraryList(filter: .collection(UUID()), query: "", definition: "s")

    #expect(manual.allowsMoving)
    #expect(!dynamic.allowsMoving)
  }

  @Test func `a field of only spaces and newlines is unsearched`() {
    #expect(" \t\n".isUnsearchedQuery)
    #expect("".isUnsearchedQuery)
    #expect(!" host ".isUnsearchedQuery)
    #expect(" host \n".normalizedQuery == "host")
  }
}

/// The library's defaults (#713) through a whole list.
@Suite("Library list: defaults")
struct LibraryListDefaultsTests {
  private let index = RFCIndex(
    rfcs: [
      Fixtures.metadata(1149, title: "Avian Carriers", year: 1990),
      Fixtures.metadata(2616, title: "HTTP/1.1", year: 1999, obsoletedBy: [.rfc(9110)]),
      Fixtures.metadata(9110, title: "HTTP Semantics", year: 2022),
    ],
    series: [])

  private func numbers(_ list: LibraryList) -> [Int] {
    list.rows(in: index, search: IndexSearch(index: index)).map(\.id.number)
  }

  private let hidingJokes = ListOptions(showsAprilFirst: false)

  @Test func `a hidden april 1st RFC leaves the library and its search`() {
    #expect(numbers(LibraryList(filter: .all, query: "", options: hidingJokes)) == [9110, 2616])
    #expect(numbers(LibraryList(filter: .all, query: "avian", options: hidingJokes)).isEmpty)
  }

  @Test func `a bookmarked april 1st RFC stays listed`() {
    let list = LibraryList(
      filter: .bookmarks, query: "", bookmarked: [.rfc(1149)], options: hidingJokes)
    #expect(numbers(list) == [1149])
    let searched = LibraryList(
      filter: .all, query: "is:bookmarked", bookmarked: [.rfc(1149)], options: hidingJokes)
    #expect(numbers(searched) == [1149])
  }

  @Test func `a collected april 1st RFC stays listed`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "", options: hidingJokes, members: [1149, 9110])
    #expect(numbers(list) == [1149, 9110])
    let searched = LibraryList(
      filter: .all, query: "in:jokes", options: hidingJokes, collections: ["jokes": [1149]])
    #expect(numbers(searched) == [1149])
  }

  // MARK: - Dynamic collections (#355)

  private let research = RFCIndex(
    rfcs: [
      Fixtures.metadata(1945, title: "HTTP/1.0", currentStatus: .historic, stream: .ietf),
      Fixtures.metadata(9000, title: "HTTP research", stream: .irtf),
    ],
    series: [])

  private func numbers(_ list: LibraryList, in index: RFCIndex) -> [Int] {
    list.rows(in: index, search: IndexSearch(index: index)).map(\.id.number)
  }

  /// A dynamic collection's own `stream:` is where the reader chose to look, as a
  /// stream's list is: the default search stream would leave its search empty.
  @Test func `a dynamic collection's stream lifts the search scope's`() {
    let options = ListOptions(searchScope: SearchScope(stream: .ietf))
    let list = LibraryList(
      filter: .collection(UUID()), query: "http", options: options, definition: "stream:irtf")

    #expect(numbers(list, in: research) == [9000])
    #expect(
      options.scopeInForce(query: "http", filter: list.filter, definition: "stream:irtf")
        .isEverything)
  }

  @Test func `a dynamic collection's status lifts current only`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true))
    let list = LibraryList(
      filter: .collection(UUID()), query: "http", options: options,
      definition: "status:historic")

    #expect(numbers(list, in: research) == [1945])
  }

  /// A dynamic collection is the reader's own, as a collection of members is.
  @Test func `a dynamic collection keeps its april 1st RFCs`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "", options: hidingJokes, definition: "avian")
    #expect(numbers(list) == [1149])
    let searched = LibraryList(
      filter: .collection(UUID()), query: "carriers", options: hidingJokes, definition: "avian")
    #expect(numbers(searched) == [1149])
  }

  @Test func `hide read reads what was read, and leaves it out`() {
    struct Sources: ListSources {
      var bookmarked: Set<DocumentID> { [] }
      var recentlyRead: [DocumentID] { [.rfc(9110)] }
      var downloaded: Set<Int> { [] }
      func members(of collection: UUID) -> [Int] { [] }
      func collection(named name: String) -> UUID? { nil }
      func query(of collection: UUID) -> String? { nil }
    }
    let list = LibraryList.reading(
      .all, query: "", options: ListOptions(hidesRead: true), from: Sources())
    #expect(numbers(list) == [2616, 1149])
    // Without the option, the read documents are not read at all.
    let unhidden = LibraryList.reading(.all, query: "", options: ListOptions(), from: Sources())
    #expect(unhidden.recentlyRead.isEmpty)
  }

  @Test func `current only hides the obsoleted from a search, not from the list`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true))
    #expect(numbers(LibraryList(filter: .all, query: "http", options: options)) == [9110])
    #expect(numbers(LibraryList(filter: .all, query: "", options: options)) == [9110, 2616, 1149])
  }
}
