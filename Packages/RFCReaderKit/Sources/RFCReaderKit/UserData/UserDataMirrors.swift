import Foundation
import SwiftData

/// The sets the app keeps read from the store, and which of them a save can have
/// changed (#603).
///
/// `LibraryModel` keeps three: the bookmarked documents, the collections and the
/// Recently Read count. It read all three again on every save, and most saves only
/// record a reading position, so the bookmark and collection fetches ran for
/// nothing — `CollectionSnapshot.fetch` reads every collection and every item. A
/// save's notification names the rows it inserted, updated and deleted, and each
/// row's entity says which mirror it feeds.
public struct UserDataMirrors: OptionSet, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// `BookmarkStore.bookmarkedDocuments`, read from `Bookmark` rows alone.
  public static let bookmarks = UserDataMirrors(rawValue: 1 << 0)
  /// `CollectionSnapshot.fetch`, read from collections and their items.
  public static let collections = UserDataMirrors(rawValue: 1 << 1)
  /// `ReadingPositionStore.recentlyReadCount`, read from `ReadingPosition` rows
  /// alone: a bookmark is not a reading.
  public static let recentlyReadCount = UserDataMirrors(rawValue: 1 << 2)

  public static let all: UserDataMirrors = [.bookmarks, .collections, .recentlyReadCount]

  /// The mirrors a save of rows of these entities can have changed. Nil — the
  /// notification did not say what it saved — is every mirror, as before #603. An
  /// entity no mirror reads changes none.
  public static func changed(byEntities entityNames: Set<String>?) -> UserDataMirrors {
    guard let entityNames else { return .all }
    return entityNames.reduce(into: []) { mirrors, name in
      mirrors.formUnion(fed[name] ?? [])
    }
  }

  /// Which mirror each entity feeds, by the name SwiftData gives the entity: the
  /// model's unqualified class name, which is what `String(describing:)` gives the
  /// type too. `UserDataMirrorsTests` holds this to the schema's own entity names,
  /// so a model added to the schema without a line here fails there.
  private static let fed: [String: UserDataMirrors] = [
    String(describing: Bookmark.self): .bookmarks,
    String(describing: ReadingPosition.self): .recentlyReadCount,
    String(describing: DocumentCollection.self): .collections,
    String(describing: DocumentCollectionItem.self): .collections,
  ]

  /// The entity names of the rows a `ModelContext.didSave` notification says were
  /// inserted, updated or deleted. Nil when its `userInfo` carries none of the three
  /// keys, or any of them with a value that is not `[PersistentIdentifier]`: the
  /// save is then unknown, and every mirror is refreshed, as before #603.
  ///
  /// Takes the `userInfo` rather than the `Notification`, which is not `Sendable`:
  /// the observer reads this first and hands only the set to the main actor.
  public static func changedEntityNames(in userInfo: [AnyHashable: Any]?) -> Set<String>? {
    let keys: [ModelContext.NotificationKey] = [
      .insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers,
    ]
    var names: Set<String> = []
    var foundAny = false
    for key in keys {
      guard let value = userInfo?[key.rawValue] else { continue }
      guard let identifiers = value as? [PersistentIdentifier] else { return nil }
      foundAny = true
      names.formUnion(identifiers.map(\.entityName))
    }
    return foundAny ? names : nil
  }
}
