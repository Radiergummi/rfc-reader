import Foundation
import RFCKit

/// The library's settings as user defaults hold them: each key and its default,
/// once (#713). Read through `LibrarySettings`.
public enum LibraryPreferences {
  /// Whether a new tab's unsearched lists show obsoleted documents.
  public static let showsObsoleteInListsKey = "libraryShowsObsoleteInLists"
  /// Whether a new tab's searches show obsoleted documents.
  public static let showsObsoleteInSearchKey = "libraryShowsObsoleteInSearch"
  public static let defaultShowsObsolete = true

  /// The order a new tab's lists start in: a `ListOptions.Order`'s raw value.
  public static let orderKey = "libraryOrder"
  public static let defaultOrder = ListOptions.Order.newestFirst

  /// Whether a new tab's searches look only in current documents.
  public static let searchesCurrentOnlyKey = "searchesCurrentOnly"
  public static let defaultSearchesCurrentOnly = false

  /// The stream a new tab's searches look in: a `PublicationStream`'s raw value, or
  /// empty for every stream.
  public static let searchStreamKey = "searchStream"
  public static let defaultSearchStream = ""

  /// Whether the April 1st RFCs are listed, searched and in Just Published.
  public static let showsAprilFirstKey = "showsAprilFirstRFCs"
  public static let defaultShowsAprilFirst = true

  /// Whether a list's rows show their status badge.
  public static let showsStatusBadgesKey = "showsStatusBadges"
  public static let defaultShowsStatusBadges = true
}

/// The library's settings, decoded from user defaults into one value (#713): the
/// defaults a new tab's list starts with, and the April 1st setting, which holds for
/// every list. The status badges are read by the rows themselves.
public struct LibrarySettings: Hashable, Sendable {
  public var showsObsoleteInLists: Bool
  public var showsObsoleteInSearch: Bool
  public var order: ListOptions.Order
  public var searchScope: SearchScope
  public var showsAprilFirst: Bool

  public init(
    showsObsoleteInLists: Bool = LibraryPreferences.defaultShowsObsolete,
    showsObsoleteInSearch: Bool = LibraryPreferences.defaultShowsObsolete,
    order: ListOptions.Order = LibraryPreferences.defaultOrder,
    searchScope: SearchScope = SearchScope(
      currentOnly: LibraryPreferences.defaultSearchesCurrentOnly),
    showsAprilFirst: Bool = LibraryPreferences.defaultShowsAprilFirst
  ) {
    self.showsObsoleteInLists = showsObsoleteInLists
    self.showsObsoleteInSearch = showsObsoleteInSearch
    self.order = order
    self.searchScope = searchScope
    self.showsAprilFirst = showsAprilFirst
  }

  /// What `defaults` holds, each setting falling back to its default where nothing
  /// is stored, or something of the wrong type, or a value this version does not know.
  public init(defaults: UserDefaults) {
    typealias Keys = LibraryPreferences
    func flag(_ key: String, _ fallback: Bool) -> Bool {
      defaults.object(forKey: key) as? Bool ?? fallback
    }
    self.init(
      showsObsoleteInLists: flag(Keys.showsObsoleteInListsKey, Keys.defaultShowsObsolete),
      showsObsoleteInSearch: flag(Keys.showsObsoleteInSearchKey, Keys.defaultShowsObsolete),
      order: defaults.string(forKey: Keys.orderKey).flatMap(ListOptions.Order.init)
        ?? Keys.defaultOrder,
      searchScope: SearchScope(
        currentOnly: flag(Keys.searchesCurrentOnlyKey, Keys.defaultSearchesCurrentOnly),
        stream: defaults.string(forKey: Keys.searchStreamKey).flatMap(PublicationStream.init)),
      showsAprilFirst: flag(Keys.showsAprilFirstKey, Keys.defaultShowsAprilFirst)
    )
  }

  /// The options a new tab starts with. Collections keep their own default order,
  /// manual, and Hide Read is a tab's own filter, off.
  public var listOptions: ListOptions {
    ListOptions(
      order: order, showsObsolete: showsObsoleteInLists,
      showsObsoleteInSearch: showsObsoleteInSearch, searchScope: searchScope,
      showsAprilFirst: showsAprilFirst)
  }
}
