import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the app reads collections through (#349).
@Suite("Collection snapshot")
@MainActor
struct CollectionSnapshotTests {
  private let early = Date(timeIntervalSince1970: 1_000)
  private let late = Date(timeIntervalSince1970: 2_000)

  @Test func `collections are in sidebar order`() {
    let second = DocumentCollection(name: "DNS", color: .green, position: 2)
    let first = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)

    let snapshot = CollectionSnapshot(collections: [second, first], items: [])

    #expect(snapshot.collections.map(\.name) == ["HTTP/3", "DNS"])
    #expect(snapshot.collections.map(\.color) == [.blue, .green])
  }

  @Test func `members are in the collection's order`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 2),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9000), .rfc(9114)])
    #expect(snapshot[id]?.rfcNumbers == [9000, 9114])
  }

  /// Two devices appending offline both write "after the last".
  @Test func `equal positions fall back to when the item was added`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 1, addedAt: late),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1, addedAt: early),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9000), .rfc(9114)])
  }

  @Test func `items of a collection not in the snapshot are ignored`() {
    let items = [DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1)]
    #expect(CollectionSnapshot(collections: [], items: items).collections.isEmpty)
  }

  @Test func `a document listed twice appears once, where it first appears`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 1),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 2),
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 3),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9114), .rfc(9000)])
  }

  /// A key this version cannot read, or a series, is not an RFC the lists can show.
  @Test func `only RFCs are counted and listed`() {
    let collection = DocumentCollection(name: "Mixed", color: .blue, position: 1)
    let id = collection.identifier
    let unreadable = DocumentCollectionItem(collection: id, document: .rfc(1), position: 3)
    unreadable.documentKey = "draft-ietf-quic"
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1),
      DocumentCollectionItem(
        collection: id, document: DocumentID(series: .bcp, number: 14), position: 2),
      unreadable,
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.rfcNumbers == [9000])
  }

  @Test func `which collections hold a document`() {
    let http = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let transport = DocumentCollection(name: "Transport", color: .green, position: 2)
    let items = [
      DocumentCollectionItem(collection: http.identifier, document: .rfc(9000), position: 1),
      DocumentCollectionItem(collection: transport.identifier, document: .rfc(9000), position: 1),
      DocumentCollectionItem(collection: http.identifier, document: .rfc(9114), position: 2),
    ]

    let snapshot = CollectionSnapshot(collections: [http, transport], items: items)

    #expect(
      snapshot.collections(containing: .rfc(9000)) == [http.identifier, transport.identifier])
    #expect(snapshot.collections(containing: .rfc(9114)) == [http.identifier])
  }
}
