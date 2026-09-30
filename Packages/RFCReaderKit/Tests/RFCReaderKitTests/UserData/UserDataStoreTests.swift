import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Bookmarks and reading positions, on an in-memory store.
@Suite("Bookmark and reading position stores")
@MainActor
struct UserDataStoreTests {
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeContainer() throws -> ModelContainer {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  private func rowCount<Row: PersistentModel>(_: Row.Type, in context: ModelContext) throws -> Int {
    try context.fetchCount(FetchDescriptor<Row>())
  }

  // MARK: - Bookmarks

  @Test func `toggling adds a bookmark and toggling again removes it`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context) == [.rfc(9110)])

    try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context).isEmpty)
  }

  @Test func `removing a bookmark removes every row naming the document`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    context.insert(Bookmark(document: .rfc(9110), title: "One"))
    context.insert(Bookmark(document: .rfc(9110), title: "Two"))
    context.insert(Bookmark(document: DocumentID(series: .bcp, number: 14), title: "Keywords"))
    try context.save()

    try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    #expect(
      try BookmarkStore.bookmarkedDocuments(in: context) == [DocumentID(series: .bcp, number: 14)])
  }

  @Test func `a toggle is saved before it returns`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: context)
    #expect(!context.hasChanges)
  }

  // MARK: - Reading positions

  @Test func `saving a place twice keeps one row, with the later place`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let first = ReadingPlace(anchor: "section-1", offset: 0)
    let second = ReadingPlace(anchor: "section-4.2", offset: 0)
    try ReadingPositionStore.save(first, for: .rfc(9110), in: context)
    try ReadingPositionStore.save(second, for: .rfc(9110), in: context)

    #expect(try rowCount(ReadingPosition.self, in: context) == 1)
    #expect(try ReadingPositionStore.position(for: .rfc(9110), in: context)?.place == second)
    #expect(!context.hasChanges)
  }

  @Test func `marking a document opened dates it and leaves its place alone`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let place = ReadingPlace(anchor: "section-3", offset: 0)
    let left = Date(timeIntervalSince1970: 1_000)
    let opened = Date(timeIntervalSince1970: 2_000)
    try ReadingPositionStore.save(place, for: .rfc(9110), at: left, in: context)
    try ReadingPositionStore.markOpened(.rfc(9110), at: opened, in: context)

    let position = try ReadingPositionStore.position(for: .rfc(9110), in: context)
    #expect(position?.place == place)
    #expect(position?.updatedAt == opened)
  }

  @Test func `a document never opened has no position`() throws {
    let container = try makeContainer()
    #expect(try ReadingPositionStore.position(for: .rfc(9110), in: container.mainContext) == nil)
  }

  /// RFC 1, BCP 1 and STD 1 share a number, not a position.
  @Test func `documents with one number keep positions of their own`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let bcp = DocumentID(series: .bcp, number: 1)
    try ReadingPositionStore.save(
      ReadingPlace(anchor: "section-1", offset: 0), for: .rfc(1), in: context)
    try ReadingPositionStore.save(
      ReadingPlace(anchor: "section-2", offset: 0), for: bcp, in: context)

    #expect(
      try ReadingPositionStore.position(for: .rfc(1), in: context)?.place?.anchor == "section-1")
    #expect(try ReadingPositionStore.position(for: bcp, in: context)?.place?.anchor == "section-2")
  }

  @Test func `a document opened for the first time has a row and no place`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try ReadingPositionStore.markOpened(.rfc(2119), in: context)

    let position = try ReadingPositionStore.position(for: .rfc(2119), in: context)
    #expect(position != nil)
    #expect(position?.place == nil)
  }

  @Test func `recently read lists the latest first`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try ReadingPositionStore.markOpened(
      .rfc(1), at: Date(timeIntervalSince1970: 1_000), in: context)
    try ReadingPositionStore.markOpened(
      .rfc(3), at: Date(timeIntervalSince1970: 3_000), in: context)
    try ReadingPositionStore.markOpened(
      .rfc(2), at: Date(timeIntervalSince1970: 2_000), in: context)

    #expect(try ReadingPositionStore.recentlyRead(in: context) == [.rfc(3), .rfc(2), .rfc(1)])
  }

  @Test func `the recently read count is of the RFCs recently read lists`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try ReadingPositionStore.markOpened(.rfc(1), in: context)
    try ReadingPositionStore.markOpened(.rfc(2), in: context)
    try ReadingPositionStore.markOpened(DocumentID(series: .bcp, number: 14), in: context)

    #expect(try ReadingPositionStore.recentlyReadRFCCount(in: context) == 2)
  }

  @Test func `read since a date leaves out what was read before it`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try ReadingPositionStore.markOpened(
      .rfc(1), at: Date(timeIntervalSince1970: 1_000), in: context)
    try ReadingPositionStore.markOpened(
      .rfc(2), at: Date(timeIntervalSince1970: 3_000), in: context)

    let since = Date(timeIntervalSince1970: 2_000)
    #expect(try ReadingPositionStore.read(since: since, in: context) == [.rfc(2)])
  }
}
