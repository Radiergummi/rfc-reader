import Foundation
import RFCKit

/// Where a document's body is stored (#358).
public enum StorageTier: Sendable, Hashable {
  /// `Application Support`, kept until the document is no longer wanted offline:
  /// a promise, with no bound.
  case kept
  /// `Caches`, which the system may purge and `CacheEviction` bounds.
  case cache

  /// The tier `id`'s body belongs in, given what is wanted offline: where a fetch
  /// that finishes writes it, whoever asked for it.
  public static func of(_ id: DocumentID, wanted: Set<DocumentID>) -> StorageTier {
    wanted.contains(id) ? .kept : .cache
  }
}

/// What keeping documents offline still owes, given the marks and what is on disk
/// (#358).
///
/// The App target runs it again whenever a mark changes, the network path changes or
/// Low Power Mode does, and carries out its plan: moves through the store, fetches
/// through `FetchPolicy` with a discretionary cause. Pure, and here rather than in
/// the App target, because the App target has no test bundle.
public enum OfflineReconciler {
  /// What to do to bring the disk in line with what is wanted.
  public struct Plan: Sendable, Hashable {
    /// Bodies to move from the cache into the kept tier. Marking a document already
    /// read fetches nothing.
    public var keep: Set<DocumentID>
    /// Bodies to move from the kept tier back into the cache, where eviction treats
    /// them as any other. Unmarking does not delete.
    public var release: Set<DocumentID>
    /// Wanted documents with a body in neither tier and no fetch running: the
    /// fetches still owed.
    public var fetch: Set<DocumentID>
    /// Running fetches nobody waits for, for documents no longer wanted, to stop so
    /// they spend no more of the connection.
    public var cancel: Set<DocumentID>

    public init(
      keep: Set<DocumentID> = [], release: Set<DocumentID> = [], fetch: Set<DocumentID> = [],
      cancel: Set<DocumentID> = []
    ) {
      self.keep = keep
      self.release = release
      self.fetch = fetch
      self.cancel = cancel
    }
  }

  /// The documents wanted offline: every marked one, and every bookmarked one when
  /// "Keep bookmarked documents offline" is on. A bookmark otherwise means "find
  /// this again", not "store this".
  public static func wanted(
    marks: Set<DocumentID>, bookmarks: Set<DocumentID>, keepsBookmarks: Bool
  ) -> Set<DocumentID> {
    keepsBookmarks ? marks.union(bookmarks) : marks
  }

  /// The plan for `wanted`, given the bodies in each tier and the fetches running,
  /// with why each was started.
  ///
  /// A fetch already running for a wanted document is not owed again: a reader's
  /// open is joined, not doubled. One running for a document no longer wanted is
  /// stopped only when nobody waits for it; a reader's goes on, and its body lands
  /// in the cache (`StorageTier.of`).
  public static func plan(
    wanted: Set<DocumentID>, kept: Set<DocumentID>, cached: Set<DocumentID>,
    fetching: [DocumentID: FetchPolicy.Cause] = [:]
  ) -> Plan {
    Plan(
      keep: wanted.intersection(cached).subtracting(kept),
      release: kept.subtracting(wanted),
      fetch: wanted.subtracting(kept).subtracting(cached).subtracting(fetching.keys),
      cancel: Set(
        fetching.filter { !$0.value.isAwaited && !wanted.contains($0.key) }.keys))
  }
}
