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
    let parsed = IndexSearch.parseQuery(query)
    // Each word naming a collection the library doesn't hold, as it was written.
    let missing = SearchQuery.words(in: query).filter { word in
      IndexSearch.parseQuery(word).filters.collectionNames.contains {
        collections[$0.lowercased()] == nil
      }
    }
    return SearchQuery.unknownTerms(of: parsed, in: index)
      + missing.map { UnknownSearchTerm(word: $0, reason: .collection) }
  }

  /// The rows, as the options show them. `search` is the index's own; without one,
  /// a query finds nothing more than the filter already lists. `hits` are its hits
  /// for `query`, best first, when they are known already (`ListedRows`); without
  /// them the query is searched here.
  public func rows(
    in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]? = nil
  ) -> [LibraryRow] {
    let asked = IndexSearch.parseQuery(query).filters
    guard unknownTerms(in: index).isEmpty else { return [] }
    let rows = unshaped(in: index, search: search, hits: hits, asked: asked)
    return options.apply(to: sorted(rows, by: asked.sort), filter: filter, query: query)
  }

  /// `rows` in the order a query's `sort:` asks for, or as they are without one.
  private func sorted(_ rows: [LibraryRow], by sort: SearchFilters.Sort?) -> [LibraryRow] {
    switch sort {
    case nil: return rows
    case .newest: return rows.sorted { ($0.date, $0.id.number) > ($1.date, $1.id.number) }
    case .oldest: return rows.sorted { ($0.date, $0.id.number) < ($1.date, $1.id.number) }
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
      var asking: [LibraryRow] = []
      if asked.readerData.contains(.bookmarked) { asking += readerRows(of: .bookmarks, in: index) }
      if asked.readerData.contains(.read) { asking += readerRows(of: .recent, in: index) }
      if asked.readerData.contains(.offline) { asking += readerRows(of: .downloaded, in: index) }
      var listed: Set<DocumentID> = []
      asking = asking.filter { listed.insert($0.id).inserted }
      rows = filter == .all ? asking : rows.filter { listed.contains($0.id) }
      isNarrowed = true
    }
    if !asked.collectionNames.isEmpty {
      // The documents `in:` names beside its collections: the search leaves `in:` to
      // this once it names a collection.
      let numbers = Set(
        asked.collectionNames.flatMap { collections[$0.lowercased()] ?? [] }
          + asked.scopes.flatMap { scope -> [Int] in
            guard case .document(let id) = scope else { return [] }
            return id.series == .rfc ? [id.number] : (index.series(id)?.members.map(\.number) ?? [])
          })
      rows = rows.filter { $0.rfc.map { numbers.contains($0.number) } ?? false }
      isNarrowed = true
    }
    return (rows, isNarrowed)
  }

  /// The rows `filter` lists from the reader's data, newest first, or in reading order.
  private func readerRows(of filter: LibraryFilter, in index: RFCIndex) -> [LibraryRow] {
    switch filter {
    case .recent: recentlyRead.compactMap { LibraryRow($0, in: index) }
    case .bookmarks:
      bookmarked.compactMap { LibraryRow($0, in: index) }.sorted(by: LibraryRow.isNewer)
    case .downloaded: downloaded.sorted(by: >).compactMap { index[$0] }.map(LibraryRow.rfc)
    default: []
    }
  }

  /// Newest first, as every list is built, or in order of relevance for a search.
  private func unshaped(
    in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]?, asked: SearchFilters
  ) -> [LibraryRow] {
    var base: [LibraryRow]
    switch filter {
    case .all: base = index.rfcs.reversed().map(LibraryRow.rfc)
    // By date rather than number, the one order an RFC and a series share.
    case .recent, .bookmarks, .downloaded: base = readerRows(of: filter, in: index)
    // Through the predicate the sidebar's counts use, so the two cannot disagree.
    case .standards, .bestCurrentPractice, .stream, .workingGroup:
      base = index.rfcs.reversed().filter { filter.includes($0) == true }.map(LibraryRow.rfc)
    case .series(let id): base = (LibraryRow(id, in: index)?.members ?? []).map(LibraryRow.rfc)
    case .collection: base = members.compactMap { index[$0] }.map(LibraryRow.rfc)
    }

    let narrowed = narrowing(base, in: index, by: asked)
    base = narrowed.rows
    // A query of only what was narrowed by, and a sort, searches for nothing more,
    // and keeps the rows in their own order: Bookmarks newest first, Recently Read
    // in reading order.
    guard !asked.searchesIndex(text: IndexSearch.parseQuery(query).text) else {
      return searched(base, in: index, search: search, hits: hits, isNarrowed: narrowed.isNarrowed)
    }
    return base
  }

  /// `base` narrowed by the search for the query, in order of relevance.
  private func searched(
    _ base: [LibraryRow], in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]?,
    isNarrowed: Bool
  ) -> [LibraryRow] {
    // Every hit, not the top few hundred: the search scores and sorts all of them
    // anyway, the list windows its rows itself (`ListWindow`), and the count over
    // the list says how many there are. A cap also cut before the filter below,
    // so a search inside a collection lost whatever ranked outside the cap overall.
    let found: [RFCMetadata]
    if let hits {
      found = hits
    } else if let search {
      found = search.search(query, limit: .max).map(\.rfc)
    } else {
      return base
    }
    // Everything is allowed in the whole library, so there is nothing to filter.
    if case .all = filter, !isNarrowed { return found.map(LibraryRow.rfc) }
    // In order of relevance, a series row where its best hit is: it is found when
    // any of the RFCs it names is. Only Bookmarks and Recently Read hold one, so
    // the RFC rows, thousands in a stream or a group, go in a set.
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
  /// The names of the collections `in:` names.
  var collectionNames: [String] {
    scopes.compactMap { scope in
      guard case .collection(let name) = scope else { return nil }
      return name
    }
    .sorted()
  }

  /// Whether a query of `text` and these filters asks the index's search for more
  /// than the reader's data, a collection and a sort, which are narrowed by here.
  func searchesIndex(text: String) -> Bool {
    var indexed = self
    indexed.readerData = []
    indexed.sort = nil
    if !collectionNames.isEmpty { indexed.scopes = [] }
    return !text.trimmingCharacters(in: .whitespaces).isEmpty || !indexed.isEmpty
  }
}
