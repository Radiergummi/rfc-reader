import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Every change to collections (#349).
@Suite("Collection store")
@MainActor
struct CollectionStoreTests {
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeContainer() throws -> ModelContainer {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  private func members(of collection: UUID, in context: ModelContext) -> [DocumentID] {
    CollectionSnapshot.fetch(in: context)[collection]?.members ?? []
  }

  @Test func `a new collection is trimmed and goes after the others`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    try CollectionStore.create(named: "  DNS \n", color: .green, in: context)

    let names = CollectionSnapshot.fetch(in: context).collections.map(\.name)
    #expect(names == ["HTTP/3", "DNS"])
  }

  @Test func `a name of only spaces is refused, on create and on rename`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    #expect(throws: CollectionStore.Failure.emptyName) {
      try CollectionStore.create(named: "   ", color: .blue, in: context)
    }
    let collection = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    #expect(throws: CollectionStore.Failure.emptyName) {
      try CollectionStore.rename(collection.identifier, to: "\t", in: context)
    }
    #expect(CollectionSnapshot.fetch(in: context).collections.map(\.name) == ["HTTP/3"])
  }

  @Test func `rename and colour change what the snapshot says`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.rename(id, to: "QUIC", in: context)
    try CollectionStore.setColor(id, to: .orange, in: context)

    let entry = CollectionSnapshot.fetch(in: context)[id]
    #expect(entry?.name == "QUIC")
    #expect(entry?.color == .orange)
  }

  @Test func `adding appends, and adding again changes nothing`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: id, in: context)
    try CollectionStore.add(.rfc(9114), to: id, in: context)
    try CollectionStore.add(.rfc(9000), to: id, in: context)

    #expect(members(of: id, in: context) == [.rfc(9000), .rfc(9114)])
  }

  @Test func `adding to a collection that is gone is an error`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    #expect(throws: CollectionStore.Failure.noSuchCollection) {
      try CollectionStore.add(.rfc(9000), to: UUID(), in: context)
    }
  }

  @Test func `toggling removes every item naming the document`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(9000), position: 2))
    try context.save()

    let isIn = try CollectionStore.toggle(.rfc(9000), in: id, undoManager: nil, in: context)

    #expect(!isIn)
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
    #expect(try CollectionStore.toggle(.rfc(9000), in: id, undoManager: nil, in: context))
    #expect(members(of: id, in: context) == [.rfc(9000)])
  }

  @Test func `deleting a collection deletes its items and nothing else`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let doomed = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let kept = try CollectionStore.create(named: "DNS", color: .green, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: doomed, in: context)
    try CollectionStore.add(.rfc(1035), to: kept, in: context)

    try CollectionStore.delete(doomed, in: context)

    #expect(CollectionSnapshot.fetch(in: context).collections.map(\.id) == [kept])
    let items = try context.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.collectionIdentifier) == [kept])
  }

  @Test func `a move places a document between its visible neighbours`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2, 3] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    try CollectionStore.move(
      .rfc(3), in: id, afterVisible: .rfc(1), beforeVisible: .rfc(2), in: context)
    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])

    try CollectionStore.move(
      .rfc(2), in: id, afterVisible: nil, beforeVisible: .rfc(1), in: context)
    #expect(members(of: id, in: context) == [.rfc(2), .rfc(1), .rfc(3)])
  }

  /// A gap halved until it cannot be split again, and two items at one position:
  /// both renumber rather than collapse.
  @Test func `a move into a gap too narrow renumbers first`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let early = Date(timeIntervalSince1970: 1_000)
    let late = Date(timeIntervalSince1970: 2_000)
    context.insert(
      DocumentCollectionItem(collection: id, document: .rfc(1), position: 1, addedAt: early))
    context.insert(
      DocumentCollectionItem(collection: id, document: .rfc(2), position: 1, addedAt: late))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(3), position: 5))
    try context.save()

    try CollectionStore.move(
      .rfc(3), in: id, afterVisible: .rfc(1), beforeVisible: .rfc(2), in: context)

    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])
    let positions = try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(sortBy: [SortDescriptor(\.position)])
    ).map(\.position)
    #expect(Set(positions).count == 3)
  }

  @Test func `collections move in the sidebar`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let first = try CollectionStore.create(named: "A", color: .blue, in: context).identifier
    let second = try CollectionStore.create(named: "B", color: .blue, in: context).identifier
    let third = try CollectionStore.create(named: "C", color: .blue, in: context).identifier

    try CollectionStore.moveCollection(
      third, afterVisible: nil, beforeVisible: first, in: context)

    #expect(
      CollectionSnapshot.fetch(in: context).collections.map(\.id) == [third, first, second])
  }

  /// A reading path must not lose its place to a mistaken tap.
  @Test func `an undone removal returns to its old place`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2, 3] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    undoManager.beginUndoGrouping()
    try CollectionStore.remove(.rfc(2), from: id, undoManager: undoManager, in: context)
    undoManager.endUndoGrouping()
    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3)])

    undoManager.undo()

    #expect(members(of: id, in: context) == [.rfc(1), .rfc(2), .rfc(3)])
  }
}
