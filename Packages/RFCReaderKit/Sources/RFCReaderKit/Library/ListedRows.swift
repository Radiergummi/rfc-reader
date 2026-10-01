import RFCKit

/// What a tab's list shows, stored by the tab rather than computed in a view's body
/// (#597): the rows for `list`, and the whole library's results for its query, which
/// the iPhone sidebar lists while it is searched (#345). Both come from one search.
///
/// Made off the main actor whenever an input of the list changes, so a body only
/// reads it. `list` is what the rows were made for, which is what the list's search,
/// count and sections are about until the next one arrives.
public struct ListedRows: Sendable {
  public let list: LibraryList
  public let rows: [RFCMetadata]
  /// Empty for a list that is not searched.
  public let librarySearch: [RFCMetadata]

  /// Nothing listed yet: before there is an index.
  public static let empty = ListedRows(
    list: LibraryList(filter: .all, query: ""), rows: [], librarySearch: [])

  private init(list: LibraryList, rows: [RFCMetadata], librarySearch: [RFCMetadata]) {
    self.list = list
    self.rows = rows
    self.librarySearch = librarySearch
  }

  /// `list` over `index`. `search` is the index's own; see `LibraryList.rows`.
  public init(_ list: LibraryList, in index: RFCIndex, search: IndexSearch?) {
    self.list = list
    guard !list.query.isEmpty, let search else {
      rows = list.rows(in: index, search: search)
      librarySearch = []
      return
    }
    let hits = search.search(list.query, limit: .max).map(\.rfc)
    rows = list.rows(in: index, search: search, hits: hits)
    librarySearch = LibraryList(filter: .all, query: list.query)
      .rows(in: index, search: search, hits: hits)
  }
}
