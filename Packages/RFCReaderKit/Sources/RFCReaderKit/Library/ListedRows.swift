import RFCKit

/// What a tab's list shows, stored by the tab rather than computed in a view's body
/// (#597): the rows for `list`, and the search's hits they came from.
///
/// Made off the main actor whenever an input of the list changes, so a body only
/// reads it. `list` is what the rows were made for, which is what the list's search,
/// count and sections are about until the next one arrives.
public struct ListedRows: Sendable {
  public let list: LibraryList
  public let rows: [RFCMetadata]
  /// The search's hits for `list.query`, best first, whatever the filter: empty for
  /// a list that is not searched. Kept so a change of filter or options lists again
  /// without searching again.
  public let hits: [RFCMetadata]
  /// Which index the rows were made over, as the library counts the indexes it
  /// installs: comparing two indexes would compare 9,842 entries.
  public let indexVersion: Int

  /// `list` over `index`, the library's `indexVersion`th. `search` is the index's
  /// own; see `LibraryList.rows`. `known` are its hits for `list.query` from an
  /// earlier listing over the same index, which spares the search.
  public init(
    _ list: LibraryList, in index: RFCIndex, indexVersion: Int, search: IndexSearch?,
    hits known: [RFCMetadata]? = nil
  ) {
    self.list = list
    self.indexVersion = indexVersion
    guard !list.query.isEmpty, let search else {
      rows = list.rows(in: index, search: search)
      hits = []
      return
    }
    let hits = known ?? search.search(list.query, limit: .max).map(\.rfc)
    self.hits = hits
    rows = list.rows(in: index, search: search, hits: hits)
  }

  /// Whether these are the rows `list` asks for over the index counted
  /// `indexVersion`: a change that makes the same list, as a collection renamed,
  /// lists nothing.
  public func shows(_ list: LibraryList, indexVersion: Int) -> Bool {
    self.list == list && self.indexVersion == indexVersion
  }

  /// The hits to list `list` from without searching again: these, when it searches
  /// for the same over the same index, as after a change of filter or options.
  public func hits(for list: LibraryList, indexVersion: Int) -> [RFCMetadata]? {
    guard list.query == self.list.query, self.indexVersion == indexVersion else { return nil }
    return hits
  }

  /// The whole library's results for the query, as All RFCs lists them: what the
  /// iPhone sidebar shows while it is searched (#345). Shaped from `hits` when read,
  /// since only that sidebar reads it.
  public var librarySearch: [RFCMetadata] {
    guard !list.query.isEmpty else { return [] }
    return ListOptions().apply(to: hits, filter: .all, query: list.query)
  }
}
