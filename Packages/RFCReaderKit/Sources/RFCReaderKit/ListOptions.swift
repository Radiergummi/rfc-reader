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

  public var order: Order
  public var showsObsolete: Bool

  public init(order: Order = .newestFirst, showsObsolete: Bool = true) {
    self.order = order
    self.showsObsolete = showsObsolete
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
    guard order == .oldestFirst, Self.canReorder(filter, query: query) else { return shown }
    return shown.reversed()
  }
}
