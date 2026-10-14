import Foundation
import RFCKit
import SwiftData

/// The one place an `OfflineMark` is read or written (#358), on `BookmarkStore`'s
/// terms: every failure is thrown, and the App decides what to do with it.
///
/// Nobody displays the state by asking here: `LibraryModel` reads
/// `markedDocuments(in:)` after every save of a mark, as it reads the bookmarks.
@MainActor
public enum OfflineMarkStore {
  /// Every document marked to keep offline. Only the keys are fetched.
  ///
  /// Throws rather than answering with an empty set, which would read as "nothing is
  /// kept": the reconciler would take that as leave to move every kept body back
  /// into the cache.
  public static func markedDocuments(in context: ModelContext) throws -> Set<DocumentID> {
    var descriptor = FetchDescriptor<OfflineMark>()
    descriptor.propertiesToFetch = [\.documentKey]
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }

  /// Marks `id` to keep offline, or removes its marks, and saves. Marking a document
  /// already marked adds nothing: a failed lookup throws before anything changes, as
  /// a bookmark's does.
  public static func setMarked(_ id: DocumentID, _ isMarked: Bool, in context: ModelContext)
    throws
  {
    let key = id.fileStem
    let existing = try context.fetch(
      FetchDescriptor<OfflineMark>(predicate: #Predicate { $0.documentKey == key }))
    if isMarked {
      guard existing.isEmpty else { return }
      context.insert(OfflineMark(document: id))
    } else {
      guard !existing.isEmpty else { return }
      // Every row naming the document, since nothing stops there being two.
      existing.forEach(context.delete)
    }
    try context.save()
  }

  /// Removes every mark, as Settings' Remove All Offline Documents does (#358), and
  /// saves. The bodies are the reconciler's to move back into the cache.
  /// Row by row rather than a batch delete, which skips the context's change tracking
  /// that the save's notification, and so every other tab, reads.
  public static func removeAll(in context: ModelContext) throws {
    try context.fetch(FetchDescriptor<OfflineMark>()).forEach(context.delete)
    try context.save()
  }
}
