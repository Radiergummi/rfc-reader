import Foundation
import RFCKit

/// How the list is shown: the view options in the iOS list's More menu (#348).
///
/// A new tab's start from the library's settings (`LibrarySettings.listOptions`,
/// #713), and its View Options change them for that tab only.
public struct ListOptions: Hashable, Sendable {
  /// Raw values as user defaults hold the default order (`LibraryPreferences`).
  public enum Order: String, Hashable, Sendable, CaseIterable {
    case newestFirst
    case oldestFirst

    public func title(in locale: Locale = .interface) -> String {
      switch self {
      case .newestFirst: String(kit: "Newest First", locale: locale)
      case .oldestFirst: String(kit: "Oldest First", locale: locale)
      }
    }
  }

  /// How a collection's list is ordered (#349): the reader's own order, or by
  /// publication date. Separate from `order`, so a tab set to Oldest First for the
  /// library still opens a collection in its own order.
  public enum CollectionSort: Hashable, Sendable, CaseIterable {
    case manual
    case newestFirst
    case oldestFirst

    public func title(in locale: Locale = .interface) -> String {
      switch self {
      case .manual: String(kit: "Manual", locale: locale)
      case .newestFirst: String(kit: "Newest First", locale: locale)
      case .oldestFirst: String(kit: "Oldest First", locale: locale)
      }
    }
  }

  public var order: Order
  /// Whether an unsearched list shows obsoleted documents.
  public var showsObsolete: Bool
  /// Whether a search shows obsoleted documents: a default of its own in Settings
  /// (#713), so the tab's toggle changes the one for what is on show.
  public var showsObsoleteInSearch: Bool
  public var collectionSort: CollectionSort
  /// Leave out what the reader has read (`ReaderData.read`, Recently Read): a tab's
  /// own filter, with no default in Settings (#713).
  public var hidesRead: Bool
  /// What a search looks in until its query says otherwise (#713).
  public var searchScope: SearchScope
  /// Whether the April 1st RFCs are listed (`AprilFirstRFCs`): a setting of the
  /// library's, not the tab's, which a tab's list follows (#713).
  public var showsAprilFirst: Bool

  public init(
    order: Order = .newestFirst, showsObsolete: Bool = true,
    showsObsoleteInSearch: Bool = true, collectionSort: CollectionSort = .manual,
    hidesRead: Bool = false, searchScope: SearchScope = SearchScope(),
    showsAprilFirst: Bool = true
  ) {
    self.order = order
    self.showsObsolete = showsObsolete
    self.showsObsoleteInSearch = showsObsoleteInSearch
    self.collectionSort = collectionSort
    self.hidesRead = hidesRead
    self.searchScope = searchScope
    self.showsAprilFirst = showsAprilFirst
  }

  /// Whether obsoleted documents are shown in a search, or in an unsearched list.
  public func showsObsolete(searching: Bool) -> Bool {
    searching ? showsObsoleteInSearch : showsObsolete
  }

  /// Shows or hides obsoleted documents in a search, or in an unsearched list: what
  /// the tab's Show Obsolete toggle changes, for what is on show.
  public mutating func setShowsObsolete(_ shows: Bool, searching: Bool) {
    if searching { showsObsoleteInSearch = shows } else { showsObsolete = shows }
  }

  /// The search scope in force for `query` in `filter`'s list: none while it
  /// searches for nothing, and otherwise what its own qualifiers and the list leave
  /// of `searchScope`. `definition` is a dynamic collection's query (#355), whose
  /// own qualifiers leave it as the query's do.
  public func scopeInForce(
    query: String, filter: LibraryFilter, definition: String? = nil
  ) -> SearchScope {
    guard !query.isUnsearchedQuery else { return SearchScope() }
    let asked = IndexSearch.parseQuery(query.normalizedQuery).filters
    return Self.scope(searchScope.leaving(asked, in: filter), definedBy: definition)
  }

  /// `scope` less what a dynamic collection's query `definition` names itself: the
  /// reader chose where to look, as with a stream's list.
  private static func scope(_ scope: SearchScope, definedBy definition: String?) -> SearchScope {
    guard let definition else { return scope }
    return scope.leaving(IndexSearch.parseQuery(definition).filters)
  }

  /// Whether a list can be put oldest first: only one in order of publication, the
  /// same lists that are sectioned by year. Reversing reading order or relevance
  /// would not put the oldest first.
  public static func canReorder(_ filter: LibraryFilter, query: String) -> Bool {
    YearSections.apply(to: filter, query: query)
  }

  /// `rows`, newest first as every list is built, shown as these options say.
  /// `read` is what the reader has read, which Hide Read leaves out. `searching` is
  /// whether the rows are a search's, which by default a query that is not empty
  /// says; a list narrowing a search by its qualifiers alone says so itself.
  /// `definition` is a dynamic collection's query (#355): its rows are the whole
  /// library's, `filter` `.all`, yet it is the reader's own collection.
  public func apply(
    to rows: [LibraryRow], filter: LibraryFilter, query: String, read: Set<DocumentID> = [],
    searching: Bool? = nil, definition: String? = nil
  ) -> [LibraryRow] {
    let searching = searching ?? !query.isUnsearchedQuery
    let asked = IndexSearch.parseQuery(query.normalizedQuery).filters
    let scope =
      searching
      ? Self.scope(searchScope.leaving(asked, in: filter), definedBy: definition) : SearchScope()
    let hidesRead = hidesRead && filter != .recent && !asked.readerData.contains(.read)
    let hidesAprilFirst =
      !showsAprilFirst && definition == nil && Self.listsFromIndex(filter, asked: asked)
    let showsObsolete = showsObsolete(searching: searching)
    let hidesNothing = showsObsolete && scope.isEverything && !hidesRead && !hidesAprilFirst
    let shown =
      hidesNothing
      ? rows
      : rows.filter { row in
        (showsObsolete || !row.isObsolete) && scope.includes(row)
          && !(hidesRead && read.contains(row.id))
          && !(hidesAprilFirst && AprilFirstRFCs.contains(row.id))
      }
    if case .collection = filter { return sortedCollection(shown, query: query) }
    guard order == .oldestFirst, Self.canReorder(filter, query: query) else { return shown }
    return shown.reversed()
  }

  /// Whether `filter`, under a query asking for `asked`, lists from the index rather
  /// than from what the reader keeps: where the April 1st RFCs are hidden. A bookmark,
  /// a collection, a document read or kept offline, and a query's `is:` or `in:`,
  /// keep theirs, so hiding them never breaks what the reader chose (#713).
  private static func listsFromIndex(_ filter: LibraryFilter, asked: SearchFilters) -> Bool {
    guard asked.readerData.isEmpty, asked.scopes.isEmpty else { return false }
    switch filter {
    case .all, .standards, .bestCurrentPractice, .stream, .workingGroup: return true
    case .recent, .bookmarks, .downloaded, .series, .collection: return false
    }
  }

  /// Whether these options leave anything out of a search of the whole library,
  /// whatever its query: the full-text search then searches only the documents the
  /// list shows (`LibraryList.textQuery`).
  func narrowsSearch(query: String) -> Bool {
    !showsObsoleteInSearch || hidesRead || !showsAprilFirst
      || !scopeInForce(query: query, filter: .all).isEverything
  }

  /// Whether rows can be dragged into a new order: only in a collection, in its own
  /// order, unsearched — a search's rows are in order of relevance, and their
  /// neighbors are not the collection's.
  public func allowsMoving(in filter: LibraryFilter, query: String) -> Bool {
    guard case .collection = filter else { return false }
    return collectionSort == .manual && query.isUnsearchedQuery
  }

  /// By publication date, then number: a collection is in the reader's order, so
  /// reversing it would not put the oldest first. A search stays in order of
  /// relevance.
  private func sortedCollection(_ rows: [LibraryRow], query: String) -> [LibraryRow] {
    guard query.isUnsearchedQuery else { return rows }
    switch collectionSort {
    case .manual: return rows
    case .newestFirst: return rows.sorted { ($0.date, $0.id.number) > ($1.date, $1.id.number) }
    case .oldestFirst: return rows.sorted { ($0.date, $0.id.number) < ($1.date, $1.id.number) }
    }
  }
}
