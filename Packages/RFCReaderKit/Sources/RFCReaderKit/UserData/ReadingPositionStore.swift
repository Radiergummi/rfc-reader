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
  /// The row of an RFC or a draft's revision (#728), keyed as `userDataKey` says. By
  /// key, the store having no unique constraint (#152); `UserData.deduplicate` leaves
  /// one per document.
  public static func position(for document: ReadableDocument, in context: ModelContext) throws
    -> ReadingPosition?
  {
    let key = document.userDataKey
    let descriptor = FetchDescriptor<ReadingPosition>(
      predicate: #Predicate { $0.documentKey == key })
    return try context.fetch(descriptor).first
  }

  /// Dates the row as the document is opened, leaving its place alone: the place
  /// is restored a moment later, and writing it here would undo that.
  public static func markOpened(
    _ document: ReadableDocument, at date: Date = .now, in context: ModelContext
  ) throws {
    if let existing = try position(for: document, in: context) {
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(key: document.userDataKey, place: nil, updatedAt: date))
    }
    try context.save()
  }

  /// The place the reader left, dated as it is left.
  public static func save(
    _ place: ReadingPlace?, for document: ReadableDocument, at date: Date = .now,
    in context: ModelContext
  ) throws {
    if let existing = try position(for: document, in: context) {
      existing.place = place
      existing.updatedAt = date
    } else {
      context.insert(ReadingPosition(key: document.userDataKey, place: place, updatedAt: date))
    }
    try context.save()
  }

  /// Every document with a position, most recently opened or left first.
  public static func recentlyRead(in context: ModelContext) throws -> [DocumentID] {
    let descriptor = FetchDescriptor<ReadingPosition>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    return try context.fetch(descriptor).compactMap(\.document)
  }

  /// How many documents `recentlyRead` lists, a BCP, STD or FYI among them (#321):
  /// the Recently Read count, which the library refreshes on every save of a reading
  /// position, so only the keys are fetched, unsorted.
  public static func recentlyReadCount(in context: ModelContext) throws -> Int {
    var descriptor = FetchDescriptor<ReadingPosition>()
    descriptor.propertiesToFetch = [\.documentKey]
    return try context.fetch(descriptor).count { $0.document != nil }
  }

  /// The documents opened or left after `date`.
  public static func read(since date: Date, in context: ModelContext) throws -> Set<DocumentID> {
    let descriptor = FetchDescriptor<ReadingPosition>(
      predicate: #Predicate { $0.updatedAt > date })
    return Set(try context.fetch(descriptor).compactMap(\.document))
  }
}

extension ReadableDocument {
  /// What the user's data keys the document by: an RFC's `fileStem`, `rfc9110`, or
  /// a draft's name with its revision, `draft-ietf-httpbis-semantics-19`, which no
  /// `DocumentID` reads as its own, so a draft is never listed as an RFC read.
  public var userDataKey: String {
    switch self {
    case .rfc(let id): id.fileStem
    case .draft(let id): id.description
    }
  }
}
