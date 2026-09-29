import Foundation
import Testing

@testable import RFCReaderKit

/// A collection deleted in another tab or on another device (#349).
@Suite("Kept filter")
struct KeptFilterTests {
  private let entry = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .blue, members: [])

  @Test func `a deleted collection falls back to every RFC`() {
    #expect(KeptFilter.filter(.collection(UUID()), keeping: .empty) == .all)
  }

  @Test func `a collection still there stays`() {
    let snapshot = CollectionSnapshot(collections: [entry])
    #expect(KeptFilter.filter(.collection(entry.id), keeping: snapshot) == .collection(entry.id))
  }

  @Test func `other filters stay`() {
    #expect(KeptFilter.filter(.bookmarks, keeping: .empty) == .bookmarks)
    #expect(KeptFilter.filter(.workingGroup("quic"), keeping: .empty) == .workingGroup("quic"))
  }

  /// Replacing the value keeps a cleared selection cleared: a collapsed sidebar
  /// must not push a list because a collection went away.
  @Test func `replacing the kept value leaves a cleared selection cleared`() {
    var kept = KeptSelection(LibraryFilter.collection(entry.id))
    kept.selection = nil
    kept.replaceValue(.all)
    #expect(kept.value == .all)
    #expect(kept.selection == nil)
  }
}
