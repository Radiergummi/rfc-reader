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

  public init(
    filter: LibraryFilter, query: String, bookmarked: Set<DocumentID> = [],
    recentlyRead: [DocumentID] = [],
    downloaded: Set<Int> = [], options: ListOptions = ListOptions(), members: [Int] = []
  ) {
    self.filter = filter
    self.query = query.normalizedQuery
    self.bookmarked = bookmarked
    self.recentlyRead = recentlyRead
    self.downloaded = downloaded
    self.options = options
    self.members = members
  }

  /// The list `filter` shows, reading from `sources` only the input it lists from.
  /// The others are never read, so a caller whose reads are observed is not asked
  /// to list again for a change it does not show: every tab searched again for a
  /// bookmark toggled.
  public static func reading(
    _ filter: LibraryFilter, query: String, options: ListOptions, from sources: some ListSources
  ) -> LibraryList {
    var members: [Int] {
      guard case .collection(let identifier) = filter else { return [] }
      return sources.members(of: identifier)
    }
    return LibraryList(
      filter: filter,
      query: query,
      bookmarked: filter == .bookmarks ? sources.bookmarked : [],
      recentlyRead: filter == .recent ? sources.recentlyRead : [],
      downloaded: filter == .downloaded ? sources.downloaded : [],
      options: options,
      members: members
    )
  }

  /// The rows, as the options show them. `search` is the index's own; without one,
  /// a query finds nothing more than the filter already lists. `hits` are its hits
  /// for `query`, best first, when they are known already (`ListedRows`); without
  /// them the query is searched here.
  public func rows(
    in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]? = nil
  ) -> [LibraryRow] {
    options.apply(
      to: unshaped(in: index, search: search, hits: hits), filter: filter, query: query)
  }

  /// Newest first, as every list is built, or in order of relevance for a search.
  private func unshaped(
    in index: RFCIndex, search: IndexSearch?, hits: [RFCMetadata]?
  ) -> [LibraryRow] {
    let base: [LibraryRow]
    switch filter {
    case .all: base = index.rfcs.reversed().map(LibraryRow.rfc)
    case .recent: base = recentlyRead.compactMap { LibraryRow($0, in: index) }
    // By date rather than number, the one order an RFC and a series share.
    case .bookmarks:
      base = bookmarked.compactMap { LibraryRow($0, in: index) }.sorted(by: LibraryRow.isNewer)
    case .downloaded: base = downloaded.sorted(by: >).compactMap { index[$0] }.map(LibraryRow.rfc)
    // Through the predicate the sidebar's counts use, so the two cannot disagree.
    case .standards, .bestCurrentPractice, .stream, .workingGroup:
      base = index.rfcs.reversed().filter { filter.includes($0) == true }.map(LibraryRow.rfc)
    case .series(let id): base = (LibraryRow(id, in: index)?.members ?? []).map(LibraryRow.rfc)
    case .collection: base = members.compactMap { index[$0] }.map(LibraryRow.rfc)
    }

    guard !query.isEmpty else { return base }
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
    if case .all = filter { return found.map(LibraryRow.rfc) }
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
