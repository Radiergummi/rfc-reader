import Foundation
import RFCKit
import Synchronization
import Testing

@testable import RFCReaderKit

/// The full-text index kept to what the store holds (#37): a body stored is indexed,
/// and one removed, evicted or purged leaves the index. Each test has a store and an
/// index of its own.
@Suite("Text indexer", .timeLimit(.minutes(1)))
struct TextIndexerTests {
  typealias Sandbox = DocumentStoreTests.Sandbox
  typealias GatedFetcher = DocumentStoreTests.GatedFetcher

  let id = DocumentID.rfc(8999)

  func indexURL(in sandbox: Sandbox) -> URL {
    sandbox.root.appending(path: "FullText.sqlite")
  }

  /// `id`'s body stored by an open, as a reader's open stores it.
  func storeBody(in store: DocumentStore) async throws {
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    _ = try await store.document(id, formats: [.xml], client: fetcher)
  }

  @Test func `a stored body is indexed at reconcile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)

    await indexer.reconcile()

    let found = try await indexer.search("intermediaries")
    #expect(found.hits.map(\.anchor) == ["connection-id"])
    #expect(found.hits.first?.document == id)
    #expect(found.searched == 1)
  }

  @Test func `a removed body leaves the index at reconcile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    await store.remove(id)
    await indexer.reconcile()

    let found = try await indexer.search("intermediaries")
    #expect(found.hits.isEmpty)
    #expect(found.searched == 0)
  }

  @Test func `an evicted body leaves the index at reconcile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    #expect(await store.evict(pinned: [], bound: 0) == [id])
    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries").hits.isEmpty)
  }

  /// The system purges Caches without telling the app: the store finds the body gone
  /// when it next looks, and so does the index.
  @Test func `a body purged from the disk leaves the index at reconcile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    try FileManager.default.removeItem(at: sandbox.file(id, format: .xml))
    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries").hits.isEmpty)
  }

  /// An index emptied by a new version, or made new, is filled from the bodies on
  /// disk, which a store opened afresh has not parsed.
  @Test func `a body on disk that is not indexed is indexed from the disk`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    try await storeBody(in: sandbox.store())

    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [id])
  }

  /// Indexing reads the body without opening it: when it was last opened is what
  /// eviction goes by.
  @Test func `indexing a body does not count as opening it`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    try await storeBody(in: sandbox.store())
    let file = sandbox.file(id, format: .xml)
    let longAgo = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: file.path)

    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    await indexer.reconcile()

    let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
    #expect(modified as? Date == longAgo)
  }

  /// A body written again under an id already indexed, as a newer download is, is
  /// indexed again: the index keeps when each body it holds was written. The text
  /// changed at run time stands for a newer body.
  @Test func `a body rewritten under an indexed id is indexed again`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    try await storeBody(in: sandbox.store())
    try await TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store()).reconcile()

    let file = sandbox.file(id, format: .xml)
    let rewritten = try String(contentsOf: file, encoding: .utf8)
      .replacing("intermediaries", with: "zyzzyva")
    try Data(rewritten.utf8).write(to: file, options: .atomic)
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    await indexer.reconcile()

    #expect(try await indexer.search("zyzzyva").hits.map(\.anchor) == ["connection-id"])
    #expect(try await indexer.search("intermediaries").hits.isEmpty)
  }

  /// Opening a body changes its modification date (`DocumentStore.markOpened`), not
  /// the body: it is not parsed again, in this run or the next.
  @Test func `a body that did not change is not indexed again`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    await store.markOpened(id)
    let changes = Changes()
    await indexer.reconcile(changed: changes.record)
    let relaunched = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    await relaunched.reconcile(changed: changes.record)

    #expect(await changes.count == 0)
  }

  @Test func `a search is narrowed to the documents allowed`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries", in: [.rfc(9000)]).hits.isEmpty)
    #expect(try await !indexer.search("intermediaries", in: [id]).hits.isEmpty)
  }

  /// "Searched 1 of 3 RFCs" in a list of three: the documents it could look in that
  /// are indexed, not every one indexed.
  @Test func `a narrowed search counts what it could look in`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries", in: [.rfc(9000)]).searched == 0)
    let narrowed = try await indexer.search("intermediaries", in: [id, .rfc(9000)])
    #expect(narrowed.searched == 1)
    #expect(narrowed.narrowedTo == 2)
    #expect(try await indexer.search("intermediaries").narrowedTo == nil)
  }

  /// The fetcher serves RFC 8999's XML whatever is asked, as a body whose header names
  /// another document: it is indexed under the id it is stored as, and once.
  @Test func `a body is indexed under the id it is stored as`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    _ = try await store.document(.rfc(2119), formats: [.xml], client: fetcher)

    let changes = Changes()
    await indexer.reconcile(changed: changes.record)
    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [.rfc(2119)])
    await indexer.reconcile(changed: changes.record)
    #expect(await changes.count == 1)
  }

  /// Counts the calls of a reconcile's `changed`.
  actor Changes {
    private(set) var count = 0
    func increment() { count += 1 }
    nonisolated func record() async { await increment() }
  }

  /// What `run()` listens for: every write and removal of a body.
  @Test func `the store says when its bodies change`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    var changes = store.bodiesChanged.makeAsyncIterator()

    try await storeBody(in: store)
    #expect(await changes.next() != nil)
    await store.remove(id)
    #expect(await changes.next() != nil)
  }

  @Test func `running indexes what the store holds and what it stores later`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    let running = Task { await indexer.run() }
    defer { running.cancel() }

    try await storeBody(in: store)
    while try await indexer.search("intermediaries").hits.isEmpty {
      await Task.yield()
    }
    await store.remove(id)
    while try await !indexer.search("intermediaries").hits.isEmpty {
      await Task.yield()
    }
  }

  // MARK: - Index All RFCs

  /// A stand-in for the run's download: RFC 8999's XML parsed, whichever document is
  /// asked for, counting each fetch.
  final class CountingFetch: Sendable {
    private let asked = Mutex<[DocumentID]>([])
    var fetched: [DocumentID] { asked.withLock { $0 } }

    func callAsFunction(_ id: DocumentID) throws -> RFCDocument {
      asked.withLock { $0.append(id) }
      return try Fixtures.rfc8999()
    }
  }

  @Test func `the whole-corpus run indexes what it downloads and keeps no body`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    let fetch = CountingFetch()

    let progress = await indexer.indexAll([id, .rfc(1)]) { try fetch($0) }

    #expect(progress == TextIndexer.CorpusProgress(indexed: 2, total: 2, failed: 0))
    #expect(await store.storedBodies().isEmpty)
    let found = try await indexer.search("intermediaries")
    #expect(Set(found.hits.map(\.document)) == [id, .rfc(1)])
    #expect(found.searched == 2)
  }

  /// Its documents have no body in the store, which a reconcile would otherwise read
  /// as a body removed.
  @Test func `what Index All RFCs indexed stays at reconcile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    let fetch = CountingFetch()
    _ = await indexer.indexAll([id]) { try fetch($0) }

    await indexer.reconcile()

    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [id])
  }

  /// A document indexed from its body is not downloaded again, and is not dropped
  /// when the body is evicted after.
  @Test func `the whole-corpus run keeps what is indexed, past its eviction`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()
    let fetch = CountingFetch()

    let progress = await indexer.indexAll([id]) { try fetch($0) }
    #expect(await store.evict(pinned: [], bound: 0) == [id])
    await indexer.reconcile()

    #expect(fetch.fetched.isEmpty)
    #expect(progress.indexed == 1)
    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [id])
  }

  @Test func `the whole-corpus run resumes where it stopped`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let first = CountingFetch()
    _ = await indexer.indexAll([id]) { try first($0) }
    let fetch = CountingFetch()
    let reported = Mutex<[TextIndexer.CorpusProgress]>([])

    _ = await indexer.indexAll([id, .rfc(1)]) {
      try fetch($0)
    } progress: { progress in
      reported.withLock { $0.append(progress) }
    }

    #expect(fetch.fetched == [.rfc(1)])
    #expect(
      reported.withLock { $0 } == [
        TextIndexer.CorpusProgress(indexed: 1, total: 2, failed: 0),
        TextIndexer.CorpusProgress(indexed: 2, total: 2, failed: 0),
      ])
  }

  /// One that cannot be downloaded or parsed is counted, and the next run tries it
  /// again.
  @Test func `a document Index All RFCs cannot fetch is counted, and the run goes on`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let id = self.id

    let progress = await indexer.indexAll([.rfc(1), id]) { asked in
      guard asked == id else { throw URLError(.badServerResponse) }
      return try Fixtures.rfc8999()
    }

    #expect(progress == TextIndexer.CorpusProgress(indexed: 1, total: 2, failed: 1))
    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [id])
  }

  /// Cancelled, the run keeps what it indexed, and counts nothing it left as failed.
  @Test func `a cancelled Index All RFCs keeps what it indexed`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let (indexing, indexed) = AsyncStream.makeStream(of: Int.self)
    let id = self.id

    let run = Task {
      await indexer.indexAll([id, .rfc(1), .rfc(2)]) { asked in
        if asked != id {
          try await Task.sleep(for: .seconds(120))
        }
        return try Fixtures.rfc8999()
      } progress: { progress in
        indexed.yield(progress.indexed)
      }
    }
    for await count in indexing where count == 1 { break }
    run.cancel()
    let progress = await run.value

    #expect(progress == TextIndexer.CorpusProgress(indexed: 1, total: 3, failed: 0))
    #expect(try await indexer.search("intermediaries").hits.map(\.document) == [id])
  }

  /// The reader shows a legacy RFC from the pack's XML, whose anchors a hit has to
  /// open, so the run reads the pack and does not download what it holds.
  @Test func `the whole-corpus run reads what the legacy pack holds from the pack`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    _ = try await store.installLegacyPack(from: DocumentStoreTests.legacyPack(in: sandbox.root))
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    let fetch = CountingFetch()

    let progress = await indexer.indexAll([.rfc(2119)]) { try fetch($0) }

    #expect(fetch.fetched.isEmpty)
    #expect(progress == TextIndexer.CorpusProgress(indexed: 1, total: 1, failed: 0))
    #expect(try await indexer.search("interoperation").hits.map(\.document) == [.rfc(2119)])
  }

  @Test func `releasing what the whole-corpus run indexed gives back its disk`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let fetch = CountingFetch()
    _ = await indexer.indexAll((1...40).map { DocumentID.rfc($0) }) { try fetch($0) }
    let before = await indexer.usage().usage.bytes

    await indexer.releaseRetained()

    let after = await indexer.usage()
    #expect(after.usage.documents == 0)
    #expect(after.retained == 0)
    #expect(after.usage.bytes < before / 2)
  }

  /// A run that only retains what is indexed already still changes what Settings
  /// shows: Remove Full-Text Index has something to remove.
  @Test func `retaining what is indexed already announces a change`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()
    let changes = Mutex(0)
    let fetch = CountingFetch()

    _ = await indexer.indexAll([id]) {
      try fetch($0)
    } changed: {
      changes.withLock { $0 += 1 }
    }

    #expect(changes.withLock { $0 } == 1)
    #expect(await indexer.usage().retained == 1)
  }

  /// What the confirmation says Index All RFCs downloads.
  @Test func `the RFCs not indexed yet are counted`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let fetch = CountingFetch()
    _ = await indexer.indexAll([id]) { try fetch($0) }

    #expect(await indexer.unindexed([id, .rfc(1), .rfc(2)]) == 2)
  }

  /// The same RFCs a narrowed search counts (`TextQuery.documents`), so a complete
  /// run searches everything a search could: one with no formats listed may have a
  /// text, and the download tries it.
  @Test func `only an RFC listed only as a PDF or a PostScript cannot be indexed`() {
    let date = PublicationDate(year: 1990)
    let rfcs = [
      RFCMetadata(id: .rfc(1), title: "Text", date: date, formats: [.text, .html]),
      RFCMetadata(id: .rfc(2), title: "XML", date: date, formats: [.xml]),
      RFCMetadata(id: .rfc(3), title: "Scanned", date: date, formats: [.pdf, .postScript]),
      RFCMetadata(id: .rfc(4), title: "Unlisted", date: date, formats: []),
    ]

    #expect(IndexAllRun.indexable(rfcs).map(\.id) == [.rfc(1), .rfc(2), .rfc(4)])
  }

  /// A body the reader stored during the run is indexed by the reconcile as it was
  /// written; the run does not index it again over that, as if it had no body.
  @Test func `the whole-corpus run leaves what a reconcile indexed meanwhile`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let url = indexURL(in: sandbox)
    let indexer = try TextIndexer(contentsOf: url, store: store)
    let fetch = CountingFetch()

    _ = await indexer.indexAll([id]) { asked in
      try await storeBody(in: store)
      await indexer.reconcile()
      return try fetch(asked)
    }

    let written = try FullTextIndex(contentsOf: url).indexed()[id]
    #expect(written == (await store.storedBodies())[id])
    #expect(await indexer.usage().retained == 1)
  }

  /// Remove Full-Text Index: the index goes back to the bodies the store holds.
  @Test func `releasing what Index All RFCs indexed keeps only the stored`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()
    let fetch = CountingFetch()
    _ = await indexer.indexAll([id, .rfc(1)]) { try fetch($0) }

    await indexer.releaseRetained()

    let found = try await indexer.search("intermediaries")
    #expect(found.hits.map(\.document) == [id])
    #expect(found.searched == 1)
  }

  @Test func `the usage counts what is indexed and what Index All RFCs retained`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: store)
    try await storeBody(in: store)
    await indexer.reconcile()
    let fetch = CountingFetch()
    _ = await indexer.indexAll([.rfc(1)]) { try fetch($0) }

    let usage = await indexer.usage()

    #expect(usage.usage.documents == 2)
    #expect(usage.retained == 1)
    #expect(usage.usage.bytes > 0)
  }

  @MainActor @Test func `a run reports what it ended with`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let run = IndexAllRun()
    let fetch = CountingFetch()

    run.start([id, .rfc(1)], indexer: indexer) { try fetch($0) }
    #expect(run.isRunning)
    await run.untilEnded()

    #expect(!run.isRunning)
    #expect(run.progress == TextIndexer.CorpusProgress(indexed: 2, total: 2, failed: 0))
  }

  /// Until the new run reports, the control shows it starting, not where the last
  /// one ended.
  @MainActor @Test func `a run started again does not show the last run's progress`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let run = IndexAllRun()
    let fetch = CountingFetch()
    run.start([id], indexer: indexer) { try fetch($0) }
    await run.untilEnded()

    run.start([id, .rfc(1)], indexer: indexer) { try fetch($0) }

    #expect(run.progress == nil)
    await run.untilEnded()
  }

  @MainActor @Test func `a stopped run ends with what it indexed`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let indexer = try TextIndexer(contentsOf: indexURL(in: sandbox), store: sandbox.store())
    let run = IndexAllRun()

    run.start([id], indexer: indexer) { _ in
      try await Task.sleep(for: .seconds(120))
      return try Fixtures.rfc8999()
    }
    run.stop()
    await run.untilEnded()

    #expect(!run.isRunning)
    #expect(run.progress == TextIndexer.CorpusProgress(indexed: 0, total: 1, failed: 0))
  }
}
