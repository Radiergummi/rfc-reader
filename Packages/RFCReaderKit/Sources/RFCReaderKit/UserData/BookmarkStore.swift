import Foundation
import RFCKit
import SwiftData

/// The one place a `Bookmark` is read or written.
///
/// Both toolbars offer "bookmark this RFC" and each used to implement it: macOS
/// fetched with a `#Predicate` and saved explicitly, iOS filtered a `@Query` and left
/// it to autosave. Nothing was broken, but the next change to what bookmarking means
/// had to be made twice — and the two had already drifted over the title a new
/// bookmark stores, which is now `DocumentActions.bookmarkTitle`.
///
/// Nobody displays the state by asking here: `UserDataMirror` reads
/// `bookmarkedDocuments(in:)` after every save of a bookmark, and the toolbars, the
/// menu and the list rows read its set, which is cheap enough for `NSToolbar` to
/// revalidate against on every event.
///
/// In the package beside `CollectionStore`, and on its terms: every failure is
/// thrown, and the App decides what to do with it.
@MainActor
public enum BookmarkStore {
  /// Every bookmarked document. Only the keys are fetched: this runs on every save
  /// of a bookmark (`UserDataMirrors`, #603).
  ///
  /// Throws rather than answering with an empty set, which would read as "nothing is
  /// bookmarked": eviction would take that as leave to delete the bookmarked
  /// documents' offline copies.
  public static func bookmarkedDocuments(in context: ModelContext) throws -> Set<DocumentID> {
    var descriptor = FetchDescriptor<Bookmark>()
    descriptor.propertiesToFetch = [\.documentKey]
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }

  /// Adds the bookmark, or removes the one already there.
  ///
  /// A failed lookup throws before anything changes: not knowing whether the
  /// document is bookmarked, inserting would add a second bookmark beside the one
  /// there.
  ///
  /// A removal can be undone, the bookmark back with its title and the date it was
  /// added (#769): a stray swipe or ⌘D lost both. Its undo and redo run long after
  /// this returns, so they hand what they throw to `onUndoFailure`, as
  /// `CollectionStore.remove`'s do.
  public static func toggle(
    _ id: DocumentID, title: String, undoManager: UndoManager? = nil,
    onUndoFailure: @escaping @MainActor (any Error) -> Void = { _ in }, in context: ModelContext
  ) throws {
    let existing = try bookmarks(for: id, in: context)
    let undo = Undo(
      manager: undoManager,
      name: DocumentActions.bookmarkCommand(isBookmarked: !existing.isEmpty),
      onFailure: onUndoFailure)
    if let first = existing.first {
      try remove(
        existing, putBack: Entry(document: id, title: first.title, createdAt: first.createdAt),
        undo: undo, in: context)
    } else {
      try put(Entry(document: id, title: title, createdAt: .now), undo: undo, in: context)
    }
  }

  /// A bookmark as a removal took it out, or an add puts it in.
  private struct Entry {
    let document: DocumentID
    let title: String
    let createdAt: Date
  }

  /// Where a toggle registers its undo, and under the name of what the reader did,
  /// which its undo and redo keep whichever way they go.
  @MainActor private struct Undo {
    let manager: UndoManager?
    let name: String
    let onFailure: @MainActor (any Error) -> Void

    /// Registers `action` as the undo. Its undo and redo run long after the toggle
    /// returns, so they hand what they throw to `onFailure`, as
    /// `CollectionStore.remove`'s do. The manager is held weakly: it holds this.
    func register(
      in context: ModelContext, _ action: @escaping @MainActor (ModelContext, Undo) throws -> Void
    ) {
      guard let manager else { return }
      let name = name
      let onFailure = onFailure
      manager.registerUndo(withTarget: context) { [weak manager] context in
        // On the main thread, for the reason `CollectionStore.remove` gives.
        MainActor.assumeIsolated {
          do {
            try action(context, Undo(manager: manager, name: name, onFailure: onFailure))
          } catch {
            onFailure(error)
          }
        }
      }
      manager.setActionName(name)
    }
  }

  /// Puts `entry` in, and registers taking it out as the undo. Nothing is put in
  /// beside a bookmark made since: an undone removal adds no second.
  private static func put(_ entry: Entry, undo: Undo, in context: ModelContext) throws {
    guard try bookmarks(for: entry.document, in: context).isEmpty else { return }
    context.insert(
      Bookmark(document: entry.document, title: entry.title, createdAt: entry.createdAt))
    try context.saveOrRollBack()
    undo.register(in: context) { context, undo in
      try remove(
        bookmarks(for: entry.document, in: context), putBack: entry, undo: undo, in: context)
    }
  }

  /// Removes `existing`, every row naming the document, since nothing stops there
  /// being two, and registers putting `entry` back as the undo.
  private static func remove(
    _ existing: [Bookmark], putBack entry: Entry, undo: Undo, in context: ModelContext
  ) throws {
    guard !existing.isEmpty else { return }
    existing.forEach(context.delete)
    // Explicitly, rather than leaving it to autosave on one platform and not the
    // other: on macOS the sidebar's list and the reader's toolbar are separate
    // hosting roots reading the same store, and the glyph should not be able to
    // disagree with the list behind it while a save is still pending.
    try context.saveOrRollBack()
    // Registered once saved: a failed save discards the removal, leaving nothing to undo.
    undo.register(in: context) { context, undo in
      try put(entry, undo: undo, in: context)
    }
  }

  /// Looked up by key before every insert: the store has no unique constraint to do
  /// it (#152).
  private static func bookmarks(for id: DocumentID, in context: ModelContext) throws -> [Bookmark] {
    let key = id.fileStem
    let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.documentKey == key })
    return try context.fetch(descriptor)
  }
}
