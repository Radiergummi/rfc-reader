import Foundation
import RFCKit
import SwiftData

/// The reader's own data: bookmarks and reading positions (#152).
///
/// Versioned from the start, so a change to the schema is a migration rather than a
/// store that no longer opens. `SchemaV3` is the one the app uses: it is CloudKit's
/// shape — no `@Attribute(.unique)`, every attribute optional or defaulted — so
/// turning sync on later is configuration, not another migration. Uniqueness is the
/// stores' job instead (a lookup by the document's `fileStem`, and `deduplicate`),
/// since CloudKit can deliver two rows for one document.
///
/// Here rather than in the App target so the migration can be tested.
public typealias Bookmark = SchemaV3.Bookmark
public typealias ReadingPosition = SchemaV3.ReadingPosition

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

/// V1's rows with V3's columns beside the number they are filled from (#152).
///
/// Only ever a step on the way to V3: it exists so that the number and the key it
/// becomes are in the same row, in the store, while the key is written. Nothing
/// has to be carried outside the store between the stages, so a migration
/// interrupted at any point picks up where it stopped on the next launch.
public enum SchemaV2: VersionedSchema {
  public static let versionIdentifier = Schema.Version(2, 0, 0)
  public static var models: [any PersistentModel.Type] { [Bookmark.self, ReadingPosition.self] }

  @Model
  public final class Bookmark {
    public var number: Int
    public var documentKey: String = ""
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
    public var number: Int
    public var documentKey: String = ""
    public var sectionAnchor: String?
    public var offset: Int?
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
public enum SchemaV3: VersionedSchema {
  public static let versionIdentifier = Schema.Version(3, 0, 0)
  public static var models: [any PersistentModel.Type] { [Bookmark.self, ReadingPosition.self] }

  @Model
  public final class Bookmark {
    /// The document's `fileStem`: `rfc9110`, `bcp14`.
    public var documentKey: String = ""
    public var title: String = ""
    public var createdAt: Date = Date.distantPast

    public init(document: DocumentID, title: String, createdAt: Date = .now) {
      self.documentKey = document.fileStem
      self.title = title
      self.createdAt = createdAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
  }

  @Model
  public final class ReadingPosition {
    public var documentKey: String = ""
    /// The nearest anchor at or above the place the reader left, as a
    /// `ReadingPlace` has it. V1 and V2 called it the section anchor.
    @Attribute(originalName: "sectionAnchor") public var anchor: String?
    /// Characters past `anchor`, or nil when no place is recorded. Zero for a place
    /// that is the anchor itself, which is every place recorded before #152.
    public var offset: Int?
    public var updatedAt: Date = Date.distantPast

    public init(document: DocumentID, place: ReadingPlace?, updatedAt: Date = .now) {
      self.documentKey = document.fileStem
      self.anchor = place?.anchor
      self.offset = place?.offset
      self.updatedAt = updatedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }

    public var place: ReadingPlace? {
      get { offset.map { ReadingPlace(anchor: anchor, offset: $0) } }
      set {
        anchor = newValue?.anchor
        offset = newValue?.offset
      }
    }
  }
}

/// V1 to V3 by way of V2 (#152). Every row survives, as `rfcN`, and a section
/// anchor becomes a place at offset zero.
///
/// `rfcN` is an assumption the V1 row cannot confirm: it kept only the number, so a
/// BCP or STD opened through a deep link and bookmarked is indistinguishable from
/// the RFC with that number. RFCs are what the library lists and nearly all anyone
/// opens, so they are the reading of a bare number that is almost always right.
///
/// SwiftData's inferred migration can add defaulted attributes, rename one and drop
/// a unique constraint, but not turn a number into a key. So V1 to V2 is inferred
/// and keeps the number beside the new columns; V2 to V3 writes each row's key from
/// its own number, then drops the number. A row whose key is already written is
/// left alone, so running the second stage again changes nothing.
public enum UserDataMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self]
  }
  public static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

  static let v1ToV2 = MigrationStage.lightweight(
    fromVersion: SchemaV1.self, toVersion: SchemaV2.self)

  static let v2ToV3 = MigrationStage.custom(
    fromVersion: SchemaV2.self, toVersion: SchemaV3.self,
    willMigrate: { context in
      let bookmarks = try context.fetch(
        FetchDescriptor<SchemaV2.Bookmark>(predicate: #Predicate { $0.documentKey == "" }))
      for bookmark in bookmarks {
        bookmark.documentKey = DocumentID.rfc(bookmark.number).fileStem
      }
      let positions = try context.fetch(
        FetchDescriptor<SchemaV2.ReadingPosition>(predicate: #Predicate { $0.documentKey == "" }))
      for position in positions {
        position.documentKey = DocumentID.rfc(position.number).fileStem
        position.offset = position.sectionAnchor == nil ? nil : 0
      }
      try context.save()
    },
    didMigrate: nil)
}

/// Opening the store, and keeping it one row per document.
public enum UserData {
  /// The app's container: V3, migrated from whatever version is on disk.
  public static func container(configurations: ModelConfiguration...) throws -> ModelContainer {
    try ModelContainer(
      for: Schema(versionedSchema: SchemaV3.self), migrationPlan: UserDataMigrationPlan.self,
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
