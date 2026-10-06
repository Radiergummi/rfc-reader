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

  /// Counted from a notification observer, which may not capture a `var`.
  @MainActor
  private final class SaveCount {
    var count = 0
  }

  /// What an undo or redo reports failing, which none here should: a collection
  /// gone since, or a document back in it, is nothing to put back, not a failure.
  private static func undoFailed(_ error: any Error) {
    Issue.record(error, "an undo or redo failed")
  }

  private func members(of collection: UUID, in context: ModelContext) throws -> [DocumentID] {
    try CollectionSnapshot.fetch(in: context)[collection]?.members ?? []
  }

  @Test func `a new collection is trimmed and goes after the others`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    try CollectionStore.create(named: "  DNS \n", color: .green, in: context)

    let names = try CollectionSnapshot.fetch(in: context).collections.map(\.name)
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
      try CollectionStore.update(collection.identifier, name: "\t", color: .blue, in: context)
    }
    #expect(try CollectionSnapshot.fetch(in: context).collections.map(\.name) == ["HTTP/3"])
  }

  /// What the editor enables its button by, so the button and the store agree.
  @Test func `a name is valid once it has more than spaces`() {
    #expect(!CollectionStore.isValidName(""))
    #expect(!CollectionStore.isValidName(" \t\n"))
    #expect(CollectionStore.isValidName(" DNS "))
  }

  @Test func `an update renames and recolors in one save`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let saves = SaveCount()
    // The main context posts on the main actor, synchronously from `save`.
    let observer = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: context, queue: nil
    ) { _ in MainActor.assumeIsolated { saves.count += 1 } }
    defer { NotificationCenter.default.removeObserver(observer) }

    try CollectionStore.update(id, name: "QUIC", color: .orange, in: context)

    let entry = try CollectionSnapshot.fetch(in: context)[id]
    #expect(entry?.name == "QUIC")
    #expect(entry?.color == .orange)
    #expect(saves.count == 1)
  }

  @Test func `adding appends, and adding again changes nothing`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: id, in: context)
    try CollectionStore.add(.rfc(9114), to: id, in: context)
    try CollectionStore.add(.rfc(9000), to: id, in: context)

    #expect(try members(of: id, in: context) == [.rfc(9000), .rfc(9114)])
  }

  /// A reading path saved as a collection (#189).
  @Test func `a collection is created with its documents in their order, in one save`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let saves = SaveCount()
    let observer = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: context, queue: nil
    ) { _ in MainActor.assumeIsolated { saves.count += 1 } }
    defer { NotificationCenter.default.removeObserver(observer) }

    let id = try CollectionStore.create(
      named: "Reading Path: RFC 9114", color: .blue,
      documents: [
        .rfc(9000), DocumentID(series: .bcp, number: 14), .rfc(9110), .rfc(9000), .rfc(9114),
      ],
      in: context
    ).identifier

    #expect(try members(of: id, in: context) == [.rfc(9000), .rfc(9110), .rfc(9114)])
    #expect(saves.count == 1)
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

    let isIn = try CollectionStore.toggle(
      .rfc(9000), in: id, undoManager: nil, onUndoFailure: Self.undoFailed, in: context)

    #expect(!isIn)
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
    #expect(
      try CollectionStore.toggle(
        .rfc(9000), in: id, undoManager: nil, onUndoFailure: Self.undoFailed, in: context))
    #expect(try members(of: id, in: context) == [.rfc(9000)])
  }

  @Test func `deleting a collection deletes its items and nothing else`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let doomed = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let kept = try CollectionStore.create(named: "DNS", color: .green, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: doomed, in: context)
    try CollectionStore.add(.rfc(1035), to: kept, in: context)

    try CollectionStore.delete(doomed, in: context)

    #expect(try CollectionSnapshot.fetch(in: context).collections.map(\.id) == [kept])
    let items = try context.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.collectionIdentifier) == [kept])
  }

  @Test func `a move places a document between its visible neighbors`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2, 3] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    try CollectionStore.move(
      .rfc(3), in: id, afterVisible: .rfc(1), beforeVisible: .rfc(2), in: context)
    #expect(try members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])

    try CollectionStore.move(
      .rfc(2), in: id, afterVisible: nil, beforeVisible: .rfc(1), in: context)
    #expect(try members(of: id, in: context) == [.rfc(2), .rfc(1), .rfc(3)])
  }

  /// Sync can leave two items naming one document. The list shows the first, so
  /// a move that left the other behind would leave the document where it was.
  @Test func `a move takes every copy of a document with it`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(1), position: 1))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(2), position: 2))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(1), position: 2.5))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(3), position: 3))
    try context.save()

    try CollectionStore.move(
      .rfc(1), in: id, afterVisible: .rfc(3), beforeVisible: nil, in: context)

    #expect(try members(of: id, in: context) == [.rfc(2), .rfc(3), .rfc(1)])
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

    #expect(try members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])
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
      try CollectionSnapshot.fetch(in: context).collections.map(\.id) == [third, first, second])
  }

  /// Two collections on one position — two devices appending offline — sit in the
  /// sidebar in the snapshot's order, and a move between them must be resolved in
  /// that same order. Inserted in the other order, so a store that breaks the tie
  /// some other way sees them reversed and puts the moved collection after both.
  @Test func `a move between collections tied on position lands between them`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let created = Date(timeIntervalSinceReferenceDate: 0)
    let first = DocumentCollection(name: "A", color: .blue, position: 1, createdAt: created)
    first.identifier = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let second = DocumentCollection(name: "B", color: .blue, position: 1, createdAt: created)
    second.identifier = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    context.insert(second)
    try context.save()
    context.insert(first)
    try context.save()
    let third = try CollectionStore.create(named: "C", color: .blue, in: context).identifier
    #expect(
      try CollectionSnapshot.fetch(in: context).collections.map(\.id)
        == [first.identifier, second.identifier, third])

    try CollectionStore.moveCollection(
      third, afterVisible: first.identifier, beforeVisible: second.identifier, in: context)

    #expect(
      try CollectionSnapshot.fetch(in: context).collections.map(\.id)
        == [first.identifier, third, second.identifier])
  }

  /// Collections list RFCs: a series, or text dropped from another app that happens
  /// to read as one, is not added.
  @Test func `only RFCs are added`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.add(DocumentID(series: .bcp, number: 14), to: id, in: context)
    try CollectionStore.add(.rfc(9000), to: id, in: context)

    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 1)
    #expect(try members(of: id, in: context) == [.rfc(9000)])
  }

  /// Undoing a removal after the collection went, or after the document came back,
  /// must not leave an orphan or a duplicate behind.
  @Test func `an undone removal puts back nothing that is no longer missing`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: id, in: context)

    undoManager.beginUndoGrouping()
    try CollectionStore.remove(
      .rfc(9000), from: id, undoManager: undoManager, onUndoFailure: Self.undoFailed, in: context)
    undoManager.endUndoGrouping()
    try CollectionStore.add(.rfc(9000), to: id, in: context)
    undoManager.undo()
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 1)

    undoManager.beginUndoGrouping()
    try CollectionStore.remove(
      .rfc(9000), from: id, undoManager: undoManager, onUndoFailure: Self.undoFailed, in: context)
    undoManager.endUndoGrouping()
    try CollectionStore.delete(id, in: context)
    undoManager.undo()
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
  }

  @Test func `an undone removal can be redone`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    undoManager.beginUndoGrouping()
    try CollectionStore.remove(
      .rfc(1), from: id, undoManager: undoManager, onUndoFailure: Self.undoFailed, in: context)
    undoManager.endUndoGrouping()
    undoManager.undo()
    #expect(undoManager.canRedo)
    undoManager.redo()

    #expect(try members(of: id, in: context) == [.rfc(2)])
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
    try CollectionStore.remove(
      .rfc(2), from: id, undoManager: undoManager, onUndoFailure: Self.undoFailed, in: context)
    undoManager.endUndoGrouping()
    #expect(try members(of: id, in: context) == [.rfc(1), .rfc(3)])

    undoManager.undo()

    #expect(try members(of: id, in: context) == [.rfc(1), .rfc(2), .rfc(3)])
  }
}
