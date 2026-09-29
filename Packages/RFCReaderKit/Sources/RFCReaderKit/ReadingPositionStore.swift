import Foundation
import RFCKit
import SwiftData

/// The one place a `ReadingPosition` is read or written (#135), as `BookmarkStore`
/// is for bookmarks.
///
/// The store has no unique constraint on the document (#152), so each write looks
/// its row up first and updates it rather than inserting a second.
@MainActor
public enum ReadingPositionStore {
  public static func stored(for id: DocumentID, in context: ModelContext) -> ReadingPosition? {
    let key = id.fileStem
    let descriptor = FetchDescriptor<ReadingPosition>(
      predicate: #Predicate { $0.documentKey == key })
    return try? context.fetch(descriptor).first
  }

  /// Dates the entry as the document is opened, not only as it is left.
  ///
  /// `save` runs as the reader leaves, which is the one moment the place is known —
  /// but on its own it left the document on screen carrying the date it was last
  /// *closed*, and Recently Read listed what is being read now below things
  /// finished with earlier. Only the date is written: the place is restored from
  /// this entry a moment later, and writing it here would undo that.
  public static func markAsRead(
    _ id: DocumentID, at date: Date = .now, in context: ModelContext
  ) {
    if let existing = stored(for: id, in: context) {
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(document: id, place: nil, updatedAt: date))
    }
  }

  /// Records where the reader left the document.
  public static func save(
    _ place: ReadingPlace?, for id: DocumentID, at date: Date = .now, in context: ModelContext
  ) {
    if let existing = stored(for: id, in: context) {
      existing.place = place
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(document: id, place: place, updatedAt: date))
    }
  }
}
