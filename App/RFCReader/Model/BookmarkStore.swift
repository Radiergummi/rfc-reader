import Foundation
import RFCKit
import RFCReaderKit
import SwiftData
import os

private let bookmarkLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "bookmarks")

/// The one place a `Bookmark` is read or written.
///
/// Both toolbars offer "bookmark this RFC" and each used to implement it: macOS
/// fetched with a `#Predicate` and saved explicitly, iOS filtered a `@Query` and left
/// it to autosave. Nothing was broken, but the next change to what bookmarking means
/// had to be made twice — and the two had already drifted over the title a new
/// bookmark stores, which is now `DocumentActions.bookmarkTitle`.
///
/// What each caller still owns is how it *displays* the state: iOS reads its `@Query`
/// for the filled glyph, macOS holds the last answer in
/// `ReaderWindowController.isBookmarked` because `NSToolbar` revalidates far too
/// often to ask a store here.
enum BookmarkStore {
  /// Every bookmarked document. Only the keys are fetched: this runs on every save
  /// of the store, and most of those record a reading position.
  ///
  /// Throws rather than answering with an empty set, which would read as "nothing is
  /// bookmarked": eviction would take that as leave to delete the bookmarked
  /// documents' offline copies.
  static func bookmarkedDocuments(in context: ModelContext) throws -> Set<DocumentID> {
    var descriptor = FetchDescriptor<Bookmark>()
    descriptor.propertiesToFetch = [\.documentKey]
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }

  /// Adds the bookmark, or removes the one already there.
  ///
  /// When the lookup fails, it changes nothing: not knowing whether the document is
  /// bookmarked, inserting would add a second bookmark beside the one there.
  static func toggle(_ id: DocumentID, title: String, in context: ModelContext) {
    let existing: [Bookmark]
    do {
      existing = try bookmarks(for: id, in: context)
    } catch {
      bookmarkLog.error(
        "looking up a bookmark failed: \(String(describing: error), privacy: .public)")
      return
    }
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
    do {
      try context.save()
    } catch {
      // Logged rather than discarded (#125): the change is still in the context,
      // and autosave may yet write it, but a bookmark that is never saved should
      // leave a trace.
      bookmarkLog.error("saving a bookmark failed: \(String(describing: error), privacy: .public)")
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
