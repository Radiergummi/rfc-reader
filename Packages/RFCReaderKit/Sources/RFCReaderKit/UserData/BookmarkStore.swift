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
/// Nobody displays the state by asking here: `LibraryModel` reads
/// `bookmarkedDocuments(in:)` after every save, and the toolbars, the menu and the
/// list rows read its set, which is cheap enough for `NSToolbar` to revalidate
/// against on every event.
///
/// In the package beside `CollectionStore`, and on its terms: every failure is
/// thrown, and the App decides what to do with it.
@MainActor
public enum BookmarkStore {
  /// Every bookmarked document. Only the keys are fetched: this runs on every save
  /// of the store, and most of those record a reading position.
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
  public static func toggle(_ id: DocumentID, title: String, in context: ModelContext) throws {
    let existing = try bookmarks(for: id, in: context)
    if !existing.isEmpty {
      // Every row naming the document, since nothing stops there being two.
      existing.forEach(context.delete)
    } else {
      context.insert(Bookmark(document: id, title: title))
    }
    // Explicitly, rather than leaving it to autosave on one platform and not the
    // other: on macOS the sidebar's list and the reader's toolbar are separate
    // hosting roots reading the same store, and the glyph should not be able to
    // disagree with the list behind it while a save is still pending.
    try context.save()
  }

  /// Looked up by key before every insert: the store has no unique constraint to do
  /// it (#152).
  private static func bookmarks(for id: DocumentID, in context: ModelContext) throws -> [Bookmark] {
    let key = id.fileStem
    let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.documentKey == key })
    return try context.fetch(descriptor)
  }
}
