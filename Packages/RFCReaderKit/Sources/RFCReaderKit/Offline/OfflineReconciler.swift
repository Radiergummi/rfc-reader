import RFCKit

/// Where a document's body is stored (#358).
public enum StorageTier: Sendable, Hashable {
  /// Kept until the document is no longer wanted offline: a promise, with no bound,
  /// and the store's to write in `Application Support`.
  case kept
  /// The reading cache, which `CacheEviction` bounds, and the store's to write in
  /// `Caches`, which the system may purge.
  case cache

  /// The tier `id`'s body belongs in, given what is wanted offline: where a fetch
  /// that finishes writes it, whoever asked for it.
  public static func of(_ id: DocumentID, wanted: Set<DocumentID>) -> StorageTier {
    wanted.contains(id) ? .kept : .cache
  }

  /// What the cache leaves free on the disk: reading is never what fills it.
  public static let cacheReserve = 100 * 1024 * 1024

  /// The bytes free for a body, from what the volume reports: `usage` is its
  /// capacity for important or opportunistic usage, and `available` its plain
  /// available capacity. A volume that does not report the usage, as some that are
  /// not APFS answer 0, is read by its available capacity instead, so a full disk
  /// still reads 0. Nil when neither can be read.
  public static func freeSpace(forUsage usage: Int64?, available: Int64?) -> Int? {
    if let usage, usage > 0 { return Int(clamping: usage) }
    return available.map { Int(clamping: $0) }
  }

  /// Whether a body of `bytes` is written to this tier, with `available` bytes free
  /// for it: the volume's capacity for important usage for a kept body, which is a
  /// promise and needs only its own room, and for opportunistic usage for a cached
  /// one, which leaves the reserve as well. A capacity that cannot be read blocks
  /// neither.
  public func hasRoom(for bytes: Int, available: Int?) -> Bool {
    guard let available else { return true }
    switch self {
    case .kept: return available >= bytes
    case .cache: return available >= bytes + Self.cacheReserve
    }
  }
}

/// What keeping documents offline still owes, given the marks and what is on disk
/// (#358).
///
/// The App target runs it again whenever a mark changes, the network path changes or
/// Low Power Mode does, and carries out its plan. Pure, and here rather than in the
/// App target, because the App target has no test bundle.
///
/// The fetches it starts are its own waiters on the store's downloads, as a reader's
/// open is one: to stop one, it leaves, and `InFlightDownloads` cancels the download
/// only when nobody else waits for it (#116). So a reader who opened the document
/// meanwhile still gets it, and the reconciler never has to know who else is waiting.
public enum OfflineReconciler {
  /// What to do to bring the disk in line with what is wanted.
  public struct Plan: Sendable, Hashable {
    /// Bodies to move from the cache into the kept tier: marking a document already
    /// read fetches nothing.
    public var keep: Set<DocumentID>
    /// Bodies to move from the kept tier back into the cache, where eviction treats
    /// them as any other: unmarking does not delete.
    ///
    /// A move replaces a body already at its destination, so a document with a body
    /// in both tiers ends with one, in the tier it belongs in.
    public var release: Set<DocumentID>
    /// Documents to start fetching, with a discretionary cause.
    public var fetch: Set<DocumentID>
    /// Documents owed a fetch that the path does not allow now, the reason being
    /// `deferral`: their rows say so, with Download Now.
    public var waiting: Set<DocumentID>
    /// Why `waiting` waits; `nil` when nothing does.
    public var deferral: FetchPolicy.Reason?
    /// The reconciler's own fetches to leave: those for documents no longer wanted,
    /// and all of them when the path stops allowing them.
    public var leave: Set<DocumentID>

    public init(
      keep: Set<DocumentID> = [], release: Set<DocumentID> = [], fetch: Set<DocumentID> = [],
      waiting: Set<DocumentID> = [], deferral: FetchPolicy.Reason? = nil,
      leave: Set<DocumentID> = []
    ) {
      self.keep = keep
      self.release = release
      self.fetch = fetch
      self.waiting = waiting
      self.deferral = deferral
      self.leave = leave
    }
  }

  /// The documents wanted offline: every marked one, and every bookmarked one when
  /// "Keep bookmarked documents offline" is on. A bookmark otherwise means "find
  /// this again", not "store this", and its body stays in the cache.
  public static func wanted(
    marks: Set<DocumentID>, bookmarks: Set<DocumentID>, keepsBookmarks: Bool
  ) -> Set<DocumentID> {
    keepsBookmarks ? marks.union(bookmarks) : marks
  }

  /// The plan for `wanted`.
  ///
  /// - Parameters:
  ///   - kept: the documents with a body in the kept tier.
  ///   - cached: the documents with a body in the cache.
  ///   - running: every document with a download running, whoever started it. One is
  ///     not owed another fetch, since a fetch would join it, and its body is not
  ///     moved while the download may still write it; the next run moves it.
  ///   - own: the documents the reconciler itself is waiting on, a subset of `running`.
  ///   - failed: the documents whose last fetch failed. One is owed no fetch, and is
  ///     not listed as waiting either: its row offers Retry instead.
  ///   - policy: `FetchPolicy`'s decision for a discretionary fetch on the path now.
  public static func plan(
    wanted: Set<DocumentID>, kept: Set<DocumentID>, cached: Set<DocumentID>,
    running: Set<DocumentID> = [], own: Set<DocumentID> = [], failed: Set<DocumentID> = [],
    policy: FetchPolicy.Decision = .fetch
  ) -> Plan {
    let owed = wanted.subtracting(kept).subtracting(cached).subtracting(running)
      .subtracting(failed)
    var plan = Plan(
      keep: wanted.intersection(cached).subtracting(running),
      release: kept.subtracting(wanted).subtracting(running))
    switch policy {
    case .fetch:
      plan.fetch = owed
      plan.leave = own.subtracting(wanted)
    case .deferred(let reason):
      // What the reconciler was fetching and still wants waits with the rest.
      plan.waiting = owed.union(own.intersection(wanted))
      plan.deferral = plan.waiting.isEmpty ? nil : reason
      plan.leave = own
    }
    return plan
  }
}
