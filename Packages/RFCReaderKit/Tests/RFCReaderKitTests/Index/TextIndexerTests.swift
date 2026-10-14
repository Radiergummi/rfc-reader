import Foundation
import RFCKit
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
}
