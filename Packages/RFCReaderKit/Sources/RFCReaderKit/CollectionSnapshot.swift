import Foundation
import RFCKit
import SwiftData

/// Every collection and its members, as values (#349).
///
/// What the app reads collections through: the sidebar and its counts, a
/// collection's list, the Add to Collection menus, the Mac's menu bar and scripts.
/// Built from one fetch, and `Equatable` so the app publishes a new one only when it
/// differs — most saves of the store record a reading position, not a collection.
public struct CollectionSnapshot: Equatable, Sendable {
  public struct Entry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let color: CollectionColor
    /// In the collection's order, each document once.
    public let members: [DocumentID]

    public init(id: UUID, name: String, color: CollectionColor, members: [DocumentID]) {
      self.id = id
      self.name = name
      self.color = color
      self.members = members
    }

    /// The members the lists can show: the lists list RFCs.
    public var rfcNumbers: [Int] {
      members.filter { $0.series == .rfc }.map(\.number)
    }
  }

  /// In sidebar order.
  public let collections: [Entry]

  public static let empty = CollectionSnapshot(collections: [])

  public init(collections: [Entry]) {
    self.collections = collections
  }

  /// From the store's rows: collections in `(position, createdAt, identifier)`
  /// order, members in `(position, addedAt, documentKey)` order. Items naming a
  /// collection that is not among `collections`, and keys that name no document,
  /// are left out.
  public init(collections: [DocumentCollection], items: [DocumentCollectionItem]) {
    let orderedItems = items.sorted {
      ($0.position, $0.addedAt, $0.documentKey) < ($1.position, $1.addedAt, $1.documentKey)
    }
    var membersByCollection: [UUID: [DocumentID]] = [:]
    for item in orderedItems {
      guard let collection = item.collectionIdentifier, let document = item.document else {
        continue
      }
      if membersByCollection[collection]?.contains(document) != true {
        membersByCollection[collection, default: []].append(document)
      }
    }
    let orderedCollections = collections.sorted {
      ($0.position, $0.createdAt, $0.identifier.uuidString)
        < ($1.position, $1.createdAt, $1.identifier.uuidString)
    }
    self.collections = orderedCollections.map {
      Entry(
        id: $0.identifier, name: $0.name, color: $0.color,
        members: membersByCollection[$0.identifier] ?? [])
    }
  }

  public subscript(_ identifier: UUID) -> Entry? {
    collections.first { $0.id == identifier }
  }

  /// The collections `document` is in, for the Add to Collection menus' checkmarks.
  public func collections(containing document: DocumentID) -> Set<UUID> {
    Set(collections.filter { $0.members.contains(document) }.map(\.id))
  }

  /// The store's collections, now. Only the fields a snapshot reads: this runs
  /// on every save, and most of those record a reading position.
  @MainActor
  public static func fetch(in context: ModelContext) -> CollectionSnapshot {
    var collectionFetch = FetchDescriptor<DocumentCollection>()
    collectionFetch.propertiesToFetch = [
      \.identifier, \.name, \.colorName, \.position, \.createdAt,
    ]
    var itemFetch = FetchDescriptor<DocumentCollectionItem>()
    itemFetch.propertiesToFetch = [
      \.collectionIdentifier, \.documentKey, \.position, \.addedAt,
    ]
    let collections = (try? context.fetch(collectionFetch)) ?? []
    let items = (try? context.fetch(itemFetch)) ?? []
    return CollectionSnapshot(collections: collections, items: items)
  }
}
