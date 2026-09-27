import Foundation
import RFCKit
import SwiftData
import Synchronization

/// The reader's own data: bookmarks and reading positions (#152).
///
/// Versioned from the start, so a change to the schema is a migration rather than a
/// store that no longer opens. `SchemaV2` is the one the app uses: it is CloudKit's
/// shape — no `@Attribute(.unique)`, every attribute optional or defaulted — so
/// turning sync on later is configuration, not another migration. Uniqueness is the
/// stores' job instead (`UserDataKey`, `deduplicate`), since CloudKit can deliver two
/// rows for one document.
///
/// Here rather than in the App target so the migration can be tested.
public typealias Bookmark = SchemaV2.Bookmark
public typealias ReadingPosition = SchemaV2.ReadingPosition

/// Today's models as they were before #152, exactly: a bare RFC number, unique.
public enum SchemaV1: VersionedSchema {
  public static let versionIdentifier = Schema.Version(1, 0, 0)
  public static var models: [any PersistentModel.Type] { [Bookmark.self, ReadingPosition.self] }

  @Model
  public final class Bookmark {
    @Attribute(.unique) public var number: Int
    public var title: String
    public var createdAt: Date

    public init(number: Int, title: String, createdAt: Date = .now) {
      self.number = number
      self.title = title
      self.createdAt = createdAt
    }
  }

  @Model
  public final class ReadingPosition {
    @Attribute(.unique) public var number: Int
    public var sectionAnchor: String?
    public var updatedAt: Date

    public init(number: Int, sectionAnchor: String?, updatedAt: Date = .now) {
      self.number = number
      self.sectionAnchor = sectionAnchor
      self.updatedAt = updatedAt
    }
  }
}

/// Keyed on the document, not its number — RFC 1, BCP 1 and STD 1 share a number —
/// and in CloudKit's shape.
public enum SchemaV2: VersionedSchema {
  public static let versionIdentifier = Schema.Version(2, 0, 0)
  public static var models: [any PersistentModel.Type] { [Bookmark.self, ReadingPosition.self] }

  @Model
  public final class Bookmark {
    /// `UserDataKey.key(for:)`: `rfc9110`, `bcp14`.
    public var documentKey: String = ""
    public var title: String = ""
    public var createdAt: Date = Date.distantPast

    public init(document: DocumentID, title: String, createdAt: Date = .now) {
      self.documentKey = UserDataKey.key(for: document)
      self.title = title
      self.createdAt = createdAt
    }

    public var document: DocumentID? { UserDataKey.document(for: documentKey) }
  }

  @Model
  public final class ReadingPosition {
    public var documentKey: String = ""
    /// The nearest anchor at or above the place the reader left, as a
    /// `ReadingPlace` has it.
    public var anchor: String?
    /// Characters past `anchor`. Zero for a place that is the anchor itself, which
    /// is every place recorded before #152.
    public var offset: Int = 0
    public var updatedAt: Date = Date.distantPast

    public init(document: DocumentID, place: ReadingPlace?, updatedAt: Date = .now) {
      self.documentKey = UserDataKey.key(for: document)
      self.anchor = place?.anchor
      self.offset = place?.offset ?? 0
      self.updatedAt = updatedAt
    }

    public var document: DocumentID? { UserDataKey.document(for: documentKey) }

    public var place: ReadingPlace? {
      get { anchor == nil && offset == 0 ? nil : ReadingPlace(anchor: anchor, offset: offset) }
      set {
        anchor = newValue?.anchor
        offset = newValue?.offset ?? 0
      }
    }
  }
}

/// How a document is named in the store: its file stem, which is what the RFC
/// Editor calls it too, and which tells RFC 1 from BCP 1.
public enum UserDataKey {
  public static func key(for document: DocumentID) -> String {
    document.fileStem
  }

  public static func document(for key: String) -> DocumentID? {
    guard let document = DocumentID(parsing: key), document.fileStem == key else { return nil }
    return document
  }
}

/// V1 to V2 (#152). Every row survives, as `rfcN`, and a section anchor becomes a
/// place at offset zero.
///
/// `rfcN` is an assumption the V1 row cannot confirm: it kept only the number, so a
/// BCP or STD opened through a deep link and bookmarked is indistinguishable from
/// the RFC with that number. RFCs are what the library lists and nearly all anyone
/// opens, so they are the reading of a bare number that is almost always right.
///
/// A custom stage: SwiftData's inferred migration can add V2's defaulted attributes
/// and drop the unique constraint, but not turn a number into a key. So the V1 rows
/// are read before the stage and written back as V2 rows after it.
public enum UserDataMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
  public static var stages: [MigrationStage] { [v1ToV2] }

  private struct V1Rows: Sendable {
    var bookmarks: [CarriedBookmark] = []
    var positions: [CarriedPosition] = []
  }

  /// Carried from `willMigrate` to `didMigrate`, the one way a custom stage's two
  /// halves can hand anything over.
  private static let carried = Mutex(V1Rows())

  static let v1ToV2 = MigrationStage.custom(
    fromVersion: SchemaV1.self, toVersion: SchemaV2.self,
    willMigrate: { context in
      let bookmarks = try context.fetch(FetchDescriptor<SchemaV1.Bookmark>())
      let positions = try context.fetch(FetchDescriptor<SchemaV1.ReadingPosition>())
      let rows = V1Rows(
        bookmarks: bookmarks.map {
          CarriedBookmark(number: $0.number, title: $0.title, createdAt: $0.createdAt)
        },
        positions: positions.map {
          CarriedPosition(number: $0.number, anchor: $0.sectionAnchor, updatedAt: $0.updatedAt)
        })
      carried.withLock { $0 = rows }
    },
    didMigrate: { context in
      let rows = carried.withLock { rows in
        defer { rows = V1Rows() }
        return rows
      }
      // The inferred step left one row per V1 row with the defaulted key; they are
      // replaced by the rows carried over.
      try context.delete(model: SchemaV2.Bookmark.self)
      try context.delete(model: SchemaV2.ReadingPosition.self)
      for row in rows.bookmarks {
        context.insert(
          SchemaV2.Bookmark(document: .rfc(row.number), title: row.title, createdAt: row.createdAt))
      }
      for row in rows.positions {
        context.insert(
          SchemaV2.ReadingPosition(
            document: .rfc(row.number),
            place: row.anchor.map { ReadingPlace(anchor: $0, offset: 0) },
            updatedAt: row.updatedAt))
      }
      try context.save()
    })
}

/// A V1 bookmark, as `UserDataMigrationPlan` carries it across the stage.
private struct CarriedBookmark: Sendable {
  let number: Int
  let title: String
  let createdAt: Date
}

/// A V1 reading position, likewise.
private struct CarriedPosition: Sendable {
  let number: Int
  let anchor: String?
  let updatedAt: Date
}

/// Opening the store, and keeping it one row per document.
public enum UserData {
  /// The app's container: V2, migrated from whatever version is on disk.
  public static func container(configurations: ModelConfiguration...) throws -> ModelContainer {
    try ModelContainer(
      for: Schema(versionedSchema: SchemaV2.self), migrationPlan: UserDataMigrationPlan.self,
      configurations: configurations)
  }

  /// Merges rows that name the same document, keeping the newest. Without a unique
  /// constraint — CloudKit refuses one — two devices, or a race, can leave two.
  @MainActor
  public static func deduplicate(_ context: ModelContext) throws {
    let bookmarks = try context.fetch(
      FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    removeDuplicates(bookmarks, keyedBy: \.documentKey, in: context)
    let positions = try context.fetch(
      FetchDescriptor<ReadingPosition>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    removeDuplicates(positions, keyedBy: \.documentKey, in: context)
    if context.hasChanges { try context.save() }
  }

  /// Newest first in, so the first row per key is the one kept.
  private static func removeDuplicates<Row: PersistentModel>(
    _ rows: [Row], keyedBy key: (Row) -> String, in context: ModelContext
  ) {
    var seen: Set<String> = []
    for row in rows where !seen.insert(key(row)).inserted {
      context.delete(row)
    }
  }
}
