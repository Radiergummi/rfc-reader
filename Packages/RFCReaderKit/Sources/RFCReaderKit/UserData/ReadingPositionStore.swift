import Foundation
import RFCKit
import SwiftData

/// The one place a `ReadingPosition` is read or written.
///
/// The reader, eviction and the Recently read list each used to write their own
/// `FetchDescriptor`, with `try?` turning a failed fetch into "never read". On
/// `CollectionStore`'s terms instead: every failure is thrown, the App decides what
/// to do with it, and every change saves before it returns.
@MainActor
public enum ReadingPositionStore {
  /// The document's row. By key, the store having no unique constraint (#152);
  /// `UserData.deduplicate` leaves one per document.
  public static func position(for id: DocumentID, in context: ModelContext) throws
    -> ReadingPosition?
  {
    let key = id.fileStem
    let descriptor = FetchDescriptor<ReadingPosition>(
      predicate: #Predicate { $0.documentKey == key })
    return try context.fetch(descriptor).first
  }

  /// Dates the row as the document is opened, leaving its place alone: the place
  /// is restored a moment later, and writing it here would undo that.
  public static func markOpened(
    _ id: DocumentID, at date: Date = .now, in context: ModelContext
  ) throws {
    if let existing = try position(for: id, in: context) {
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(document: id, place: nil, updatedAt: date))
    }
    try context.save()
  }

  /// The place the reader left, dated as it is left.
  public static func save(
    _ place: ReadingPlace?, for id: DocumentID, at date: Date = .now, in context: ModelContext
  ) throws {
    if let existing = try position(for: id, in: context) {
      existing.place = place
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(document: id, place: place, updatedAt: date))
    }
    try context.save()
  }

  /// Every document with a position, most recently opened or left first.
  public static func recentlyRead(in context: ModelContext) throws -> [DocumentID] {
    let descriptor = FetchDescriptor<ReadingPosition>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    return try context.fetch(descriptor).compactMap(\.document)
  }

  /// How many of the documents `recentlyRead` lists are RFCs: the Recently Read
  /// count, which the library refreshes on every save of a reading position, so only
  /// the keys are fetched, unsorted.
  public static func recentlyReadRFCCount(in context: ModelContext) throws -> Int {
    var descriptor = FetchDescriptor<ReadingPosition>()
    descriptor.propertiesToFetch = [\.documentKey]
    return try context.fetch(descriptor).count { $0.document?.series == .rfc }
  }

  /// The documents opened or left after `date`.
  public static func read(since date: Date, in context: ModelContext) throws -> Set<DocumentID> {
    let descriptor = FetchDescriptor<ReadingPosition>(
      predicate: #Predicate { $0.updatedAt > date })
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }
}
