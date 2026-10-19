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

    #expect(options.scopeInForce(query: "").isEverything)
    #expect(options.scopeInForce(query: "http") == SearchScope(currentOnly: true, stream: .ietf))
    #expect(options.scopeInForce(query: "http stream:irtf") == SearchScope(currentOnly: true))
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
