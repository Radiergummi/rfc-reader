import RFCKit
import RFCReaderKit
import Testing

/// What keeping documents offline still owes, given the marks and what is on disk
/// (#358): bodies moved between the tiers, fetches to start, and the reconciler's own
/// fetches to leave.
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

  /// A kept body is a promise, written whenever it fits; a cached one is skipped when
  /// it would leave the disk with less than the reserve. Unknown capacity blocks
  /// neither.
  @Test func `a kept body needs only its own room, a cached one the reserve as well`() {
    let size = 1_000
    #expect(StorageTier.kept.hasRoom(for: size, available: size))
    #expect(!StorageTier.kept.hasRoom(for: size, available: size - 1))
    #expect(StorageTier.cache.hasRoom(for: size, available: size + StorageTier.cacheReserve))
    #expect(!StorageTier.cache.hasRoom(for: size, available: size + StorageTier.cacheReserve - 1))
    #expect(StorageTier.kept.hasRoom(for: size, available: nil))
    #expect(StorageTier.cache.hasRoom(for: size, available: nil))
  }

  /// A volume that reports no capacity for important or opportunistic usage is read
  /// by its plain available capacity instead: a full disk still reads 0 and blocks
  /// the write, and a volume that does not report the usage keys still has room.
  @Test func `a capacity of 0 for the usage falls back to the volume's available capacity`() {
    #expect(StorageTier.freeSpace(forUsage: 5_000, available: 9_000) == 5_000)
    #expect(StorageTier.freeSpace(forUsage: 0, available: 9_000) == 9_000)
    #expect(StorageTier.freeSpace(forUsage: 0, available: 0) == 0)
    #expect(StorageTier.freeSpace(forUsage: nil, available: 9_000) == 9_000)
    #expect(StorageTier.freeSpace(forUsage: 0, available: nil) == nil)
    #expect(StorageTier.freeSpace(forUsage: nil, available: nil) == nil)
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

  /// A body in both tiers is moved into the one it belongs in, replacing the copy
  /// there, so the two tiers end with one between them.
  @Test func `a body in both tiers ends in the one it belongs in`() {
    #expect(
      OfflineReconciler.plan(wanted: [.rfc(1)], kept: [.rfc(1)], cached: [.rfc(1)])
        == OfflineReconciler.Plan(keep: [.rfc(1)]))
    #expect(
      OfflineReconciler.plan(wanted: [], kept: [.rfc(1)], cached: [.rfc(1)])
        == OfflineReconciler.Plan(release: [.rfc(1)]))
  }

  /// A download already running, whoever started it, is not started again, and the
  /// body it may still write is not moved under it; the next run moves it.
  @Test func `a document being downloaded is neither fetched again nor moved`() {
    let plan = OfflineReconciler.plan(
      wanted: [.rfc(1), .rfc(2)], kept: [.rfc(3)], cached: [.rfc(2)],
      running: [.rfc(1), .rfc(2), .rfc(3)])
    #expect(plan == OfflineReconciler.Plan())
  }

  /// #116's case: the mark goes while the reconciler's fetch runs. It leaves that
  /// fetch, and `InFlightDownloads` stops the download unless a reader joined it, in
  /// which case its body lands in the cache. A reader's own download is not the
  /// reconciler's to leave.
  @Test func `a mark removed while its fetch runs leaves only the reconciler's own fetch`() {
    let plan = OfflineReconciler.plan(
      wanted: [.rfc(3)], kept: [], cached: [],
      running: [.rfc(1), .rfc(2), .rfc(3)], own: [.rfc(1), .rfc(3)])
    #expect(plan == OfflineReconciler.Plan(leave: [.rfc(1)]))
    #expect(StorageTier.of(.rfc(1), wanted: [.rfc(3)]) == .cache)
  }

  /// On a path the policy refuses, nothing is started, and the reconciler leaves the
  /// fetches it had running, which wait with the rest and say why.
  @Test func `a path that stops allowing discretionary fetches makes them wait`() {
    let plan = OfflineReconciler.plan(
      wanted: [.rfc(1), .rfc(2)], kept: [], cached: [],
      running: [.rfc(2), .rfc(3)], own: [.rfc(2), .rfc(3)],
      policy: .deferred(.waitingForWiFi))
    #expect(
      plan
        == OfflineReconciler.Plan(
          waiting: [.rfc(1), .rfc(2)], deferral: .waitingForWiFi, leave: [.rfc(2), .rfc(3)]))
  }

  /// Moves between the tiers fetch nothing, so they go ahead on any path; a deferral
  /// is named only when something waits for it.
  @Test func `a deferred path still moves bodies, and names no reason when nothing waits`() {
    let plan = OfflineReconciler.plan(
      wanted: [.rfc(1)], kept: [.rfc(2)], cached: [.rfc(1)], policy: .deferred(.offline))
    #expect(plan == OfflineReconciler.Plan(keep: [.rfc(1)], release: [.rfc(2)]))
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
    #expect(
      OfflineReconciler.plan(wanted: withBookmarks, kept: kept, cached: [])
        == OfflineReconciler.Plan())
    #expect(
      OfflineReconciler.plan(wanted: withoutBookmarks, kept: kept, cached: [])
        == OfflineReconciler.Plan(release: [.rfc(2)]))
  }
}
