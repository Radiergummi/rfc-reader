import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What Save as Collection… keeps (#355): the list as a query of the whole library,
/// so the collection lists what the tab listed.
@Suite("Saved query")
struct SavedQueryTests {
  @Test(arguments: [
    (LibraryFilter.all, "quic"),
    (.bookmarks, "is:bookmarked quic"),
    (.recent, "is:read sort:last-read quic"),
    (.downloaded, "is:offline quic"),
    (.standards, "status:internet-standard quic"),
    (.bestCurrentPractice, "status:bcp quic"),
    (.stream(.iab), "stream:iab quic"),
    (.workingGroup("httpbis"), "wg:httpbis quic"),
    (.series(DocumentID(series: .bcp, number: 14)), "in:bcp14 quic"),
  ])
  func `a built-in list is kept as its qualifier`(filter: LibraryFilter, saved: String) {
    let list = LibraryList(filter: filter, query: "quic")
    #expect(list.savedQuery(in: CollectionSnapshot(collections: [])) == saved)
  }

  @Test func `a manual collection is kept as in its name`() {
    let identifier = UUID()
    let snapshot = CollectionSnapshot(collections: [
      .init(id: identifier, name: "Key Words", color: .blue, members: [.rfc(2119)])
    ])
    let list = LibraryList(filter: .collection(identifier), query: "uppercase")
    #expect(list.savedQuery(in: snapshot) == #"in:"Key Words" uppercase"#)
  }

  @Test func `a dynamic collection is kept as its query and the search`() {
    let list = LibraryList(
      filter: .collection(UUID()), query: "congestion", definition: "wg:quic")
    #expect(list.savedQuery(in: CollectionSnapshot(collections: [])) == "wg:quic congestion")
  }

  /// The tab narrows its filter by the search, where one qualifier's values in a
  /// query are a union: kept, Bookmarks searched for `is:offline` would list every
  /// bookmark and every offline RFC.
  @Test(arguments: [
    (LibraryFilter.bookmarks, "is:offline"),
    (.recent, "is:bookmarked"),
    (.standards, "status:bcp"),
    (.stream(.iab), "stream:irtf"),
    (.workingGroup("quic"), "wg:tls"),
    (.series(DocumentID(series: .bcp, number: 14)), "in:9110"),
  ])
  func `a search naming its filter's qualifier again is not kept`(
    filter: LibraryFilter, query: String
  ) {
    let list = LibraryList(filter: filter, query: query)
    #expect(list.savedQuery(in: CollectionSnapshot(collections: [])) == nil)
  }

  @Test func `a manual collection searched in another is not kept`() {
    let identifier = UUID()
    let snapshot = CollectionSnapshot(collections: [
      .init(id: identifier, name: "Key Words", color: .blue, members: [.rfc(2119)])
    ])
    let list = LibraryList(filter: .collection(identifier), query: #"in:"Other""#)
    #expect(list.savedQuery(in: snapshot) == nil)
  }

  @Test func `an unsearched list is kept as its qualifier alone`() {
    let list = LibraryList(filter: .workingGroup("quic"), query: "")
    #expect(list.savedQuery(in: CollectionSnapshot(collections: [])) == "wg:quic")
  }
}
