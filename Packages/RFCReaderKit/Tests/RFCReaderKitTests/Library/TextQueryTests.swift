import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a list asks the full-text search (#37): the query's words, and the RFCs its
/// qualifiers and the list's filter allow, which narrow the section hits as they
/// narrow the RFC rows (answered on #37, 2026-10-14).
@Suite("Text query")
struct TextQueryTests {
  private let index = RFCIndex(
    rfcs: [
      Fixtures.metadata(1, title: "Host Software", currentStatus: .bestCurrentPractice),
      Fixtures.metadata(2, title: "Host Software Protocol"),
      Fixtures.metadata(3, title: "Documentation Conventions", currentStatus: .bestCurrentPractice),
      Fixtures.metadata(4, title: "Network Timetable"),
    ],
    series: [
      SeriesEntry(id: DocumentID(series: .bcp, number: 1), members: [.rfc(3), .rfc(1)])
    ])

  private func textQuery(_ list: LibraryList) -> LibraryList.TextQuery? {
    list.textQuery(in: index, search: IndexSearch(index: index))
  }

  @Test func `words in the whole library search every document`() {
    let query = textQuery(LibraryList(filter: .all, query: "congestion window"))
    #expect(query?.words == "congestion window")
    #expect(query?.documents == nil)
  }

  @Test func `a query of only qualifiers has no section hits`() {
    #expect(textQuery(LibraryList(filter: .all, query: "status:bcp")) == nil)
  }

  @Test func `an empty query has no section hits`() {
    #expect(textQuery(LibraryList(filter: .bookmarks, query: "", bookmarked: [.rfc(2)])) == nil)
  }

  @Test func `a qualifier narrows the documents searched`() {
    let query = textQuery(LibraryList(filter: .all, query: "congestion status:bcp"))
    #expect(query?.words == "congestion")
    #expect(query?.documents == [.rfc(1), .rfc(3)])
  }

  /// The option hides an obsolete RFC's row, and its sections with it, in the whole
  /// library as in any other list.
  @Test func `hiding the obsolete RFCs narrows the documents searched`() {
    let index = RFCIndex(
      rfcs: [Fixtures.metadata(1, obsoletedBy: [.rfc(2)]), Fixtures.metadata(2)], series: [])
    let list = LibraryList(
      filter: .all, query: "congestion", options: ListOptions(showsObsolete: false))
    #expect(list.textQuery(in: index, search: IndexSearch(index: index))?.documents == [.rfc(2)])
  }

  @Test func `the list's filter narrows the documents searched`() {
    let query = textQuery(
      LibraryList(filter: .bookmarks, query: "congestion", bookmarked: [.rfc(2), .rfc(4)]))
    #expect(query?.documents == [.rfc(2), .rfc(4)])
  }

  /// A series row is its member RFCs, and their bodies are what is indexed.
  @Test func `a series in the list searches its members`() {
    let bcp = DocumentID(series: .bcp, number: 1)
    let query = textQuery(LibraryList(filter: .bookmarks, query: "congestion", bookmarked: [bcp]))
    #expect(query?.documents == [.rfc(1), .rfc(3)])
  }

  @Test func `in a document searches only that document`() {
    #expect(textQuery(LibraryList(filter: .all, query: "congestion in:2"))?.documents == [.rfc(2)])
  }

  /// `sort:` orders the RFC rows only; it allows every document it found.
  @Test func `a sort narrows nothing`() {
    #expect(textQuery(LibraryList(filter: .all, query: "congestion sort:oldest"))?.documents == nil)
  }

  /// The RFC rows are empty while a term is unknown, and so are the section hits.
  @Test func `an unknown term has no section hits`() {
    #expect(textQuery(LibraryList(filter: .all, query: "congestion released:2024")) == nil)
  }
}
