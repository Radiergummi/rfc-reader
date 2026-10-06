import Foundation
import RFCKit
import SwiftData

/// The reader's own data: bookmarks, reading positions (#152) and collections (#349).
///
/// Versioned from the start, so a change to the schema is a migration rather than a
/// store that no longer opens. `SchemaV5` is the one the app uses, V3's keys and
/// shape carried over unchanged: it is CloudKit's shape — no `@Attribute(.unique)`, every attribute optional or defaulted — so
/// turning sync on later is configuration, not another migration. Uniqueness is the
/// stores' job instead (a lookup by the document's `fileStem`, and `deduplicate`),
/// since CloudKit can deliver two rows for one document.
///
/// Here rather than in the App target so the migration can be tested.
public typealias Bookmark = SchemaV5.Bookmark
public typealias ReadingPosition = SchemaV5.ReadingPosition
public typealias DocumentCollection = SchemaV5.DocumentCollection
public typealias DocumentCollectionItem = SchemaV5.DocumentCollectionItem
public typealias OfflineMark = SchemaV5.OfflineMark

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

/// V3 and the collections (#349). Its own copies of V3's two models, identical to
/// them: reusing one schema's classes in another is a known source of failed
/// staged migrations in SwiftData.
public enum SchemaV4: VersionedSchema {
  public static let versionIdentifier = Schema.Version(4, 0, 0)
  public static var models: [any PersistentModel.Type] {
    [Bookmark.self, ReadingPosition.self, DocumentCollection.self, DocumentCollectionItem.self]
  }

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

  /// V3's, `originalName` included: without it the migration drops every reading
  /// position's anchor — measured, on V1, V2 and V3 stores alike.
  @Model
  public final class ReadingPosition {
    public var documentKey: String = ""
    /// The nearest anchor at or above the place the reader left, as a
    /// `ReadingPlace` has it. V1 and V2 called it the section anchor.
    @Attribute(originalName: "sectionAnchor") public var anchor: String?
    /// Characters past `anchor`, or nil when no place is recorded.
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

  /// A named, user-made list of documents. Its members are `DocumentCollectionItem`
  /// rows naming it by `identifier`, not a relationship: two devices adding to one
  /// collection then each insert a row, and nothing is lost when they meet.
  @Model
  public final class DocumentCollection {
    public var identifier: UUID = UUID()
    public var name: String = ""
    /// A `CollectionColor` raw value. An unknown name reads as the default.
    public var colorName: String = CollectionColor.default.rawValue
    /// Where the collection sits in the sidebar, ascending.
    public var position: Double = 0
    public var createdAt: Date = Date.distantPast

    public init(name: String, color: CollectionColor, position: Double, createdAt: Date = .now) {
      self.identifier = UUID()
      self.name = name
      self.colorName = color.rawValue
      self.position = position
      self.createdAt = createdAt
    }

    public var color: CollectionColor {
      get { CollectionColor(name: colorName) }
      set { colorName = newValue.rawValue }
    }
  }

  /// One document in one collection.
  @Model
  public final class DocumentCollectionItem {
    public var collectionIdentifier: UUID?
    /// The document's `fileStem`, as `Bookmark.documentKey` is: `rfc9110`.
    public var documentKey: String = ""
    /// Where the item sits in its collection, ascending.
    public var position: Double = 0
    public var addedAt: Date = Date.distantPast

    public init(collection: UUID, document: DocumentID, position: Double, addedAt: Date = .now) {
      self.collectionIdentifier = collection
      self.documentKey = document.fileStem
      self.position = position
      self.addedAt = addedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
  }
}

/// V4 and the Keep Offline marks (#358). Its own copies of V4's models, identical
/// to them, for the reason V4 has its own of V3's.
public enum SchemaV5: VersionedSchema {
  public static let versionIdentifier = Schema.Version(5, 0, 0)
  public static var models: [any PersistentModel.Type] {
    [
      Bookmark.self, ReadingPosition.self, DocumentCollection.self, DocumentCollectionItem.self,
      OfflineMark.self,
    ]
  }

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

  /// V4's, `originalName` included, which V4's needs: see there.
  @Model
  public final class ReadingPosition {
    public var documentKey: String = ""
    /// The nearest anchor at or above the place the reader left, as a
    /// `ReadingPlace` has it. V1 and V2 called it the section anchor.
    @Attribute(originalName: "sectionAnchor") public var anchor: String?
    /// Characters past `anchor`, or nil when no place is recorded.
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

  /// A named, user-made list of documents. Its members are `DocumentCollectionItem`
  /// rows naming it by `identifier`, not a relationship: two devices adding to one
  /// collection then each insert a row, and nothing is lost when they meet.
  @Model
  public final class DocumentCollection {
    public var identifier: UUID = UUID()
    public var name: String = ""
    /// A `CollectionColor` raw value. An unknown name reads as the default.
    public var colorName: String = CollectionColor.default.rawValue
    /// Where the collection sits in the sidebar, ascending.
    public var position: Double = 0
    public var createdAt: Date = Date.distantPast

    public init(name: String, color: CollectionColor, position: Double, createdAt: Date = .now) {
      self.identifier = UUID()
      self.name = name
      self.colorName = color.rawValue
      self.position = position
      self.createdAt = createdAt
    }

    public var color: CollectionColor {
      get { CollectionColor(name: colorName) }
      set { colorName = newValue.rawValue }
    }
  }

  /// One document in one collection.
  @Model
  public final class DocumentCollectionItem {
    public var collectionIdentifier: UUID?
    /// The document's `fileStem`, as `Bookmark.documentKey` is: `rfc9110`.
    public var documentKey: String = ""
    /// Where the item sits in its collection, ascending.
    public var position: Double = 0
    public var addedAt: Date = Date.distantPast

    public init(collection: UUID, document: DocumentID, position: Double, addedAt: Date = .now) {
      self.collectionIdentifier = collection
      self.documentKey = document.fileStem
      self.position = position
      self.addedAt = addedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
  }

  /// A document the reader wants kept on this device, and every other, for reading
  /// offline: a promise, where a bookmark is only "find this again". Keyed on the
  /// document's `fileStem`, as a bookmark is, and synced like one, so marking a
  /// document on the Mac makes the iPhone fetch it.
  @Model
  public final class OfflineMark {
    /// The document's `fileStem`: `rfc9110`.
    public var documentKey: String = ""
    public var markedAt: Date = Date.distantPast

    public init(document: DocumentID, markedAt: Date = .now) {
      self.documentKey = document.fileStem
      self.markedAt = markedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
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
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
  }
  public static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5] }

  static let v1ToV2 = MigrationStage.lightweight(
    fromVersion: SchemaV1.self, toVersion: SchemaV2.self)

  /// Adds the collections' two entities and changes nothing else (#349).
  static let v3ToV4 = MigrationStage.lightweight(
    fromVersion: SchemaV3.self, toVersion: SchemaV4.self)

  /// Adds the Keep Offline marks' entity and changes nothing else (#358).
  static let v4ToV5 = MigrationStage.lightweight(
    fromVersion: SchemaV4.self, toVersion: SchemaV5.self)

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
  /// The app's container: V5, migrated from whatever version is on disk.
  public static func container(configurations: ModelConfiguration...) throws -> ModelContainer {
    try ModelContainer(
      for: Schema(versionedSchema: SchemaV5.self), migrationPlan: UserDataMigrationPlan.self,
      configurations: configurations)
  }

  /// Merges rows that name the same document — keeping the newest bookmark and
  /// reading position, and the earliest item in a collection and Keep Offline mark. Without a unique
  /// constraint — CloudKit refuses one — two devices, or a race, can leave two.
  @MainActor
  public static func deduplicate(_ context: ModelContext) throws {
    let bookmarks = try context.fetch(
      FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    removeDuplicates(bookmarks, keyedBy: \.documentKey, in: context)
    let positions = try context.fetch(
      FetchDescriptor<ReadingPosition>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    removeDuplicates(positions, keyedBy: \.documentKey, in: context)
    // The earliest first, so the place the reader first gave a document survives.
    // Items whose collection is not in the store are left alone: under sync they
    // may have arrived before it (#349).
    let items = try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(sortBy: [
        SortDescriptor(\.addedAt), SortDescriptor(\.position),
      ]))
    removeDuplicates(
      items, keyedBy: { "\($0.collectionIdentifier?.uuidString ?? "")/\($0.documentKey)" },
      in: context)
    let marks = try context.fetch(FetchDescriptor<OfflineMark>(sortBy: [SortDescriptor(\.markedAt)]))
    removeDuplicates(marks, keyedBy: \.documentKey, in: context)
    if context.hasChanges { try context.save() }
  }

  /// Keeps the first row per key and deletes the rest, so `rows` come in the order
  /// of preference: newest first for bookmarks and positions, earliest first for
  /// collection items and marks.
  private static func removeDuplicates<Row: PersistentModel>(
    _ rows: [Row], keyedBy key: (Row) -> String, in context: ModelContext
  ) {
    var seen: Set<String> = []
    for row in rows where !seen.insert(key(row)).inserted {
      context.delete(row)
    }
  }
}
