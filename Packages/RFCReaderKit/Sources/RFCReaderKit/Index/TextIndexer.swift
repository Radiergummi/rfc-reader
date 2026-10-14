import Foundation
import RFCKit
import os

private let indexerLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "text-index")

/// Keeps the full-text index (#37) to what the store holds: every document with a body
/// in either tier is indexed, and one whose body is removed, evicted or purged is
/// dropped. The index follows the store rather than being told of each body, so a
/// body is never indexed that is not on disk, whichever path wrote or removed it.
///
/// The one place the index is written and searched, from this actor's executor:
/// `FullTextIndex` is one connection, used from one task.
public actor TextIndexer {
  private let store: DocumentStore
  private let index: FullTextIndex

  /// Every document indexed, read from the index once and kept as it is changed here,
  /// the one place it is written: each search counts them.
  private var indexed: Set<DocumentID>?

  /// The stored bodies that could not be read or indexed, which a reconcile does not
  /// try again while they stay stored: each change to the store would parse them
  /// again. One whose body goes is forgotten, so a body stored again is tried again.
  private var unindexable: Set<DocumentID> = []

  /// How many documents a long reconcile indexes between the calls of its `changed`,
  /// so a search on show fills in while the first pass works through every body.
  private static let progressInterval = 25

  /// What the app's index is kept in: Application Support, in a folder excluded from
  /// backups, since it is made again from the bodies.
  public static var defaultURL: URL {
    get throws {
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
      var folder = support.appending(path: "RFCReader/FullText", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      var excluded = URLResourceValues()
      excluded.isExcludedFromBackup = true
      try folder.setResourceValues(excluded)
      return folder.appending(path: "sections.sqlite")
    }
  }

  /// An indexer keeping the index at `url`, made when there is none, to `store`.
  public init(contentsOf url: URL, store: DocumentStore) throws {
    self.store = store
    self.index = try FullTextIndex(contentsOf: url)
  }

  /// The app's indexer, at `defaultURL`, opened off the caller's actor: opening may
  /// make the folder and the tables.
  @concurrent
  public static func opening(store: DocumentStore) async throws -> TextIndexer {
    try TextIndexer(contentsOf: defaultURL, store: store)
  }

  /// Reconciles once, then again after each change to the store's bodies, until the
  /// task is cancelled. `changed` is called whenever the index has changed, for a
  /// search on show to be made again: after each reconcile that changed it, and every
  /// few documents during a long one.
  public func run(changed: @Sendable () async -> Void = {}) async {
    await reconcile(changed: changed)
    for await _ in store.bodiesChanged {
      await reconcile(changed: changed)
    }
  }

  /// Indexes every body the store holds that the index lacks, and drops every
  /// document the index holds that the store no longer has a body of. `changed` is
  /// called as `run(changed:)` says.
  ///
  /// A body removed while it was being parsed here is indexed all the same; the
  /// removal is a change of its own, and the reconcile after it drops it.
  public func reconcile(changed: @Sendable () async -> Void = {}) async {
    let state = await store.offlineState()
    let stored = state.kept.union(state.cached)
    unindexable.formIntersection(stored)
    guard let before = indexedDocuments() else { return }
    var unannounced = 0
    for id in before.subtracting(stored) {
      do {
        try index.remove(id)
        indexed?.remove(id)
        unannounced += 1
      } catch {
        indexerLog.error(
          "\(id.displayName, privacy: .public): not removed from the index: \(String(describing: error), privacy: .public)"
        )
      }
    }
    for id in stored.subtracting(before).subtracting(unindexable).sorted() {
      guard !Task.isCancelled else { break }
      if unannounced >= Self.progressInterval {
        unannounced = 0
        await changed()
      }
      guard var document = await store.storedDocument(id) else {
        unindexable.insert(id)
        continue
      }
      // Under the id it is stored as, whatever its header says: a body whose header
      // names another document, or none, would otherwise never be found indexed.
      document.header.id = id
      do {
        try index.add(document)
        indexed?.insert(id)
        unannounced += 1
      } catch {
        unindexable.insert(id)
        indexerLog.error(
          "\(id.displayName, privacy: .public): not indexed: \(String(describing: error), privacy: .public)"
        )
      }
    }
    if unannounced > 0 { await changed() }
  }

  /// `indexed`, read from the index the first time; nil when it cannot be read.
  private func indexedDocuments() -> Set<DocumentID>? {
    if let indexed { return indexed }
    do {
      indexed = try index.indexed()
    } catch {
      indexerLog.error(
        "reading what is indexed failed: \(String(describing: error), privacy: .public)")
    }
    return indexed
  }

  /// What a search found, and how many documents it searched.
  public struct Found: Sendable {
    public var hits: [SectionHit]
    /// How many of the documents the search could look in are indexed: of every
    /// document, or of those it was narrowed to.
    public var searched: Int
    /// How many documents the search was narrowed to, or nil for every one.
    public var narrowedTo: Int?
  }

  /// The sections holding every word of `query`, best first; see
  /// `FullTextIndex.search`, `section` included. `allowed`, when given, are the only
  /// documents a hit may be in.
  public func search(
    _ query: String, section: String? = nil, limit: Int = 50, in allowed: Set<DocumentID>? = nil
  ) throws -> Found {
    let hits = try index.search(
      query, section: section, limit: limit, where: allowed.map { allowed in allowed.contains })
    let indexed = indexedDocuments() ?? []
    let searched = allowed.map { indexed.intersection($0).count } ?? indexed.count
    return Found(hits: hits, searched: searched, narrowedTo: allowed?.count)
  }
}
