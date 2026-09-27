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

  @Test func `a document's key is its file stem, and names it again`() {
    #expect(UserDataKey.key(for: .rfc(9110)) == "rfc9110")
    #expect(UserDataKey.document(for: "rfc9110") == .rfc(9110))
  }

  /// A bare number could not: RFC 1, BCP 1 and STD 1 all have the number 1.
  @Test func `documents of different series with one number have different keys`() {
    let bcp = DocumentID(series: .bcp, number: 1)
    #expect(UserDataKey.key(for: .rfc(1)) != UserDataKey.key(for: bcp))
    #expect(UserDataKey.document(for: UserDataKey.key(for: bcp)) == bcp)
  }

  @Test func `a key that names no document is nil`() {
    #expect(UserDataKey.document(for: "") == nil)
    #expect(UserDataKey.document(for: "notes") == nil)
    #expect(UserDataKey.document(for: "RFC 9110") == nil)
  }

  // MARK: - Reading place

  @Test func `a reading position keeps the place, anchor and offset`() {
    let position = ReadingPosition(
      document: .rfc(9110), place: ReadingPlace(anchor: "section-4.2", offset: 118))
    #expect(position.place == ReadingPlace(anchor: "section-4.2", offset: 118))
    #expect(ReadingPosition(document: .rfc(9110), place: nil).place == nil)
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

  @Test func `a new store opens at version 2`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let container = try UserData.container(configurations: ModelConfiguration(url: url))
    let context = ModelContext(container)
    context.insert(Bookmark(document: .rfc(9110), title: "HTTP Semantics"))
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)
  }

  // MARK: - Uniqueness

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
