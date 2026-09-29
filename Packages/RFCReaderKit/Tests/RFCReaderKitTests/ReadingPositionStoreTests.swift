import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// The one place a reading position is read or written (#135).
@Suite("Reading position store")
@MainActor
struct ReadingPositionStoreTests {
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeContainer() throws -> ModelContainer {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  private func positions(in context: ModelContext) throws -> [ReadingPosition] {
    try context.fetch(FetchDescriptor<ReadingPosition>())
  }

  @Test func `a document never opened has no position`() throws {
    let container = try makeContainer()
    #expect(ReadingPositionStore.stored(for: .rfc(9110), in: container.mainContext) == nil)
  }

  /// Opening dates the entry without a place, so the reader's restore is not
  /// undone.
  @Test func `opening a document dates it and records no place`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let opened = Date(timeIntervalSince1970: 1_000)
    ReadingPositionStore.markAsRead(.rfc(9110), at: opened, in: context)

    let stored = try #require(ReadingPositionStore.stored(for: .rfc(9110), in: context))
    #expect(stored.updatedAt == opened)
    #expect(stored.place == nil)
  }

  @Test func `opening again keeps the place and moves the date`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let place = ReadingPlace(anchor: "section-4.2", offset: 0)
    ReadingPositionStore.save(
      place, for: .rfc(9110), at: Date(timeIntervalSince1970: 1), in: context)
    ReadingPositionStore.markAsRead(.rfc(9110), at: Date(timeIntervalSince1970: 2), in: context)

    let stored = try #require(ReadingPositionStore.stored(for: .rfc(9110), in: context))
    #expect(stored.place == place)
    #expect(stored.updatedAt == Date(timeIntervalSince1970: 2))
    #expect(try positions(in: context).count == 1)
  }

  @Test func `leaving a document saves its place over the one before`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    ReadingPositionStore.markAsRead(.rfc(9110), at: Date(timeIntervalSince1970: 1), in: context)
    let place = ReadingPlace(anchor: "section-8.3", offset: 0)
    ReadingPositionStore.save(
      place, for: .rfc(9110), at: Date(timeIntervalSince1970: 3), in: context)

    let stored = try #require(ReadingPositionStore.stored(for: .rfc(9110), in: context))
    #expect(stored.place == place)
    #expect(stored.updatedAt == Date(timeIntervalSince1970: 3))
    #expect(try positions(in: context).count == 1)
  }

  /// RFC 1, BCP 1 and STD 1 share a number, not a position.
  @Test func `documents with one number keep positions of their own`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let bcp = DocumentID(series: .bcp, number: 1)
    ReadingPositionStore.save(
      ReadingPlace(anchor: "section-1", offset: 0), for: .rfc(1), in: context)
    ReadingPositionStore.save(
      ReadingPlace(anchor: "section-2", offset: 0), for: bcp, in: context)

    #expect(ReadingPositionStore.stored(for: .rfc(1), in: context)?.place?.anchor == "section-1")
    #expect(ReadingPositionStore.stored(for: bcp, in: context)?.place?.anchor == "section-2")
  }
}
