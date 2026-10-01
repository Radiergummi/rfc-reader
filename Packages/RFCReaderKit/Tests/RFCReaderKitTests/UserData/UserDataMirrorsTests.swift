import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Which of the library's mirrors of the store a save refreshes (#603).
@Suite("User data mirrors")
@MainActor
struct UserDataMirrorsTests {
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeContainer() throws -> ModelContainer {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  /// What each save of the context said it changed, as the library's observer reads it.
  /// On the main actor, which makes it `Sendable`, so the observer's `@Sendable`
  /// closure can hold it: a nested type does not take the suite's isolation.
  @MainActor
  private final class Saves {
    var entityNames: [Set<String>?] = []
  }

  /// Runs `change` with every save of `context` recorded.
  private func recordingSaves(
    of context: ModelContext, _ change: () throws -> Void
  ) rethrows -> [Set<String>?] {
    let saves = Saves()
    // The main context posts on the main actor, synchronously from `save`.
    let observer = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: context, queue: nil
    ) { notification in
      let names = UserDataMirrors.changedEntityNames(in: notification.userInfo)
      MainActor.assumeIsolated { saves.entityNames.append(names) }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    try change()
    return saves.entityNames
  }

  // MARK: - From entities to mirrors

  @Test func `a reading position save refreshes only the recently read count`() {
    #expect(UserDataMirrors.changed(byEntities: ["ReadingPosition"]) == .recentlyReadCount)
  }

  @Test func `a bookmark save refreshes only the bookmarks`() {
    #expect(UserDataMirrors.changed(byEntities: ["Bookmark"]) == .bookmarks)
  }

  @Test func `a collection or an item in one refreshes only the collections`() {
    #expect(UserDataMirrors.changed(byEntities: ["DocumentCollection"]) == .collections)
    #expect(UserDataMirrors.changed(byEntities: ["DocumentCollectionItem"]) == .collections)
  }

  @Test func `a save of several entities refreshes each one's mirror`() {
    #expect(
      UserDataMirrors.changed(byEntities: ["Bookmark", "DocumentCollectionItem"])
        == [.bookmarks, .collections])
  }

  @Test func `a save that changed nothing a mirror reads refreshes nothing`() {
    #expect(UserDataMirrors.changed(byEntities: []).isEmpty)
    #expect(UserDataMirrors.changed(byEntities: ["SomethingElse"]).isEmpty)
  }

  @Test func `an unknown save refreshes every mirror`() {
    #expect(UserDataMirrors.changed(byEntities: nil) == .all)
  }

  /// The names in the table are SwiftData's own, and a model added to the schema
  /// without a mirror for it fails here rather than going unrefreshed.
  @Test func `every entity of the schema feeds a mirror`() {
    let entities = Schema(versionedSchema: SchemaV4.self).entities.map(\.name)
    #expect(entities.count == SchemaV4.models.count)
    for entity in entities {
      #expect(!UserDataMirrors.changed(byEntities: [entity]).isEmpty, "\(entity)")
    }
  }

  // MARK: - From a notification to entities

  @Test func `a notification that names no changes is unknown`() {
    #expect(UserDataMirrors.changedEntityNames(in: nil) == nil)
    #expect(UserDataMirrors.changedEntityNames(in: [:]) == nil)
    #expect(UserDataMirrors.changedEntityNames(in: ["unrelated": 1]) == nil)
  }

  @Test func `a change list of an unexpected type is unknown`() {
    let key = ModelContext.NotificationKey.updatedIdentifiers.rawValue
    #expect(UserDataMirrors.changedEntityNames(in: [key: ["rfc9110"]]) == nil)
  }

  /// Through a real save, so the keys, the value type and the entity names are
  /// SwiftData's rather than this test's idea of them.
  @Test func `saving a reading position names only the reading position`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let place = ReadingPlace(anchor: "section-1", offset: 0)
    let saves = try recordingSaves(of: context) {
      try ReadingPositionStore.save(place, for: .rfc(9110), in: context)
      try ReadingPositionStore.save(place, for: .rfc(9110), in: context)
    }
    // The first save inserts the row and the second updates it.
    #expect(saves == [["ReadingPosition"], ["ReadingPosition"]])
    #expect(saves.allSatisfy { UserDataMirrors.changed(byEntities: $0) == .recentlyReadCount })
  }

  @Test func `toggling a bookmark names only the bookmark`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let saves = try recordingSaves(of: context) {
      try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
      try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    }
    // An insert, then a delete.
    #expect(saves == [["Bookmark"], ["Bookmark"]])
  }

  @Test func `adding to a collection refreshes the collections`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let saves = try recordingSaves(of: context) {
      try CollectionStore.add(.rfc(9000), to: id, in: context)
    }
    #expect(!saves.isEmpty)
    #expect(saves.allSatisfy { UserDataMirrors.changed(byEntities: $0) == .collections })
  }
}
