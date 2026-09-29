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
  /// The collections each document is in: asked once per list row, by the Add to
  /// Collection menus' checkmarks.
  private let memberships: [DocumentID: Set<UUID>]

  public static let empty = CollectionSnapshot(collections: [])

  public init(collections: [Entry]) {
    self.collections = collections
    var memberships: [DocumentID: Set<UUID>] = [:]
    for entry in collections {
      for document in entry.members {
        memberships[document, default: []].insert(entry.id)
      }
    }
    self.memberships = memberships
  }

  /// From the store's rows: collections in `DocumentCollection.order`, members in
  /// `DocumentCollectionItem.order`. Items naming a collection that is not among
  /// `collections`, and keys that name no document, are left out.
  public init(collections: [DocumentCollection], items: [DocumentCollectionItem]) {
    let orderedItems = items.sorted(using: DocumentCollectionItem.order)
    var membersByCollection: [UUID: [DocumentID]] = [:]
    var seen: Set<Pair> = []
    for item in orderedItems {
      guard let collection = item.collectionIdentifier, let document = item.document else {
        continue
      }
      if seen.insert(Pair(collection: collection, document: document)).inserted {
        membersByCollection[collection, default: []].append(document)
      }
    }
    let orderedCollections = collections.sorted(using: DocumentCollection.order)
    self.init(
      collections: orderedCollections.map {
        Entry(
          id: $0.identifier, name: $0.name, color: $0.color,
          members: membersByCollection[$0.identifier] ?? [])
      })
  }

  /// A document in a collection, for keeping each document once per collection.
  private struct Pair: Hashable {
    let collection: UUID
    let document: DocumentID
  }

  public subscript(_ identifier: UUID) -> Entry? {
    collections.first { $0.id == identifier }
  }

  /// The collections `document` is in, for the Add to Collection menus' checkmarks.
  public func collections(containing document: DocumentID) -> Set<UUID> {
    memberships[document] ?? []
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
