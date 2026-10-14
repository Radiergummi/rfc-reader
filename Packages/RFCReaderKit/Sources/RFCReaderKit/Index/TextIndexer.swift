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

  /// Reconciles once, then again after each change to the store's bodies, until the
  /// task is cancelled. `changed` is called after each reconcile that changed the
  /// index, for a search on show to be made again.
  public func run(changed: @Sendable () async -> Void = {}) async {
    if await reconcile() { await changed() }
    for await _ in store.bodiesChanged {
      if await reconcile() { await changed() }
    }
  }

  /// Indexes every body the store holds that the index lacks, and drops every
  /// document the index holds that the store no longer has a body of.
  ///
  /// A body removed while it was being parsed here is indexed all the same; the
  /// removal is a change of its own, and the reconcile after it drops it. Answers
  /// whether a document was added or removed.
  @discardableResult
  public func reconcile() async -> Bool {
    let state = await store.offlineState()
    let stored = state.kept.union(state.cached)
    let indexed: Set<DocumentID>
    do {
      indexed = try index.indexed()
    } catch {
      indexerLog.error(
        "reading what is indexed failed: \(String(describing: error), privacy: .public)")
      return false
    }
    var changed = false
    for id in indexed.subtracting(stored) {
      do {
        try index.remove(id)
        changed = true
      } catch {
        indexerLog.error(
          "\(id.displayName, privacy: .public): not removed from the index: \(String(describing: error), privacy: .public)"
        )
      }
    }
    for id in stored.subtracting(indexed).sorted() {
      guard !Task.isCancelled else { return changed }
      guard var document = await store.storedDocument(id) else { continue }
      // A legacy text whose header names no number is still the body it was stored as.
      if document.header.id == nil { document.header.id = id }
      do {
        try index.add(document)
        changed = true
      } catch {
        indexerLog.error(
          "\(id.displayName, privacy: .public): not indexed: \(String(describing: error), privacy: .public)"
        )
      }
    }
    return changed
  }

  /// What a search found, and how many documents it searched.
  public struct Found: Sendable {
    public var hits: [SectionHit]
    /// How many documents are indexed: "searched 37 of 9,842 RFCs".
    public var searched: Int
  }

  /// The sections holding every word of `query`, best first; see
  /// `FullTextIndex.search`. `allowed`, when given, are the only documents a hit may
  /// be in.
  public func search(
    _ query: String, limit: Int = 50, in allowed: Set<DocumentID>? = nil
  ) throws -> Found {
    let hits = try index.search(
      query, limit: limit, where: allowed.map { allowed in allowed.contains })
    return Found(hits: hits, searched: try index.indexed().count)
  }
}
