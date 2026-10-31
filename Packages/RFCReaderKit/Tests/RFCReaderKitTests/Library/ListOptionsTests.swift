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

    #expect(
      options.apply(to: rows, filter: .all, query: "").map(\.id.number) == [2616, 7231, 9110])
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
    let options = ListOptions(showsObsolete: false, showsObsoleteInSearch: false)

    #expect(options.apply(to: rows, filter: .all, query: "").map(\.id.number) == [9110])
    #expect(options.apply(to: rows, filter: .bookmarks, query: "http").map(\.id.number) == [9110])
  }

  /// Settings has a default for each (#713), and a tab's toggle says which it changes.
  @Test func `lists and searches show the obsolete separately`() {
    let inLists = ListOptions(showsObsolete: false)
    #expect(inLists.apply(to: rows, filter: .all, query: "").map(\.id.number) == [9110])
    #expect(inLists.apply(to: rows, filter: .all, query: "http").count == 3)

    let inSearch = ListOptions(showsObsoleteInSearch: false)
    #expect(inSearch.apply(to: rows, filter: .all, query: "").count == 3)
    #expect(inSearch.apply(to: rows, filter: .all, query: "http").map(\.id.number) == [9110])
  }

  @Test func `the toggle changes the flag of what is on show`() {
    var options = ListOptions()
    options.setShowsObsolete(false, searching: true)
    #expect(options.showsObsolete && !options.showsObsoleteInSearch)
    #expect(!options.showsObsolete(searching: true))
    options.setShowsObsolete(false, searching: false)
    #expect(!options.showsObsolete)
    #expect(!options.showsObsolete(searching: false))
  }

  // MARK: - Hide Read (#713)

  @Test func `hide read leaves out what was read`() {
    let options = ListOptions(hidesRead: true)
    let read: Set<DocumentID> = [.rfc(7231)]

    #expect(
      options.apply(to: rows, filter: .all, query: "", read: read).map(\.id.number) == [9110, 2616])
    #expect(
      options.apply(to: rows, filter: .bookmarks, query: "http", read: read).map(\.id.number)
        == [9110, 2616])
  }

  /// Recently Read is what was read, and `is:read` asks for it: hiding it there
  /// would leave nothing.
  @Test func `hide read leaves what asks for the read alone`() {
    let options = ListOptions(hidesRead: true)
    let read: Set<DocumentID> = [.rfc(7231)]

    #expect(options.apply(to: rows, filter: .recent, query: "", read: read).count == 3)
    #expect(options.apply(to: rows, filter: .all, query: "is:read", read: read).count == 3)
  }

  /// A dynamic collection made from `is:read` asks for the read as the query does.
  @Test func `hide read leaves a dynamic collection of the read alone`() {
    let options = ListOptions(hidesRead: true)
    let read: Set<DocumentID> = [.rfc(7231)]

    #expect(
      options.apply(
        to: rows, filter: .collection(UUID()), query: "", read: read, definition: "is:read"
      ).count == 3)
  }

  // MARK: - A list the options empty (#937)

  /// The obsolete rows: 7231 and 2616, which 9110 obsoletes.
  private var obsoleteRows: [LibraryRow] { Array(rows.dropFirst()) }

  @Test func `a list with rows on show hides nothing`() {
    let options = ListOptions(showsObsolete: false, hidesRead: true)
    #expect(options.hiding(rows, filter: .bookmarks, query: "").isEmpty)
  }

  @Test func `an empty list is not hidden`() {
    let options = ListOptions(showsObsolete: false, hidesRead: true)
    #expect(options.hiding([], filter: .bookmarks, query: "").isEmpty)
  }

  @Test func `every row obsolete is hidden by show obsolete`() {
    let options = ListOptions(showsObsolete: false)
    #expect(options.hiding(obsoleteRows, filter: .bookmarks, query: "") == .obsolete)
  }

  @Test func `every row read is hidden by hide read`() {
    let options = ListOptions(hidesRead: true)
    let read = Set(rows.map(\.id))
    #expect(options.hiding(rows, filter: .bookmarks, query: "", read: read) == .read)
  }

  /// Either option alone lists one of the rows, so each is a way to show them.
  @Test func `rows hidden some by each option name both`() {
    let options = ListOptions(showsObsolete: false, hidesRead: true)
    let read: Set<DocumentID> = [.rfc(9110)]
    #expect(options.hiding(rows, filter: .bookmarks, query: "", read: read) == [.obsolete, .read])
  }

  /// Neither option alone lists a row, so it takes both.
  @Test func `rows hidden by both options at once name both`() {
    let options = ListOptions(showsObsolete: false, hidesRead: true)
    let read: Set<DocumentID> = [.rfc(7231), .rfc(2616)]
    #expect(
      options.hiding(obsoleteRows, filter: .bookmarks, query: "", read: read) == [.obsolete, .read])
  }

  /// Hide Read leaves Recently Read alone, so it is never what empties it.
  @Test func `only an option in force is named`() {
    let options = ListOptions(showsObsolete: false, hidesRead: true)
    let read = Set(rows.map(\.id))
    #expect(options.hiding(obsoleteRows, filter: .recent, query: "", read: read) == .obsolete)
  }

  /// A search shows the obsolete by its own option, which is the one to name.
  @Test func `a search is hidden by its own obsolete option`() {
    #expect(
      ListOptions(showsObsolete: false).hiding(obsoleteRows, filter: .all, query: "http").isEmpty)
    #expect(
      ListOptions(showsObsoleteInSearch: false).hiding(obsoleteRows, filter: .all, query: "http")
        == .obsolete)
  }

  @Test(arguments: [
    (
      ListOptions.Hidden.obsolete, "Every RFC in this list is obsolete, and Show Obsolete is off."
    ),
    (.read, "You have read every RFC in this list, and Hide Read is on."),
    ([.obsolete, .read], "Show Obsolete is off and Hide Read is on, which hide every RFC in this list."),
  ])
  func `the empty state says what hides the rows`(hidden: ListOptions.Hidden, sentence: String) {
    #expect(hidden.title(locale: .english) == "Hidden by View Options")
    #expect(hidden.description(locale: .english) == sentence)
  }

  // MARK: - April 1st RFCs (#713)

  private let jokes = [9110, 2549, 1149].map { LibraryRow.rfc(Fixtures.metadata($0)) }

  @Test func `april 1st RFCs are shown by default`() {
    #expect(ListOptions().apply(to: jokes, filter: .all, query: "").count == 3)
  }

  @Test func `turned off, april 1st RFCs leave the index's lists and searches`() {
    let options = ListOptions(showsAprilFirst: false)

    for filter in [LibraryFilter.all, .stream(.legacy), .workingGroup("none"), .standards] {
      #expect(options.apply(to: jokes, filter: filter, query: "").map(\.id.number) == [9110])
    }
    #expect(options.apply(to: jokes, filter: .all, query: "avian").map(\.id.number) == [9110])
  }

  /// Hiding never breaks a link, a bookmark or a collection.
  @Test func `turned off, april 1st RFCs stay in the reader's own lists`() {
    let options = ListOptions(showsAprilFirst: false)

    for filter in [LibraryFilter.bookmarks, .recent, .downloaded, .collection(UUID())] {
      #expect(options.apply(to: jokes, filter: filter, query: "").count == 3)
      #expect(options.apply(to: jokes, filter: filter, query: "avian").count == 3)
    }
    #expect(options.apply(to: jokes, filter: .all, query: "is:bookmarked").count == 3)
    #expect(options.apply(to: jokes, filter: .all, query: "in:rfc1149").count == 3)
  }

  // MARK: - The default search scope (#713)

  @Test func `the search scope narrows a search`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true))

    #expect(options.apply(to: rows, filter: .all, query: "http").map(\.id.number) == [9110])
    #expect(options.apply(to: rows, filter: .bookmarks, query: "http").map(\.id.number) == [9110])
  }

  @Test func `the search scope leaves an unsearched list alone`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true))

    #expect(options.apply(to: rows, filter: .all, query: "").count == 3)
  }

  @Test func `a query naming its own status wins over the search scope`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true))

    #expect(options.apply(to: rows, filter: .all, query: "http status:std").count == 3)
  }

  @Test func `the scope in force is the one a query leaves`() {
    let options = ListOptions(searchScope: SearchScope(currentOnly: true, stream: .ietf))

    #expect(options.scopeInForce(query: "", filter: .all).isEverything)
    #expect(
      options.scopeInForce(query: "http", filter: .all)
        == SearchScope(currentOnly: true, stream: .ietf))
    #expect(
      options.scopeInForce(query: "http stream:irtf", filter: .all)
        == SearchScope(currentOnly: true))
  }

  /// A list of one stream, or of one group, is where the reader chose to look: the
  /// scope's stream would leave a search there with nothing.
  @Test func `the search scope's stream gives way to a list of one stream or group`() {
    let options = ListOptions(searchScope: SearchScope(stream: .ietf))
    let research = [LibraryRow.rfc(Fixtures.metadata(9000, stream: .irtf, workingGroup: "cfrg"))]

    #expect(options.apply(to: research, filter: .all, query: "x").isEmpty)
    #expect(options.apply(to: research, filter: .stream(.irtf), query: "x").count == 1)
    #expect(options.apply(to: research, filter: .workingGroup("cfrg"), query: "x").count == 1)
    #expect(options.scopeInForce(query: "x", filter: .stream(.irtf)).isEverything)
    #expect(options.scopeInForce(query: "x", filter: .all) == SearchScope(stream: .ietf))
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
