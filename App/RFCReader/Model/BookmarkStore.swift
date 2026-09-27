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
/// What each caller still owns is how it *displays* the state: iOS reads its `@Query`
/// for the filled glyph, macOS holds the last answer in
/// `ReaderWindowController.isBookmarked` because `NSToolbar` revalidates far too
/// often to ask a store here.
enum BookmarkStore {
  /// Every bookmarked RFC's number. Only the numbers are fetched: this runs on
  /// every save of the store, and most of those record a reading position.
  static func bookmarkedNumbers(in context: ModelContext) -> Set<Int> {
    var descriptor = FetchDescriptor<Bookmark>()
    descriptor.propertiesToFetch = [\.number]
    return Set(((try? context.fetch(descriptor)) ?? []).map(\.number))
  }

  /// Adds the bookmark, or removes the one already there. Answers with the state it
  /// leaves behind, so a caller that displays it need not go back and ask.
  @discardableResult
  static func toggle(_ id: DocumentID, title: String, in context: ModelContext) -> Bool {
    let bookmarked: Bool
    if let existing = bookmark(for: id, in: context) {
      context.delete(existing)
      bookmarked = false
    } else {
      context.insert(Bookmark(number: id.number, title: title))
      bookmarked = true
    }
    // Explicitly, rather than leaving it to autosave on one platform and not the
    // other: on macOS the sidebar's list and the reader's toolbar are separate
    // hosting roots reading the same store, and the glyph should not be able to
    // disagree with the list behind it while a save is still pending.
    try? context.save()
    return bookmarked
  }

  private static func bookmark(for id: DocumentID, in context: ModelContext) -> Bookmark? {
    let number = id.number
    let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.number == number })
    return try? context.fetch(descriptor).first
  }
}
