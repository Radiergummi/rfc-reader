import Foundation
import RFCKit
import os

private let indexerLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "text-index")

/// Keeps the full-text index (#37) to what the store holds: every document with a body
/// in either tier is indexed, again when its body is written again, and one whose body
/// is removed, evicted or purged is dropped. The index follows the store rather than being told of each body, so a
/// body is never indexed that is not on disk, whichever path wrote or removed it.
///
/// Index All RFCs (`indexAll`) is the exception: it indexes documents whose bodies it
/// does not keep, and the index marks them retained, so they stay whatever the store
/// holds until `releaseRetained`.
///
/// The one place the index is written and searched, from this actor's executor:
/// `FullTextIndex` is one connection, used from one task.
public actor TextIndexer {
  private let store: DocumentStore
  private let index: FullTextIndex

  /// Every document indexed, with when its body was written, read from the index once
  /// and kept as it is changed here, the one place it is written: each search counts
  /// them.
  private var indexed: [DocumentID: Date]?

  /// The documents indexed by Index All RFCs, read and kept as `indexed` is.
  private var retained: Set<DocumentID> = []

  /// The stored bodies that could not be read or indexed, with when they were written,
  /// which a reconcile does not try again while they stay as they are: each change to
  /// the store would parse them again. A body removed or written again is tried again.
  private var unindexable: [DocumentID: Date] = [:]

  /// How many documents a long reconcile indexes between the calls of its `changed`,
  /// so a search on show fills in while the first pass works through every body.
  private static let progressInterval = 25

  /// How many documents Index All RFCs downloads at once.
  private static let concurrentDownloads = 4

  private let url: URL

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
    self.url = url
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

  /// Indexes every body the store holds that the index lacks, or holds as it was
  /// before it was written again, and drops every document the index holds that the
  /// store no longer has a body of. `changed` is called as `run(changed:)` says.
  ///
  /// A body removed while it was being parsed here is indexed all the same; the
  /// removal is a change of its own, and the reconcile after it drops it.
  public func reconcile(changed: @Sendable () async -> Void = {}) async {
    let stored = await store.storedBodies()
    unindexable = unindexable.filter { stored[$0.key] == $0.value }
    guard let before = indexedDocuments() else { return }
    var unannounced = 0
    // In one transaction: after Remove Full-Text Index, nearly every document goes.
    let gone = before.keys.filter { stored[$0] == nil && !retained.contains($0) }
    do {
      try index.remove(gone)
      for id in gone {
        indexed?[id] = nil
      }
      unannounced += gone.count
    } catch {
      indexerLog.error(
        "\(gone.count, privacy: .public) documents not removed from the index: \(String(describing: error), privacy: .public)"
      )
    }
    let unindexed = stored.filter { id, written in
      before[id] != written && unindexable[id] != written
    }
    for (id, written) in unindexed.sorted(by: { $0.key < $1.key }) {
      guard !Task.isCancelled else { break }
      if unannounced >= Self.progressInterval {
        unannounced = 0
        await changed()
      }
      guard var document = await store.storedDocument(id) else {
        unindexable[id] = written
        continue
      }
      // Under the id it is stored as, whatever its header says: a body whose header
      // names another document, or none, would otherwise never be found indexed.
      document.header.id = id
      do {
        try index.add(document, written: written)
        indexed?[id] = written
        unannounced += 1
      } catch {
        unindexable[id] = written
        indexerLog.error(
          "\(id.displayName, privacy: .public): not indexed: \(String(describing: error), privacy: .public)"
        )
      }
    }
    if unannounced > 0 { await changed() }
  }

  /// `indexed`, read from the index the first time, with `retained`; nil when it
  /// cannot be read.
  private func indexedDocuments() -> [DocumentID: Date]? {
    if let indexed { return indexed }
    do {
      retained = try index.retained()
      indexed = try index.indexed()
    } catch {
      indexerLog.error(
        "reading what is indexed failed: \(String(describing: error), privacy: .public)")
    }
    return indexed
  }

  // MARK: - Index All RFCs

  /// How far Index All RFCs has got: of the `total` documents it was given, how many
  /// are indexed, and how many it could not download or parse.
  public struct CorpusProgress: Sendable, Equatable {
    public var indexed: Int
    public var total: Int
    public var failed: Int

    public init(indexed: Int, total: Int, failed: Int) {
      self.indexed = indexed
      self.total = total
      self.failed = failed
    }
  }

  /// Index All RFCs: indexes every one of `ids`, retained, so it stays when the store
  /// holds no body of it, downloading with `fetch` each that is not indexed yet and
  /// keeping no body. A document indexed already is retained as it is, so a run
  /// stopped or cancelled is resumed by the next, which downloads only the rest, and
  /// tries again those that failed. A document the installed legacy pack holds is
  /// read from the pack instead, as the reader reads it, so a hit's anchor is one the
  /// reader has.
  ///
  /// `progress` is called after each document, beginning with what was indexed
  /// already; `changed` as `run(changed:)` says. Cancelled, the run ends with what it
  /// has indexed, and counts nothing it left as failed.
  public func indexAll(
    _ ids: [DocumentID],
    fetch: @escaping @Sendable (DocumentID) async throws -> RFCDocument,
    progress: @Sendable (CorpusProgress) async -> Void = { _ in },
    changed: @Sendable () async -> Void = {}
  ) async -> CorpusProgress {
    let before = indexedDocuments() ?? [:]
    let present = ids.filter { before[$0] != nil }
    let unretained = present.filter { !retained.contains($0) }
    if !unretained.isEmpty {
      do {
        try index.retain(unretained)
        retained.formUnion(unretained)
        await changed()
      } catch {
        indexerLog.error(
          "retaining what is indexed failed: \(String(describing: error), privacy: .public)")
      }
    }
    let store = store
    var counted = CorpusProgress(indexed: present.count, total: ids.count, failed: 0)
    await progress(counted)
    var missing = ids.filter { before[$0] == nil }.makeIterator()
    var unannounced = 0
    await withTaskGroup(of: (DocumentID, Result<RFCDocument, any Error>).self) { group in
      func download(_ id: DocumentID) {
        group.addTask {
          if let document = await store.packDocument(id) {
            return (id, .success(document))
          }
          do {
            return (id, .success(try await fetch(id)))
          } catch {
            return (id, .failure(error))
          }
        }
      }
      for _ in 0..<Self.concurrentDownloads {
        guard let id = missing.next() else { break }
        download(id)
      }
      for await (id, fetched) in group {
        if Task.isCancelled {
          group.cancelAll()
          continue
        }
        switch fetched {
        case .success(var document):
          document.header.id = id
          do {
            try index.add(document, retained: true)
            indexed?[id] = .distantPast
            retained.insert(id)
            counted.indexed += 1
            unannounced += 1
          } catch {
            counted.failed += 1
            indexerLog.error(
              "\(id.displayName, privacy: .public): not indexed: \(String(describing: error), privacy: .public)"
            )
          }
        case .failure(let error):
          counted.failed += 1
          indexerLog.error(
            "\(id.displayName, privacy: .public): not downloaded to index: \(String(describing: error), privacy: .public)"
          )
        }
        await progress(counted)
        if unannounced >= Self.progressInterval {
          unannounced = 0
          await changed()
        }
        if let next = missing.next() {
          download(next)
        }
      }
    }
    if unannounced > 0 { await changed() }
    return counted
  }

  /// Remove Full-Text Index: no document is retained any more, and those the store
  /// holds no body of leave the index, which goes back to the bodies the store holds,
  /// and gives back the disk they took.
  public func releaseRetained(changed: @Sendable () async -> Void = {}) async {
    do {
      try index.releaseRetained()
      retained = []
    } catch {
      indexerLog.error(
        "releasing what Index All RFCs indexed failed: \(String(describing: error), privacy: .public)"
      )
      return
    }
    await reconcile(changed: changed)
    do {
      try index.compact()
    } catch {
      indexerLog.error(
        "compacting the index failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// What the index holds, for Settings.
  public struct Usage: Sendable, Equatable {
    /// How many documents are indexed, and how much of the disk the index takes,
    /// its journal included.
    public var usage: StorageUsage
    /// How many of them Index All RFCs indexed.
    public var retained: Int
  }

  public func usage() -> Usage {
    let bytes = ["", "-wal"].reduce(0) { total, suffix in
      let file = URL(filePath: url.path + suffix)
      return total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    let documents = indexedDocuments()?.count ?? 0
    return Usage(
      usage: StorageUsage(documents: documents, bytes: bytes), retained: retained.count)
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
    let indexed = indexedDocuments() ?? [:]
    let searched = allowed.map { $0.count { indexed[$0] != nil } } ?? indexed.count
    return Found(hits: hits, searched: searched, narrowedTo: allowed?.count)
  }
}
