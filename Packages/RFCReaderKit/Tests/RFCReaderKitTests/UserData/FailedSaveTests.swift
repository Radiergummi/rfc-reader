import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// A change whose save fails is not left pending on the main context (#1002): each is
/// made in a context of its own, thrown away with it, so the next save, of anything,
/// cannot commit it behind the reader's back, and a retry starts from what the store
/// holds.
@Suite("Failed saves of the user's data")
@MainActor
final class FailedSaveTests {
  /// Where a test's store on disk is made, removed with the test.
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: "failed-save-\(UUID().uuidString)")

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  /// A mirror of a store on disk holding what `seed` saved, opened again refusing
  /// every save. Each test holds the mirror, which holds the container: a context
  /// does not keep its container alive, and one freed under it traps.
  private func makeReadOnlyMirror(seed: (ModelContext) throws -> Void = { _ in }) throws
    -> UserDataMirror
  {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "user.store")
    do {
      let writable = try UserData.container(configurations: ModelConfiguration(url: url))
      try seed(writable.mainContext)
    }
    let mirror = UserDataMirror(
      container: try UserData.container(
        configurations: ModelConfiguration(url: url, allowsSave: false)))
    mirror.start()
    return mirror
  }

  private var model: ModelText {
    ModelText(
      Fixtures.document(
        .paragraph(Paragraph(text: "The quick brown fox jumps over the lazy dog.", anchor: "p-1"))
      ))
  }

  @Test func `a bookmark whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext

    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")

    #expect(!context.hasChanges)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context).isEmpty)
    #expect(mirror.bookmarkedDocuments.isEmpty)
  }

  /// Nor is an undo registered for a removal that was thrown away.
  @Test func `a bookmark's removal whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror {
      try BookmarkStore.toggle(.rfc(9110), title: "HTTP Semantics", in: $0)
    }
    let context = mirror.container.mainContext
    let undoManager = UndoManager()

    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics", undoManager: undoManager)

    #expect(!context.hasChanges)
    #expect(try BookmarkStore.bookmarkedDocuments(in: context) == [.rfc(9110)])
    #expect(!undoManager.canUndo)
  }

  @Test func `a Keep Offline mark whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext

    #expect(throws: (any Error).self) { try mirror.setMarked(.rfc(9110), true) }

    #expect(!context.hasChanges)
    #expect(try OfflineMarkStore.markedDocuments(in: context).isEmpty)
  }

  @Test func `a follow whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext

    #expect(throws: (any Error).self) { try mirror.setFollowed("httpbis", true) }

    #expect(!context.hasChanges)
    #expect(try FollowedGroupStore.followedGroups(in: context).isEmpty)
  }

  @Test func `a collection's deletion whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror {
      _ = try CollectionStore.create(named: "HTTP", color: .blue, in: $0)
    }
    let context = mirror.container.mainContext
    let identifier = try #require(mirror.collections.collections.first?.id)

    let isSaved = mirror.editCollections { try CollectionStore.delete(identifier, in: $0) }

    #expect(!isSaved)
    #expect(!context.hasChanges)
    #expect(try CollectionSnapshot.fetch(in: context).collections.map(\.id) == [identifier])
  }

  /// A drop of several documents is one change (#1051): none of them joins.
  @Test func `a drop on a collection whose save fails adds none of it`() throws {
    let mirror = try makeReadOnlyMirror {
      _ = try CollectionStore.create(named: "HTTP", color: .blue, in: $0)
    }
    let context = mirror.container.mainContext
    let identifier = try #require(mirror.collections.collections.first?.id)

    let isSaved = mirror.editCollections {
      try CollectionStore.add([.rfc(9110), .rfc(9111), .rfc(9112)], to: identifier, in: $0)
    }

    #expect(!isSaved)
    #expect(!context.hasChanges)
    #expect(try CollectionSnapshot.fetch(in: context)[identifier]?.members == [])
  }

  @Test func `a highlight whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext
    let model = model

    let isSaved = mirror.editAnnotations { context in
      try AnnotationStore.highlight(
        0..<9, of: .rfc(9110), in: model, color: .yellow,
        edit: AnnotationStore.Edit(context, undoManager: nil, onUndoFailure: { _ in }))
    }

    #expect(!isSaved)
    #expect(!context.hasChanges)
    #expect(try AnnotationSnapshot.fetch(in: context).highlights(of: .rfc(9110)).isEmpty)
  }

  /// Dropped, not left pending, so the next scroll's save starts again from what the
  /// store holds.
  @Test func `a reading place whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext

    #expect(throws: (any Error).self) {
      try mirror.saveReadingPlace(
        ReadingPlace(anchor: "section-2", offset: 4), for: .rfc(.rfc(9110)))
    }

    #expect(!context.hasChanges)
    #expect(try mirror.readingPosition(for: .rfc(.rfc(9110))) == nil)
  }

  /// Nor does it change the place saved before it.
  @Test func `a reading place whose save fails leaves the one stored`() throws {
    let stored = ReadingPlace(anchor: "section-1", offset: 0)
    let mirror = try makeReadOnlyMirror {
      try ReadingPositionStore.save(stored, for: .rfc(.rfc(9110)), in: $0)
    }
    let context = mirror.container.mainContext

    #expect(throws: (any Error).self) {
      try mirror.saveReadingPlace(
        ReadingPlace(anchor: "section-2", offset: 4), for: .rfc(.rfc(9110)))
    }

    #expect(!context.hasChanges)
    #expect(try mirror.readingPosition(for: .rfc(.rfc(9110)))?.place == stored)
  }

  @Test func `an opening whose save fails is not left pending`() throws {
    let mirror = try makeReadOnlyMirror()
    let context = mirror.container.mainContext

    #expect(throws: (any Error).self) { try mirror.recordOpening(.rfc(.rfc(9110))) }

    #expect(!context.hasChanges)
    #expect(try mirror.readingPosition(for: .rfc(.rfc(9110))) == nil)
  }

  // MARK: - Undo, after the change's context is gone

  /// A mirror of an in-memory store that saves.
  private func makeMirror() throws -> UserDataMirror {
    let mirror = UserDataMirror(
      container: try UserData.container(
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    mirror.start()
    return mirror
  }

  /// The context a removal was made in is held by its undo, as the undo manager holds
  /// its target weakly: undoing still puts the bookmark back, and redoing takes it out.
  @Test func `a bookmark's removal is undone and redone`() throws {
    let mirror = try makeMirror()
    let undoManager = UndoManager()
    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics")
    mirror.toggleBookmark(.rfc(9110), title: "HTTP Semantics", undoManager: undoManager)
    #expect(mirror.bookmarkedDocuments.isEmpty)

    undoManager.undo()
    #expect(mirror.bookmarkedDocuments == [.rfc(9110)])
    undoManager.redo()
    #expect(mirror.bookmarkedDocuments.isEmpty)
  }

  @Test func `a removal from a collection is undone and redone`() throws {
    let mirror = try makeMirror()
    let undoManager = UndoManager()
    var identifier: UUID?
    mirror.editCollections { context in
      identifier = try CollectionStore.create(
        named: "HTTP", color: .blue, documents: [.rfc(9110)], in: context
      ).identifier
    }
    let collection = try #require(identifier)
    mirror.editCollections {
      try CollectionStore.remove(
        .rfc(9110), from: collection, undoManager: undoManager,
        onUndoFailure: { Issue.record($0) }, in: $0)
    }
    #expect(mirror.collections[collection]?.members == [])

    undoManager.undo()
    #expect(mirror.collections[collection]?.members == [.rfc(9110)])
    undoManager.redo()
    #expect(mirror.collections[collection]?.members == [])
  }

  /// Undone after another context changed the same highlight: the undo puts back
  /// the color it took away, whatever its context last saw.
  @Test func `a highlight's recoloring is undone after a later one`() throws {
    let mirror = try makeMirror()
    let undoManager = UndoManager()
    let model = model
    func edit(_ context: ModelContext, _ undoManager: UndoManager?) -> AnnotationStore.Edit {
      AnnotationStore.Edit(context, undoManager: undoManager, onUndoFailure: { Issue.record($0) })
    }
    var made: UUID?
    mirror.editAnnotations { context in
      made = try AnnotationStore.highlight(
        0..<9, of: .rfc(9110), in: model, color: .yellow, edit: edit(context, nil))
    }
    let highlight = try #require(made)
    mirror.editAnnotations {
      try AnnotationStore.setColor(.green, of: highlight, edit: edit($0, undoManager))
    }
    mirror.editAnnotations {
      try AnnotationStore.setColor(.blue, of: highlight, edit: edit($0, nil))
    }
    #expect(mirror.annotations.highlights(of: .rfc(9110)).map(\.color) == [.blue])

    undoManager.undo()
    #expect(mirror.annotations.highlights(of: .rfc(9110)).map(\.color) == [.yellow])
  }
}
