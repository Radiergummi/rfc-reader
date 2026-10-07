import Foundation
import Testing

@testable import RFCKit

/// What the search grammar grew for dynamic collections (#355): dates finer than a
/// year and relative ones, several working groups, the reader's own data, a document
/// or a collection to search in, a sort, Internet Standard alone, and the terms this
/// version doesn't know.
@Suite("Query grammar")
struct QueryGrammarTests {
  // MARK: - Round trip

  /// Every qualifier, in its canonical form, is written back exactly as it was read.
  @Test(arguments: [
    "wg:quic wg:tls",
    "status:internet-standard",
    "after:2023",
    "after:2023-06",
    "before:2024",
    "after:2023-01 before:2024-07",
    "published:<90d",
    "is:bookmarked",
    "is:read is:offline",
    "in:rfc9110",
    "in:bcp14",
    #"in:"HTTP stack""#,
    "in:Drafts",
    "sort:newest",
    "sort:oldest",
    "sort:last-read",
    "is:read sort:last-read",
    "wg:quic status:std after:2023-01 congestion",
    "published:<30d unknown:thing",
    "status:nonsense cache",
  ])
  func `a canonical query is written back unchanged`(query: String) {
    #expect(SearchQuery.format(IndexSearch.parseQuery(query)) == query)
  }

  @Test func `the canonical form of the new qualifiers`() {
    let parsed = IndexSearch.parseQuery(
      "sort:oldest in:BCP14 is:read before:2024 wg:TLS,quic after:2023-6 status:full")
    #expect(
      SearchQuery.format(parsed)
        == "wg:quic wg:tls status:internet-standard after:2023-06 before:2024 is:read in:bcp14 sort:oldest"
    )
  }

  // MARK: - Working groups

  /// A union within the facet, as `status:` is: a comma, or the qualifier again.
  @Test func `several working groups are a union`() {
    #expect(IndexSearch.parseQuery("wg:quic,TLS").filters.workingGroups == ["quic", "tls"])
    #expect(IndexSearch.parseQuery("wg:quic group:tls").filters.workingGroups == ["quic", "tls"])
  }

  @Test func `a working group filter finds each of its groups`() {
    let search = IndexSearch(index: Self.index)
    #expect(numbers(search.search("wg:quic,tls", limit: .max)) == [9000, 8446])
  }

  // MARK: - Statuses

  /// `std` is the whole standards track; Internet Standard alone has a word of its own.
  @Test func `internet-standard is Internet Standard alone`() {
    #expect(
      IndexSearch.parseQuery("status:internet-standard").filters.statuses == [.internetStandard])
    #expect(IndexSearch.parseQuery("status:full").filters.statuses == [.internetStandard])
    #expect(IndexSearch.parseQuery("status:std").filters.statuses.count == 3)
  }

  /// The standards track holds Internet Standard, so it is written once, as `std`.
  @Test func `the standards track is not written twice`() {
    #expect(
      SearchQuery.format(IndexSearch.parseQuery("status:full status:std")) == "status:std")
  }

  // MARK: - Dates

  @Test func `after and before take a year or a month`() {
    let filters = IndexSearch.parseQuery("after:2023-06 before:2024").filters
    #expect(filters.publishedAfter == PublicationDate(year: 2023, month: 6))
    #expect(filters.publishedBefore == PublicationDate(year: 2024))
  }

  /// `after:` counts from the start of what it names, and `before:` stops at the
  /// start of what it names, so `after:2023 before:2024` is the year 2023.
  @Test func `after is inclusive and before is exclusive`() {
    let search = IndexSearch(index: Self.index)
    #expect(numbers(search.search("after:2023 before:2024", limit: .max)) == [9420, 9400])
    #expect(numbers(search.search("after:2023-06 before:2024", limit: .max)) == [9420])
    #expect(numbers(search.search("after:2024", limit: .max)) == [9600])
  }

  /// Relative to the moment passed in, so a collection of what was just published
  /// moves as time passes. A month's document counts from the month's last day.
  @Test func `published counts back from now`() throws {
    let search = IndexSearch(index: Self.index)
    let now = try #require(
      Calendar.utc.date(from: DateComponents(year: 2024, month: 4, day: 10)))
    #expect(numbers(search.search("published:<90d", limit: .max, now: now)) == [9600])
    #expect(
      numbers(search.search("published:<365d", limit: .max, now: now)) == [9600, 9420])
    #expect(IndexSearch.parseQuery("published:<90d").filters.publishedWithinDays == 90)
  }

  // MARK: - The reader's data, documents and collections

  /// `is:` is still an alias of `status:`, and also takes the reader's own data.
  @Test func `is takes the reader's data and statuses`() {
    let filters = IndexSearch.parseQuery("is:bookmarked is:bcp is:offline").filters
    #expect(filters.readerData == [.bookmarked, .offline])
    #expect(filters.statuses == [.bestCurrentPractice])
    #expect(SearchQuery.format(text: "", filters: filters) == "status:bcp is:bookmarked is:offline")
  }

  /// A document identifier, a bare number read as an RFC, or a collection's name. An
  /// identifier wins over a collection that happens to be called the same.
  @Test func `in takes a document or a collection`() {
    #expect(IndexSearch.parseQuery("in:9110").filters.scopes == [.document(.rfc(9110))])
    #expect(
      IndexSearch.parseQuery(#"in:"BCP 14""#).filters.scopes
        == [.document(DocumentID(series: .bcp, number: 14))])
    #expect(
      IndexSearch.parseQuery(#"in:"HTTP stack""#).filters.scopes == [.collection("HTTP stack")])
  }

  /// A document is itself, and a series is its member RFCs. A collection is the
  /// reader's, so the index alone does not narrow by it.
  @Test func `in a document narrows the search to it`() {
    let search = IndexSearch(index: Self.index)
    #expect(numbers(search.search("in:8446", limit: .max)) == [8446])
    #expect(numbers(search.search("in:bcp14", limit: .max)) == [9400, 8446])
    #expect(numbers(search.search("in:rfc8446,bcp14", limit: .max)) == [9400, 8446])
  }

  @Test func `sort takes newest, oldest and last-read`() {
    #expect(IndexSearch.parseQuery("sort:newest").filters.sort == .newest)
    #expect(IndexSearch.parseQuery("sort:oldest").filters.sort == .oldest)
    #expect(IndexSearch.parseQuery("sort:last-read").filters.sort == .lastRead)
  }

  // MARK: - Unknown terms

  /// A qualifier this version doesn't know, or a value outside a closed vocabulary,
  /// is never searched as text: that would silently change what a saved query means.
  @Test(arguments: [
    ("published:>90d", SearchQuery.UnknownTerm.Reason.value),
    ("status:nonsense", .value),
    ("stream:nowhere", .value),
    ("has:pdf", .value),
    ("is:starred", .value),
    ("sort:random", .value),
    ("after:June", .value),
    ("year:soon", .value),
    ("released:2024", .qualifier),
  ])
  func `an unknown term is reported and not searched`(word: String, reason: SearchQuery.UnknownTerm.Reason) {
    let parsed = IndexSearch.parseQuery("cache \(word)")
    #expect(parsed.text == "cache")
    #expect(parsed.unknown == [SearchQuery.UnknownTerm(word: word, reason: reason)])
  }

  /// A query that names something unknown finds nothing, rather than more than it says.
  @Test func `a query with an unknown term finds nothing`() {
    let search = IndexSearch(index: Self.index)
    #expect(search.search("released:2024", limit: .max).isEmpty)
  }

  /// A colon inside a quoted phrase is the phrase's, so a URN can still be searched.
  @Test func `a quoted word with a colon is text`() {
    let parsed = IndexSearch.parseQuery(#""urn:ietf:params""#)
    #expect(parsed.unknown.isEmpty)
    #expect(parsed.text == #""urn:ietf:params""#)
  }

  /// A working group the index no longer names is unknown once the query is read
  /// against the index.
  @Test func `a working group missing from the index is unknown`() {
    let parsed = IndexSearch.parseQuery("wg:quic wg:gone")
    #expect(
      SearchQuery.unknownTerms(of: parsed, in: Self.index)
        == [SearchQuery.UnknownTerm(word: "wg:gone", reason: .workingGroup)])
  }

  // MARK: - Fixture

  private func numbers(_ hits: [SearchHit]) -> [Int] { hits.map(\.rfc.number) }

  private static let index = RFCIndex(
    rfcs: [
      rfc(8446, year: 2018, month: 8, group: "TLS", status: .proposedStandard),
      rfc(9000, year: 2021, month: 5, group: "QUIC", status: .proposedStandard),
      rfc(9400, year: 2023, month: 2, group: "HTTPBIS", status: .bestCurrentPractice),
      rfc(9420, year: 2023, month: 7, group: "HTTPBIS", status: .internetStandard),
      rfc(9600, year: 2024, month: 3, group: "HTTPBIS", status: .informational),
    ],
    series: [SeriesEntry(id: DocumentID(series: .bcp, number: 14), members: [.rfc(8446), .rfc(9400)])]
  )

  private static func rfc(
    _ number: Int, year: Int, month: Int, group: String, status: PublicationStatus
  ) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: "Document \(number)", date: PublicationDate(year: year, month: month),
      currentStatus: status, workingGroup: group)
  }
}

extension Calendar {
  fileprivate static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()
}
