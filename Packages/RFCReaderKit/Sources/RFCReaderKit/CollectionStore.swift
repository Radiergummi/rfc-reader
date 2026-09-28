import Foundation
import RFCKit
import SwiftData

/// Every change to collections, on a context (#349).
///
/// In the package rather than beside `BookmarkStore` in the App target, which has
/// no test bundle: what happens to a collection is decided here, and tested. Each
/// change saves before it returns, as `BookmarkStore.toggle` does, so the hosted
/// roots on a Mac — separate readers of one store — cannot disagree while a save is
/// pending.
@MainActor
public enum CollectionStore {
  public enum Failure: Error, Equatable {
    case emptyName
    case noSuchCollection
  }

  // MARK: - Collections

  /// A new collection, after the others in the sidebar.
  @discardableResult
  public static func create(
    named name: String, color: CollectionColor, in context: ModelContext
  ) throws -> DocumentCollection {
    let name = try validName(name)
    let last = try collections(in: context).last?.position
    let collection = DocumentCollection(
      name: name, color: color, position: CollectionOrder.appending(after: last))
    context.insert(collection)
    try context.save()
    return collection
  }

  /// The editor's name and colour, in one save.
  public static func update(
    _ identifier: UUID, name: String, color: CollectionColor, in context: ModelContext
  ) throws {
    let name = try validName(name)
    let collection = try collection(identifier, in: context)
    collection.name = name
    collection.color = color
    try context.save()
  }

  /// The collection and its items, in one save. The documents are untouched.
  public static func delete(_ identifier: UUID, in context: ModelContext) throws {
    context.delete(try collection(identifier, in: context))
    for item in try items(in: identifier, context: context) {
      context.delete(item)
    }
    try context.save()
  }

  /// Between the collections either side of the drop point in the sidebar.
  public static func moveCollection(
    _ identifier: UUID, afterVisible above: UUID?, beforeVisible below: UUID?,
    in context: ModelContext
  ) throws {
    var rows = try collections(in: context)
    guard let moving = rows.first(where: { $0.identifier == identifier }) else {
      throw Failure.noSuchCollection
    }
    rows.removeAll { $0.identifier == identifier }
    moving.position = place(
      between: CollectionOrder.neighbours(above: above, below: below, in: rows.map(\.identifier)),
      in: rows, key: \.identifier, position: \.position)
    try context.save()
  }

  // MARK: - Members

  /// At the end. A document already in the collection stays where it is, and one
  /// that is not an RFC is not added: collections list RFCs, and a drop can carry
  /// any text that happens to read as a document.
  public static func add(
    _ document: DocumentID, to identifier: UUID, in context: ModelContext
  ) throws {
    _ = try collection(identifier, in: context)
    guard document.series == .rfc else { return }
    let items = try items(in: identifier, context: context)
    guard !items.contains(where: { $0.documentKey == document.fileStem }) else { return }
    context.insert(
      DocumentCollectionItem(
        collection: identifier, document: document,
        position: CollectionOrder.appending(after: items.last?.position)))
    try context.save()
  }

  /// Every item naming the document, since nothing stops there being two. Undoing
  /// puts it back where it was, not at the end.
  public static func remove(
    _ document: DocumentID, from identifier: UUID, undoManager: UndoManager?,
    in context: ModelContext
  ) throws {
    let removed = try items(in: identifier, context: context)
      .filter { $0.documentKey == document.fileStem }
    guard let first = removed.first else { return }
    let position = first.position
    let addedAt = first.addedAt
    removed.forEach(context.delete)
    try context.save()
    undoManager?.registerUndo(withTarget: context) { context in
      MainActor.assumeIsolated {
        restore(
          document, to: identifier, at: (position, addedAt), undoManager: undoManager,
          in: context)
      }
    }
    undoManager?.setActionName("Remove from Collection")
  }

  /// Undoing a removal: the item back where it was, and the removal again as the
  /// redo. Nothing is put back into a collection that has gone since, or next to a
  /// copy of the document added since — either would leave a row nothing removes.
  private static func restore(
    _ document: DocumentID, to identifier: UUID, at place: (position: Double, addedAt: Date),
    undoManager: UndoManager?, in context: ModelContext
  ) {
    guard (try? collection(identifier, in: context)) != nil,
      let items = try? items(in: identifier, context: context),
      !items.contains(where: { $0.documentKey == document.fileStem })
    else { return }
    context.insert(
      DocumentCollectionItem(
        collection: identifier, document: document, position: place.position,
        addedAt: place.addedAt))
    try? context.save()
    undoManager?.registerUndo(withTarget: context) { context in
      MainActor.assumeIsolated {
        try? remove(document, from: identifier, undoManager: undoManager, in: context)
      }
    }
    undoManager?.setActionName("Remove from Collection")
  }

  /// Removes the document if it is in the collection, adds it otherwise. Answers
  /// whether it is in the collection afterwards.
  @discardableResult
  public static func toggle(
    _ document: DocumentID, in identifier: UUID, undoManager: UndoManager?,
    in context: ModelContext
  ) throws -> Bool {
    let isIn = try items(in: identifier, context: context)
      .contains { $0.documentKey == document.fileStem }
    if isIn {
      try remove(document, from: identifier, undoManager: undoManager, in: context)
    } else {
      try add(document, to: identifier, in: context)
    }
    return !isIn
  }

  /// Between the rows either side of the drop point in the visible list, which may
  /// hide obsolete documents or hold only the rows paged in so far. Every item
  /// naming the document moves: sync can leave two, and the list shows the first.
  public static func move(
    _ document: DocumentID, in identifier: UUID, afterVisible above: DocumentID?,
    beforeVisible below: DocumentID?, in context: ModelContext
  ) throws {
    var rows = try items(in: identifier, context: context)
    let moving = rows.filter { $0.documentKey == document.fileStem }
    guard !moving.isEmpty else { return }
    rows.removeAll { $0.documentKey == document.fileStem }
    let neighbours = CollectionOrder.neighbours(
      above: above?.fileStem, below: below?.fileStem, in: rows.map(\.documentKey))
    let position = place(
      between: neighbours, in: rows, key: \.documentKey, position: \.position)
    for item in moving {
      item.position = position
    }
    try context.save()
  }

  // MARK: - Helpers

  /// The position between two neighbours, renumbering `rows` first when the gap is
  /// too narrow or the neighbours are equal.
  private static func place<Row: AnyObject, Key: Equatable>(
    between neighbours: (before: Key?, after: Key?), in rows: [Row],
    key: KeyPath<Row, Key>, position: ReferenceWritableKeyPath<Row, Double>
  ) -> Double {
    func current(_ wanted: Key?) -> Double? {
      wanted.flatMap { wanted in rows.first { $0[keyPath: key] == wanted }?[keyPath: position] }
    }
    if case .position(let value) = CollectionOrder.placement(
      between: current(neighbours.before), and: current(neighbours.after))
    {
      return value
    }
    for (row, value) in zip(rows, CollectionOrder.renumbered(count: rows.count)) {
      row[keyPath: position] = value
    }
    guard
      case .position(let value) = CollectionOrder.placement(
        between: current(neighbours.before), and: current(neighbours.after))
    else {
      preconditionFailure("renumbered neighbours are a spacing apart")
    }
    return value
  }

  private static func validName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw Failure.emptyName }
    return trimmed
  }

  private static func collections(in context: ModelContext) throws -> [DocumentCollection] {
    try context.fetch(
      FetchDescriptor<DocumentCollection>(sortBy: [
        SortDescriptor(\.position), SortDescriptor(\.createdAt),
      ]))
  }

  private static func collection(
    _ identifier: UUID, in context: ModelContext
  ) throws -> DocumentCollection {
    let descriptor = FetchDescriptor<DocumentCollection>(
      predicate: #Predicate { $0.identifier == identifier })
    guard let collection = try context.fetch(descriptor).first else {
      throw Failure.noSuchCollection
    }
    return collection
  }

  /// In `(position, addedAt, documentKey)` order.
  private static func items(
    in identifier: UUID, context: ModelContext
  ) throws -> [DocumentCollectionItem] {
    let target: UUID? = identifier
    return try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(
        predicate: #Predicate { $0.collectionIdentifier == target },
        sortBy: [
          SortDescriptor(\.position), SortDescriptor(\.addedAt), SortDescriptor(\.documentKey),
        ]))
  }
}
