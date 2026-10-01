import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What keeping documents offline still owes, given the marks and what is on disk
/// (#358): bodies moved between the tiers, fetches to make, and fetches to stop.
@Suite("Offline reconciler")
struct OfflineReconcilerTests {
  /// Marked documents are wanted; bookmarked ones only with the setting on, since a
  /// bookmark means "find this again", not "store this".
  @Test func `what is wanted is the marks, and the bookmarks with the setting on`() {
    let marks: Set<DocumentID> = [.rfc(1), .rfc(2)]
    let bookmarks: Set<DocumentID> = [.rfc(2), .rfc(3)]
    #expect(
      OfflineReconciler.wanted(marks: marks, bookmarks: bookmarks, keepsBookmarks: false) == marks)
    #expect(
      OfflineReconciler.wanted(marks: marks, bookmarks: bookmarks, keepsBookmarks: true)
        == [.rfc(1), .rfc(2), .rfc(3)])
  }

  @Test func `a wanted body belongs in the kept tier, any other in the cache`() {
    let wanted: Set<DocumentID> = [.rfc(1)]
    #expect(StorageTier.of(.rfc(1), wanted: wanted) == .kept)
    #expect(StorageTier.of(.rfc(2), wanted: wanted) == .cache)
  }

  /// Marking a document already read moves its body across and fetches nothing.
  @Test func `a wanted body already cached is moved, not fetched`() {
    let plan = OfflineReconciler.plan(wanted: [.rfc(1)], kept: [], cached: [.rfc(1)])
    #expect(plan == OfflineReconciler.Plan(keep: [.rfc(1)]))
  }

  @Test func `a wanted body on neither tier is owed a fetch`() {
    let plan = OfflineReconciler.plan(wanted: [.rfc(1), .rfc(2)], kept: [.rfc(2)], cached: [])
    #expect(plan == OfflineReconciler.Plan(fetch: [.rfc(1)]))
  }

  /// Unmarking does not delete: the body goes back to the cache, where eviction
  /// treats it as any other.
  @Test func `a kept body no longer wanted is moved back to the cache`() {
    let plan = OfflineReconciler.plan(wanted: [], kept: [.rfc(1)], cached: [.rfc(2)])
    #expect(plan == OfflineReconciler.Plan(release: [.rfc(1)]))
  }

  /// A body in both tiers is kept where it is wanted and left alone otherwise; the
  /// kept copy is the one the plan speaks for.
  @Test func `a body in both tiers is not moved onto itself`() {
    #expect(
      OfflineReconciler.plan(wanted: [.rfc(1)], kept: [.rfc(1)], cached: [.rfc(1)]) == .init())
    #expect(
      OfflineReconciler.plan(wanted: [], kept: [.rfc(1)], cached: [.rfc(1)])
        == OfflineReconciler.Plan(release: [.rfc(1)]))
  }

  /// A fetch already running is not started again, whoever asked for it: a reader's
  /// open is joined, not doubled.
  @Test func `a wanted document being fetched is not owed another fetch`() {
    let plan = OfflineReconciler.plan(
      wanted: [.rfc(1), .rfc(2)], kept: [], cached: [],
      fetching: [.rfc(1): .open, .rfc(2): .syncedMark])
    #expect(plan == .init())
  }

  /// #116's case: the mark goes while its fetch runs. A fetch nobody waits for is
  /// stopped, so it spends no more of the connection; one a reader waits for goes on,
  /// and its body lands in the cache, since it is no longer wanted.
  @Test func `a mark removed while its fetch runs stops only a discretionary fetch`() {
    let plan = OfflineReconciler.plan(
      wanted: [], kept: [], cached: [],
      fetching: [.rfc(1): .syncedMark, .rfc(2): .open, .rfc(3): .bookmarkSetting])
    #expect(plan == OfflineReconciler.Plan(cancel: [.rfc(1), .rfc(3)]))
    #expect(StorageTier.of(.rfc(2), wanted: []) == .cache)
  }

  /// Turning the bookmark setting off releases the bookmarks' bodies, but not a body
  /// that is also marked.
  @Test func `turning the bookmark setting off releases only what is not marked`() {
    let marks: Set<DocumentID> = [.rfc(1)]
    let bookmarks: Set<DocumentID> = [.rfc(1), .rfc(2)]
    let kept: Set<DocumentID> = [.rfc(1), .rfc(2)]
    let withBookmarks = OfflineReconciler.wanted(
      marks: marks, bookmarks: bookmarks, keepsBookmarks: true)
    let withoutBookmarks = OfflineReconciler.wanted(
      marks: marks, bookmarks: bookmarks, keepsBookmarks: false)
    #expect(OfflineReconciler.plan(wanted: withBookmarks, kept: kept, cached: []) == .init())
    #expect(
      OfflineReconciler.plan(wanted: withoutBookmarks, kept: kept, cached: [])
        == OfflineReconciler.Plan(release: [.rfc(2)]))
  }
}
