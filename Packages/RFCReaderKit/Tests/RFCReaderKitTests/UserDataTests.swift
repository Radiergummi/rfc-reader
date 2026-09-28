import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// The reader's own data (#152): keyed on the document, in CloudKit's shape, and
/// migrated from the store every existing install already has without losing a row.
@Suite("User data")
@MainActor
struct UserDataTests {
  // MARK: - Keys

  /// A bare number could not: RFC 1, BCP 1 and STD 1 all have the number 1.
  @Test func `documents of different series with one number have different keys`() {
    let bcp = DocumentID(series: .bcp, number: 1)
    let bookmarks = [Bookmark(document: .rfc(1), title: ""), Bookmark(document: bcp, title: "")]
    #expect(bookmarks.map(\.documentKey) == ["rfc1", "bcp1"])
    #expect(bookmarks.map(\.document) == [.rfc(1), bcp])
  }

  // MARK: - Reading place

  @Test func `a reading position keeps the place, anchor and offset`() {
    let position = ReadingPosition(
      document: .rfc(9110), place: ReadingPlace(anchor: "section-4.2", offset: 118))
    #expect(position.place == ReadingPlace(anchor: "section-4.2", offset: 118))
    #expect(ReadingPosition(document: .rfc(9110), place: nil).place == nil)
  }

  /// The first character of a document, ahead of its first anchor, is a place, not
  /// the absence of one.
  @Test func `a place ahead of the first anchor is kept`() {
    let start = ReadingPlace(anchor: nil, offset: 0)
    #expect(ReadingPosition(document: .rfc(9110), place: start).place == start)
  }

  // MARK: - Migration

  private func temporaryStore() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "user.store")
  }

  /// The store every install already has, written by today's models, opened by the
  /// new ones: every row survives, keyed on its RFC, with its title, dates and
  /// section.
  @Test func `a version 1 store migrates without losing a row`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let read = Date(timeIntervalSince1970: 1_750_000_000)

    do {
      // Unversioned, as every install's store was made: `ModelContainer(for:)` over
      // the models, with no `VersionedSchema`. SwiftData has to recognise it as V1
      // by its models alone.
      let legacy = try ModelContainer(
        for: SchemaV1.Bookmark.self, SchemaV1.ReadingPosition.self,
        configurations: ModelConfiguration(url: url))
      let context = ModelContext(legacy)
      context.insert(SchemaV1.Bookmark(number: 9110, title: "HTTP Semantics", createdAt: created))
      context.insert(SchemaV1.Bookmark(number: 2119, title: "Key words", createdAt: created))
      context.insert(
        SchemaV1.ReadingPosition(number: 9110, sectionAnchor: "section-8.3", updatedAt: read))
      context.insert(SchemaV1.ReadingPosition(number: 1149, sectionAnchor: nil, updatedAt: read))
      try context.save()
    }

    let migrated = try UserData.container(configurations: ModelConfiguration(url: url))
    let context = ModelContext(migrated)
    let bookmarks = try context.fetch(
      FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.documentKey)]))
    #expect(bookmarks.map(\.documentKey) == ["rfc2119", "rfc9110"])
    #expect(bookmarks.map(\.title) == ["Key words", "HTTP Semantics"])
    #expect(bookmarks.allSatisfy { $0.createdAt == created })
    #expect(bookmarks.map(\.document) == [.rfc(2119), .rfc(9110)])

    let positions = try context.fetch(
      FetchDescriptor<ReadingPosition>(sortBy: [SortDescriptor(\.documentKey)]))
    #expect(positions.map(\.documentKey) == ["rfc1149", "rfc9110"])
    #expect(positions.map(\.place) == [nil, ReadingPlace(anchor: "section-8.3", offset: 0)])
    #expect(positions.allSatisfy { $0.updatedAt == read })
  }

  /// A launch that stopped between the two stages left the store at V2, the
  /// numbers still beside keys not yet written. The next launch finishes the job.
  @Test func `a store left between the stages finishes migrating`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let read = Date(timeIntervalSince1970: 1_750_000_000)

    do {
      let halfway = try ModelContainer(
        for: Schema(versionedSchema: SchemaV2.self), configurations: ModelConfiguration(url: url))
      let context = ModelContext(halfway)
      context.insert(SchemaV2.Bookmark(number: 9110, title: "HTTP Semantics"))
      context.insert(
        SchemaV2.ReadingPosition(number: 9110, sectionAnchor: "section-8.3", updatedAt: read))
      context.insert(SchemaV2.ReadingPosition(number: 1149, sectionAnchor: nil, updatedAt: read))
      try context.save()
    }

    let migrated = try UserData.container(configurations: ModelConfiguration(url: url))
    let context = ModelContext(migrated)
    #expect(try context.fetch(FetchDescriptor<Bookmark>()).map(\.document) == [.rfc(9110)])
    let positions = try context.fetch(
      FetchDescriptor<ReadingPosition>(sortBy: [SortDescriptor(\.documentKey)]))
    #expect(positions.map(\.documentKey) == ["rfc1149", "rfc9110"])
    #expect(positions.map(\.place) == [nil, ReadingPlace(anchor: "section-8.3", offset: 0)])
    #expect(positions.allSatisfy { $0.updatedAt == read })
  }

  @Test func `a new store keeps what is written to it`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    do {
      let container = try UserData.container(configurations: ModelConfiguration(url: url))
      let context = ModelContext(container)
      context.insert(Bookmark(document: .rfc(9110), title: "HTTP Semantics"))
      try context.save()
    }
    let reopened = try UserData.container(configurations: ModelConfiguration(url: url))
    let bookmarks = try ModelContext(reopened).fetch(FetchDescriptor<Bookmark>())
    #expect(bookmarks.map(\.document) == [.rfc(9110)])
  }

  /// V3 to V4 only adds the collections' tables: every existing row survives.
  @Test func `a version 3 store migrates to version 4 without losing a row`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let read = Date(timeIntervalSince1970: 1_750_000_000)

    do {
      let previous = try ModelContainer(
        for: Schema(versionedSchema: SchemaV3.self), configurations: ModelConfiguration(url: url))
      let context = ModelContext(previous)
      context.insert(SchemaV3.Bookmark(document: .rfc(9110), title: "HTTP Semantics"))
      context.insert(
        SchemaV3.ReadingPosition(
          document: .rfc(9110), place: ReadingPlace(anchor: "section-8.3", offset: 4),
          updatedAt: read))
      try context.save()
    }

    let migrated = try UserData.container(configurations: ModelConfiguration(url: url))
    let context = ModelContext(migrated)
    #expect(try context.fetch(FetchDescriptor<Bookmark>()).map(\.document) == [.rfc(9110)])
    let positions = try context.fetch(FetchDescriptor<ReadingPosition>())
    #expect(positions.map(\.place) == [ReadingPlace(anchor: "section-8.3", offset: 4)])
    #expect(try context.fetch(FetchDescriptor<DocumentCollection>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
  }

  /// A constant default would give every row one identifier.
  @Test func `two new collections get different identifiers`() {
    let first = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let second = DocumentCollection(name: "DNS", color: .green, position: 2)
    #expect(first.identifier != second.identifier)
  }

  @Test func `a new store keeps a collection and its items`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let identifier: UUID
    do {
      let container = try UserData.container(configurations: ModelConfiguration(url: url))
      let context = ModelContext(container)
      let collection = DocumentCollection(name: "HTTP/3", color: .teal, position: 1)
      identifier = collection.identifier
      context.insert(collection)
      context.insert(
        DocumentCollectionItem(collection: identifier, document: .rfc(9114), position: 1))
      try context.save()
    }
    let reopened = ModelContext(
      try UserData.container(configurations: ModelConfiguration(url: url)))
    let collections = try reopened.fetch(FetchDescriptor<DocumentCollection>())
    #expect(collections.map(\.name) == ["HTTP/3"])
    #expect(collections.map(\.color) == [.teal])
    let items = try reopened.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.collectionIdentifier) == [identifier])
    #expect(items.map(\.document) == [.rfc(9114)])
  }

  // MARK: - Uniqueness

  /// The earliest item stays, so the place the reader first gave the document does.
  @Test func `duplicate items in one collection are merged, keeping the earliest`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    context.insert(collection)
    let id = collection.identifier
    context.insert(
      DocumentCollectionItem(
        collection: id, document: .rfc(9114), position: 5,
        addedAt: Date(timeIntervalSince1970: 2_000)))
    context.insert(
      DocumentCollectionItem(
        collection: id, document: .rfc(9114), position: 1,
        addedAt: Date(timeIntervalSince1970: 1_000)))
    try context.save()

    try UserData.deduplicate(context)

    let items = try context.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.position) == [1])
  }

  @Test func `one document in two collections is not a duplicate`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    try context.save()

    try UserData.deduplicate(context)

    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 2)
  }

  /// Under sync, items can arrive before their collection. Deleting them would
  /// sync the deletion back and empty the collection where it was made.
  @Test func `items of a collection not in the store are kept`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    try context.save()

    try UserData.deduplicate(context)

    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 1)
  }

  /// With no unique constraint, two rows can name one document; the newest stays.
  @Test func `duplicates are merged, keeping the newest`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    context.insert(Bookmark(document: .rfc(9110), title: "old", createdAt: older))
    context.insert(Bookmark(document: .rfc(9110), title: "new", createdAt: newer))
    context.insert(Bookmark(document: .rfc(2119), title: "other", createdAt: older))
    context.insert(ReadingPosition(document: .rfc(9110), place: nil, updatedAt: older))
    context.insert(
      ReadingPosition(
        document: .rfc(9110), place: ReadingPlace(anchor: "s", offset: 1), updatedAt: newer))
    try context.save()

    try UserData.deduplicate(context)

    let bookmarks = try context.fetch(
      FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.documentKey)]))
    #expect(bookmarks.map(\.title) == ["other", "new"])
    let positions = try context.fetch(FetchDescriptor<ReadingPosition>())
    #expect(positions.map(\.place) == [ReadingPlace(anchor: "s", offset: 1)])
  }
}
