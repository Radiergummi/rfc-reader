import Foundation
import RFCKit

/// How the list is shown: the view options in the iOS list's More menu (#348).
public struct ListOptions: Hashable, Sendable {
  public enum Order: Hashable, Sendable, CaseIterable {
    case newestFirst
    case oldestFirst

    public var title: String {
      switch self {
      case .newestFirst: "Newest First"
      case .oldestFirst: "Oldest First"
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

    public var title: String {
      switch self {
      case .manual: "Manual"
      case .newestFirst: "Newest First"
      case .oldestFirst: "Oldest First"
      }
    }
  }

  public var order: Order
  public var showsObsolete: Bool
  public var collectionSort: CollectionSort

  public init(
    order: Order = .newestFirst, showsObsolete: Bool = true,
    collectionSort: CollectionSort = .manual
  ) {
    self.order = order
    self.showsObsolete = showsObsolete
    self.collectionSort = collectionSort
  }

  /// Whether a list can be put oldest first: only one in order of publication, the
  /// same lists that are sectioned by year. Reversing reading order or relevance
  /// would not put the oldest first.
  public static func canReorder(_ filter: LibraryFilter, query: String) -> Bool {
    YearSections.apply(to: filter, query: query)
  }

  /// `rows`, newest first as every list is built, shown as these options say.
  public func apply(
    to rows: [RFCMetadata], filter: LibraryFilter, query: String
  ) -> [RFCMetadata] {
    let shown = showsObsolete ? rows : rows.filter { !$0.isObsolete }
    if case .collection = filter { return sortedCollection(shown, query: query) }
    guard order == .oldestFirst, Self.canReorder(filter, query: query) else { return shown }
    return shown.reversed()
  }

  /// Whether rows can be dragged into a new order: only in a collection, in its own
  /// order, unsearched — a search's rows are in order of relevance, and their
  /// neighbours are not the collection's.
  public func allowsMoving(in filter: LibraryFilter, query: String) -> Bool {
    guard case .collection = filter else { return false }
    return collectionSort == .manual && query.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// By publication date, then number: a collection is in the reader's order, so
  /// reversing it would not put the oldest first. A search stays in order of
  /// relevance.
  private func sortedCollection(_ rows: [RFCMetadata], query: String) -> [RFCMetadata] {
    guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return rows }
    switch collectionSort {
    case .manual: return rows
    case .newestFirst: return rows.sorted { ($0.date, $0.number) > ($1.date, $1.number) }
    case .oldestFirst: return rows.sorted { ($0.date, $0.number) < ($1.date, $1.number) }
    }
  }
}
