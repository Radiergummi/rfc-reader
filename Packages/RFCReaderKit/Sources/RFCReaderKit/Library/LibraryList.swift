import Foundation
import RFCKit

extension String {
  /// What a search field holding this searches for: less the spaces and newlines
  /// around it, which change nothing it finds. Every list, the sidebar and the Go to
  /// RFC palette read a query through this, so they agree on what is a search.
  public var normalizedQuery: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Whether a search field holding this searches for nothing, and a list shows
  /// its filter as it is.
  public var isUnsearchedQuery: Bool {
    normalizedQuery.isEmpty
  }
}

/// Where the inputs a list may list from are read: each only when a filter asks
/// for it (`LibraryList.reading`).
public protocol ListSources {
  var bookmarked: Set<DocumentID> { get }
  var recentlyRead: [DocumentID] { get }
  var downloaded: Set<Int> { get }
  func members(of collection: UUID) -> [Int]
  /// The collection a query's `in:` names, by its name in any case.
  func collection(named name: String) -> UUID?
}

/// Everything a library list is a function of, and the list it makes.
///
/// The filter and the query are passed in rather than read off the library: they
/// belong to one tab (`NavigationModel`), and two tabs may be listing different
/// things at the same time. Gathering them into one value also says when a tab has
/// to list again: when the list it asks for is not the one it shows (#597). The one
/// input not in it is the index, handed to `rows(in:search:)`.
public struct LibraryList: Hashable, Sendable {
  public let filter: LibraryFilter
  /// Normalized, so a query differing only in the spaces around it is the same list.
  public let query: String
  /// Documents rather than RFC numbers, so a BCP, STD or FYI bookmarked or read is
  /// listed as itself (#321).
  public let bookmarked: Set<DocumentID>
  public let recentlyRead: [DocumentID]
  public let downloaded: Set<Int>
  public let options: ListOptions
  /// A collection's members in order, so adding, removing or reordering makes a
  /// different list (#349).
  public let members: [Int]
  /// The members of each collection the query's `in:` names, by its name lowercased.
  /// A name missing here is a collection the library doesn't hold.
  public let collections: [String: [Int]]

  public init(
    filter: LibraryFilter, query: String, bookmarked: Set<DocumentID> = [],
    recentlyRead: [DocumentID] = [],
    downloaded: Set<Int> = [], options: ListOptions = ListOptions(), members: [Int] = [],
    collections: [String: [Int]] = [:]
  ) {
    self.filter = filter
    self.query = query.normalizedQuery
    self.bookmarked = bookmarked
    self.recentlyRead = recentlyRead
    self.downloaded = downloaded
    self.options = options
    self.members = members
    self.collections = collections
  }

  /// The list `filter` shows, reading from `sources` only the inputs it and `query`
  /// list from. The others are never read, so a caller whose reads are observed is
  /// not asked to list again for a change it does not show: every tab searched again
  /// for a bookmark toggled.
  public static func reading(
    _ filter: LibraryFilter, query: String, options: ListOptions, from sources: some ListSources
  ) -> LibraryList {
    let asked = IndexSearch.parseQuery(query.normalizedQuery).filters
    var members: [Int] {
      guard case .collection(let identifier) = filter else { return [] }
      return sources.members(of: identifier)
    }
    var collections: [String: [Int]] = [:]
    for name in asked.collectionNames {
      guard let identifier = sources.collection(named: name) else { continue }
      collections[name.lowercased()] = sources.members(of: identifier)
    }
    return LibraryList(
      filter: filter,
      query: query,
      bookmarked: filter == .bookmarks || asked.readerData.contains(.bookmarked)
        ? sources.bookmarked : [],
      recentlyRead: filter == .recent || asked.readerData.contains(.read) || asked.sort == .lastRead
        ? sources.recentlyRead : [],
      downloaded: filter == .downloaded || asked.readerData.contains(.offline)
        ? sources.downloaded : [],
      options: options,
      members: members,
      collections: collections
    )
  }

  /// The terms of the query that name something unknown: a qualifier or a value this
  /// version doesn't know, a working group `index` doesn't name, or a collection the
  /// library doesn't hold. While there is one, the list is empty, and these say why.
  public func unknownTerms(in index: RFCIndex) -> [UnknownSearchTerm] {
    unknownTerms(of: IndexSearch.parseQuery(query), in: index)
  }

  private func unknownTerms(
    of parsed: SearchQuery.Parsed, in index: RFCIndex
  ) -> [UnknownSearchTerm] {
    let known = SearchQuery.unknownTerms(in: query, index: index)
    guard parsed.filters.collectionNames.contains(where: { collections[$0.lowercased()] == nil })
    else { return known }
    // Each word naming a collection the library doesn't hold, as it was written.
    let missing = SearchQuery.words(in: query).filter { word in
      IndexSearch.parseQuery(word).filters.collectionNames.contains {
        collections[$0.lowercased()] == nil
      }
    }
    return known + missing.map { UnknownSearchTerm(word: $0, reason: .collection) }
  }

  /// The search's hits for the part of the query the index can answer, best first:
  /// what `rows(in:search:hits:)` narrows the filter's rows by. None when the query
  /// names something unknown, or asks the index for nothing.
  public func hits(from search: IndexSearch, now: Date = Date()) -> [RFCMetadata] {
    hits(for: IndexSearch.parseQuery(query), from: search, now: now)
  }

  private func hits(
    for parsed: SearchQuery.Parsed, from search: IndexSearch, now: Date = Date()
  ) -> [RFCMetadata] {
    guard parsed.unknown.isEmpty, let indexed = parsed.filters.indexed(text: parsed.text) else {
      return []
    }
    return search.search(text: parsed.text, filters: indexed, limit: .max, now: now).map(\.rfc)
  }

  /// The rows, as the options show them. `search` is the index's own; without one,
  /// a query finds nothing more than the filter already lists. `hits` are its hits
  /// for `query`, best first, when they are known already (`ListedRows`); without
  /// them the query is searched here.
  public func rows(
    in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]? = nil
  ) -> [LibraryRow] {
    let parsed = IndexSearch.parseQuery(query)
    guard unknownTerms(of: parsed, in: index).isEmpty else { return [] }
    // In the whole library the reader's data is the list (`narrowing`), so the
    // index's every row would be made only to be thrown away.
    let isReplaced = filter == .all && !parsed.filters.readerData.isEmpty
    var base = isReplaced ? [] : rows(of: filter, in: index)
    let narrowed = narrowing(base, in: index, by: parsed.filters)
    base = narrowed.rows
    // A query of only what was narrowed by, and a sort, searches for nothing more,
    // and keeps the rows in their own order: Bookmarks newest first, Recently Read
    // in reading order.
    if parsed.filters.indexed(text: parsed.text) != nil {
      let found = hits ?? search.map { self.hits(for: parsed, from: $0) }
      if let found { base = searched(base, found: found, isNarrowed: narrowed.isNarrowed) }
    }
    return options.apply(to: sorted(base, by: parsed.filters.sort), filter: filter, query: query)
  }

  /// `rows` in the order a query's `sort:` asks for, or as they are without one.
  private func sorted(_ rows: [LibraryRow], by sort: SearchFilters.Sort?) -> [LibraryRow] {
    switch sort {
    case nil: return rows
    case .newest: return rows.sorted(by: LibraryRow.isNewer)
    case .oldest: return rows.sorted { LibraryRow.isNewer($1, than: $0) }
    case .lastRead:
      let order = Dictionary(
        recentlyRead.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      return rows.enumerated().sorted { lhs, rhs in
        (order[lhs.element.id] ?? .max, lhs.offset) < (order[rhs.element.id] ?? .max, rhs.offset)
      }
      .map(\.element)
    }
  }

  /// `base`, the filter's rows, narrowed to what the query's `is:` and `in:` a
  /// collection ask for: the reader's data, which the index doesn't hold, and so the
  /// search can't narrow by. Each is a union within itself, and the two narrow
  /// together. In the whole library the rows they ask for are the list, series rows
  /// included, as Bookmarks lists them.
  private func narrowing(
    _ base: [LibraryRow], in index: RFCIndex, by asked: SearchFilters
  ) -> (rows: [LibraryRow], isNarrowed: Bool) {
    var rows = base
    var isNarrowed = false
    if !asked.readerData.isEmpty {
      let sources: [(SearchFilters.ReaderData, LibraryFilter)] = [
        (.bookmarked, .bookmarks), (.read, .recent), (.offline, .downloaded),
      ]
      let asking = sources.filter { asked.readerData.contains($0.0) }
      var listed: Set<DocumentID> = []
      var union = asking.flatMap { self.rows(of: $0.1, in: index) }
        .filter { listed.insert($0.id).inserted }
      // One input keeps its own order; several are put newest first, as every list is.
      if asking.count > 1 { union.sort(by: LibraryRow.isNewer) }
      rows = filter == .all ? union : rows.filter { listed.contains($0.id) }
      isNarrowed = true
    }
    if !asked.collectionNames.isEmpty {
      // The documents `in:` names beside its collections: the search leaves `in:` to
      // this once it names a collection.
      let numbers = Set(
        asked.collectionNames.flatMap { collections[$0.lowercased()] ?? [] }
          + asked.documentScopes.flatMap(index.rfcNumbers(of:)))
      // A series row is in when one of its members is, as a search finds it.
      rows = rows.filter { row in
        row.rfc.map { numbers.contains($0.number) }
          ?? row.members.contains { numbers.contains($0.number) }
      }
      isNarrowed = true
    }
    return (rows, isNarrowed)
  }

  /// The rows `filter` lists, newest first as every list is built, or in its own
  /// order: Recently Read in reading order, a series or a collection in its own.
  private func rows(of filter: LibraryFilter, in index: RFCIndex) -> [LibraryRow] {
    switch filter {
    case .all: index.rfcs.reversed().map(LibraryRow.rfc)
    case .recent: recentlyRead.compactMap { LibraryRow($0, in: index) }
    // By date rather than number, the one order an RFC and a series share.
    case .bookmarks:
      bookmarked.compactMap { LibraryRow($0, in: index) }.sorted(by: LibraryRow.isNewer)
    case .downloaded: downloaded.sorted(by: >).compactMap { index[$0] }.map(LibraryRow.rfc)
    // Through the predicate the sidebar's counts use, so the two cannot disagree.
    case .standards, .bestCurrentPractice, .stream, .workingGroup:
      index.rfcs.reversed().filter { filter.includes($0) == true }.map(LibraryRow.rfc)
    case .series(let id): (LibraryRow(id, in: index)?.members ?? []).map(LibraryRow.rfc)
    case .collection: members.compactMap { index[$0] }.map(LibraryRow.rfc)
    }
  }

  /// `base` narrowed by the search's hits, `found`, in order of relevance.
  ///
  /// Every hit, not the top few hundred: the search scores and sorts all of them
  /// anyway, the list windows its rows itself (`ListWindow`), and the count over the
  /// list says how many there are. A cap also cut before the filter below, so a
  /// search inside a collection lost whatever ranked outside the cap overall.
  private func searched(
    _ base: [LibraryRow], found: [RFCMetadata], isNarrowed: Bool
  ) -> [LibraryRow] {
    // Everything is allowed in the whole library, so there is nothing to filter.
    if case .all = filter, !isNarrowed { return found.map(LibraryRow.rfc) }
    // In order of relevance, a series row where its best hit is: it is found when
    // any of the RFCs it names is. Only the reader's data holds one, so the RFC
    // rows, thousands in a stream or a group, go in a set.
    var allowed: Set<Int> = []
    var seriesByMember: [Int: [LibraryRow]] = [:]
    for row in base {
      if let rfc = row.rfc {
        allowed.insert(rfc.number)
      } else {
        for member in row.members { seriesByMember[member.number, default: []].append(row) }
      }
    }
    guard !seriesByMember.isEmpty else {
      return found.filter { allowed.contains($0.number) }.map(LibraryRow.rfc)
    }
    var listed: Set<DocumentID> = []
    return found.flatMap { hit in
      (allowed.contains(hit.number) ? [LibraryRow.rfc(hit)] : [])
        + (seriesByMember[hit.number] ?? [])
    }
    .filter { listed.insert($0.id).inserted }
  }
}

extension SearchFilters {
  /// The filters the index's search answers, beside `text`: these less the reader's
  /// data, a sort, and `in:` once it names a collection, which a list narrows by
  /// itself. Nil when they and the text ask the index for nothing.
  func indexed(text: String) -> SearchFilters? {
    var indexed = self
    indexed.readerData = []
    indexed.sort = nil
    if !collectionNames.isEmpty { indexed.scopes = [] }
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty || !indexed.isEmpty else {
      return nil
    }
    return indexed
  }
}
