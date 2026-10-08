import Foundation
import RFCKit
import Synchronization
import Testing

@testable import RFCReaderKit

/// The document store's sequences (#596): a second open joins the first fetch, a
/// removal during a download shows the document and keeps nothing (#116), a body on
/// disk is parsed without a fetch, and a text-only document's load shares Original
/// Text's download (#324). Each test has directories of its own, and a fetcher
/// that waits until the test lets it finish, so a test can act while one is in
/// flight.
@Suite("Document store", .timeLimit(.minutes(1)))
struct DocumentStoreTests {
  /// Holds every fetch in flight until the test lets them finish.
  actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
      guard !isOpen else { return }
      await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
      isOpen = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters = []
    }
  }

  /// Serves the committed fixtures, read where they are: RFC 8999's XML as any
  /// preferred document, RFC 2119's text as any body's bytes. Each fetch counts
  /// itself, then waits at the gate.
  final class GatedFetcher: DocumentFetching {
    let gate = Gate()
    private let documentCount = Mutex(0)
    private let textCount = Mutex(0)

    var documentFetches: Int { documentCount.withLock { $0 } }
    var textFetches: Int { textCount.withLock { $0 } }

    @concurrent
    func fetchPreferredDocument(_ id: DocumentID, availableFormats: [FileFormat]?) async throws
      -> RFCEditorClient.FetchedDocument
    {
      documentCount.withLock { $0 += 1 }
      await gate.wait()
      let data = try Fixtures.data("rfc8999.xml")
      return RFCEditorClient.FetchedDocument(
        data: data, format: .xml, document: try RFCXMLParser.parse(data), xmlParseFailure: nil)
    }

    func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
      textCount.withLock { $0 += 1 }
      await gate.wait()
      return try Fixtures.data("rfc2119.txt")
    }
  }

  /// Directories of one test's own, for its store.
  struct Sandbox {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "DocumentStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    var directory: URL { root.appending(path: "Documents", directoryHint: .isDirectory) }
    var caches: URL { root.appending(path: "Caches", directoryHint: .isDirectory) }

    /// A store whose disk has `freeSpace` bytes left for each tier, or as much as
    /// the real volume has when that is nil, and which awaits `parsing` in each
    /// parse of a body on disk.
    func store(
      freeSpace: (@Sendable (StorageTier) -> Int?)? = nil,
      parsing: (@Sendable () async -> Void)? = nil
    ) -> DocumentStore {
      DocumentStore(directory: directory, caches: caches, freeSpace: freeSpace, parsing: parsing)
    }

    /// Where the store keeps `id`'s body in `format`, in `tier`.
    func file(_ id: DocumentID, format: FileFormat, in tier: StorageTier = .cache) -> URL {
      let folder =
        switch tier {
        case .kept: directory.appending(path: "Offline", directoryHint: .isDirectory)
        case .cache: caches.appending(path: "Documents", directoryHint: .isDirectory)
        }
      return folder.appending(path: DocumentCacheIndex.fileName(for: id, format: format))
    }

    func exists(_ id: DocumentID, format: FileFormat, in tier: StorageTier) -> Bool {
      FileManager.default.fileExists(atPath: file(id, format: format, in: tier).path)
    }

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  @Test func `two opens of a document not on disk make one fetch and both get it`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)

    let first = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 1, for: id, in: store)
    let second = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 2, for: id, in: store)
    await fetcher.gate.open()

    let expected = try Fixtures.rfc8999()
    #expect(try await first.value == expected)
    #expect(try await second.value == expected)
    #expect(fetcher.documentFetches == 1)
  }

  /// The reader who opened it gets the document; the disk does not, and nor does
  /// the store's memory, so the next open fetches it again.
  @Test func `a removal during the fetch shows the document and keeps nothing`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)

    let opening = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 1, for: id, in: store)
    await store.remove(id)
    await fetcher.gate.open()

    #expect(try await opening.value == Fixtures.rfc8999())
    #expect(await !store.isCached(id))
    #expect(!FileManager.default.fileExists(atPath: sandbox.file(id, format: .xml).path))

    _ = try await store.document(id, formats: [.xml], client: fetcher)
    #expect(fetcher.documentFetches == 2)
  }

  @Test func `an XML body on disk is parsed without a fetch`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try Fixtures.data("rfc8999.xml").write(to: sandbox.file(id, format: .xml))

    let document = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(try document == Fixtures.rfc8999())
    #expect(fetcher.documentFetches == 0)
    #expect(fetcher.textFetches == 0)
  }

  @Test func `a text body on disk is parsed without a fetch`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(2119)
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(id, format: .text))

    let document = try await store.document(id, formats: [.text], client: fetcher)

    #expect(try document == Fixtures.rfc2119())
    #expect(fetcher.documentFetches == 0)
    #expect(fetcher.textFetches == 0)
  }

  @Test func `a fetched document is written and reported as cached`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)

    let document = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(try document == Fixtures.rfc8999())
    #expect(await store.isCached(id))
    #expect(try Data(contentsOf: sandbox.file(id, format: .xml)) == Fixtures.data("rfc8999.xml"))
  }

  /// Where the text is the document, its load and Original Text share one download,
  /// which is written once and parsed by the load (#324).
  @Test func `a text-only document's load shares Original Text's download`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(2119)

    let opening = Task { try await store.document(id, formats: [.text], client: fetcher) }
    await untilWaiting(texts: 1, for: id, in: store)
    let reading = Task { try await store.originalText(id, client: fetcher) }
    await untilWaiting(texts: 2, for: id, in: store)
    await fetcher.gate.open()

    let text = try LegacyTextParser.text(decoding: Fixtures.data("rfc2119.txt"))
    #expect(try await opening.value == Fixtures.rfc2119())
    #expect(try await reading.value == LegacyTextParser.stripPagination(text))
    #expect(fetcher.textFetches == 1)
    #expect(fetcher.documentFetches == 0)
    #expect(await store.isCached(id))
  }

  /// Kept in Application Support, where the next launch's comparison reads it (#191).
  @Test func `a bookmark baseline is read back as it was stored`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let index = RFCIndex(rfcs: [
      RFCMetadata(
        id: .rfc(8999), title: "An Example", date: PublicationDate(year: 2021),
        obsoletedBy: [.rfc(9999)])
    ])
    let baseline = BookmarkBaseline(
      bookmarks: [.rfc(8999)], index: index, revisions: nil, carryingOver: nil)

    #expect(await store.bookmarkBaseline() == nil)
    try await store.storeBookmarkBaseline(baseline)
    #expect(await store.bookmarkBaseline() == baseline)
  }

  // MARK: - Two tiers (#358)

  @Test func `a read document is written to the cache tier, not the kept one`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)

    _ = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(sandbox.exists(id, format: .xml, in: .cache))
    #expect(!sandbox.exists(id, format: .xml, in: .kept))
    #expect(await !store.isKept(id))
    #expect(await store.offlineState().kept.isEmpty)
  }

  /// Marking a document already read moves its body across and fetches nothing.
  @Test func `keeping a cached document moves its body without a fetch`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    _ = try await store.document(id, formats: [.xml], client: fetcher)

    try await store.keep(id, formats: [.xml], client: fetcher)

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
    #expect(await store.isKept(id))
    #expect(await store.isCached(id))
    #expect(await store.offlineState().kept == [id])
  }

  @Test func `keeping a document on neither tier fetches it into the kept tier`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)

    try await store.keep(id, formats: [.xml], client: fetcher)

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
    #expect(await store.isKept(id))
  }

  /// Unmarking does not delete: the body goes back to the cache, where eviction
  /// treats it as any other.
  @Test func `releasing a kept document moves its body back into the cache`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)

    await store.release(id)

    #expect(!sandbox.exists(id, format: .xml, in: .kept))
    #expect(sandbox.exists(id, format: .xml, in: .cache))
    #expect(await !store.isKept(id))
    #expect(await store.isCached(id))
  }

  @Test func `a kept body is parsed without a fetch`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    let kept = sandbox.file(id, format: .xml, in: .kept)
    try FileManager.default.createDirectory(
      at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Fixtures.data("rfc8999.xml").write(to: kept)

    let document = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(try document == Fixtures.rfc8999())
    #expect(fetcher.documentFetches == 0)
    #expect(await store.isKept(id))
  }

  /// A kept document's Original Text is part of what is kept, so it is not evicted
  /// from under the document.
  @Test func `a kept document's text is written to the kept tier`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)

    _ = try await store.originalText(id, client: fetcher)

    #expect(sandbox.exists(id, format: .text, in: .kept))
    #expect(!sandbox.exists(id, format: .text, in: .cache))
  }

  @Test func `eviction never removes a kept body`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let kept = DocumentID.rfc(8999)
    let read = DocumentID.rfc(9000)
    try await store.keep(kept, formats: [.xml], client: fetcher)
    _ = try await store.document(read, formats: [.xml], client: fetcher)

    let evicted = await store.evict(pinned: [], bound: 0)

    #expect(evicted == [read])
    #expect(sandbox.exists(kept, format: .xml, in: .kept))
    #expect(await store.isKept(kept))
    #expect(await !store.isCached(read))
  }

  /// A wanted body in the cache is there only until the reconciler moves it.
  @Test func `eviction never removes a wanted body from the cache`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    _ = try await store.document(id, formats: [.xml], client: fetcher)
    await store.setWanted([id])

    let evicted = await store.evict(pinned: [], bound: 0)

    #expect(evicted.isEmpty)
    #expect(sandbox.exists(id, format: .xml, in: .cache))
  }

  /// The kept tier can be downloaded again, so it stays out of backups.
  @Test func `the kept tier is excluded from backups`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)

    let folder = sandbox.file(id, format: .xml, in: .kept).deletingLastPathComponent()
    let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  /// A keep made while the document is being opened joins that fetch, and
  /// whichever of the two writes the body puts it in the kept tier: the reader that
  /// writes is the first to finish, on the store's actor, so the other finds the
  /// body there.
  @Test func `keeping a document while it is opened keeps it`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)

    let opening = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 1, for: id, in: store)
    let keeping = Task { try await store.keep(id, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 2, for: id, in: store)
    await fetcher.gate.open()

    _ = try await opening.value
    try await keeping.value
    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
  }

  /// A disk too full for the cache's reserve still shows the document; it is only
  /// not written, so it is fetched again next time.
  @Test func `a read document is not cached when the disk is low`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store(freeSpace: { _ in 0 })
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)

    let document = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(try document == Fixtures.rfc8999())
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
    #expect(await !store.isCached(id))
  }

  /// Keeping is a promise the user asked for, so one that does not fit says so.
  @Test func `keeping a document the disk has no room for fails`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store(freeSpace: { _ in 0 })
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)

    await #expect(throws: DocumentStore.NotEnoughSpace.self) {
      try await store.keep(id, formats: [.xml], client: fetcher)
    }
    #expect(await !store.isKept(id))
  }

  /// A keep that failed promised nothing, so reading the document later caches it
  /// like any other.
  @Test func `a document whose keep failed is cached when read`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let roomy = Mutex(false)
    let store = sandbox.store(freeSpace: { _ in roomy.withLock { $0 } ? nil : 0 })
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    await #expect(throws: DocumentStore.NotEnoughSpace.self) {
      try await store.keep(id, formats: [.xml], client: fetcher)
    }
    roomy.withLock { $0 = true }

    _ = try await store.originalText(id, client: fetcher)

    #expect(sandbox.exists(id, format: .text, in: .cache))
    #expect(await !store.isKept(id))
  }

  /// The system purges Caches, the cache's own folder included, while the app runs.
  @Test func `a read document is cached after the cache folder was purged`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try FileManager.default.removeItem(at: sandbox.caches)

    _ = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(sandbox.exists(id, format: .xml, in: .cache))
  }

  // MARK: - Keeping what is wanted offline (#358)

  /// A document marked but not fetched yet, opened by a reader, is written where it
  /// belongs, rather than into the cache for the reconciler to move.
  @Test func `a document wanted offline is written to the kept tier when read`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    await store.setWanted([id])

    _ = try await store.document(id, formats: [.xml], client: fetcher)

    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
  }

  @Test func `the offline state names each tier's documents and the downloads running`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let cached = DocumentID.rfc(2119)
    let kept = DocumentID.rfc(8999)
    let fetching = DocumentID.rfc(9110)
    let opening = Task { try await store.document(fetching, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 1, for: fetching, in: store)
    let reading = Task { try await store.originalText(cached, client: fetcher) }
    await untilWaiting(texts: 1, for: cached, in: store)
    let state = await store.offlineState()
    #expect(state.running == [fetching, cached])
    await fetcher.gate.open()
    _ = try await opening.value
    _ = try await reading.value
    try await store.keep(kept, formats: [.xml], client: fetcher)
    await store.remove(fetching)

    let settled = await store.offlineState()

    #expect(settled.kept == [kept])
    #expect(settled.cached == [cached])
    #expect(settled.running.isEmpty)
  }

  /// A keep with nothing left to do does not fail on a move it did not need: here a
  /// cached copy that cannot leave its folder.
  @Test func `keeping a kept document does not move its cached copy`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)
    let cacheFolder = sandbox.file(id, format: .xml).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: sandbox.file(id, format: .xml, in: .kept), to: sandbox.file(id, format: .xml))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: cacheFolder.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: cacheFolder.path)
    }

    try await store.keep(id, formats: [.xml], client: fetcher)

    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(fetcher.documentFetches == 1)
  }

  /// A move that fails leaves the body already at its destination: here a cached
  /// copy that cannot leave its folder, moved onto a kept one.
  @Test func `a failed move keeps the body at its destination`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)
    let cacheFolder = sandbox.file(id, format: .xml).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: sandbox.file(id, format: .xml, in: .kept), to: sandbox.file(id, format: .xml))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: cacheFolder.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: cacheFolder.path)
    }

    await #expect(throws: (any Error).self) { try await store.keepCached(id) }

    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(await store.isKept(id))
  }

  /// A move only: a cached body gone by the time it runs is not fetched.
  @Test func `keeping a cached body fetches nothing when there is none`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let id = DocumentID.rfc(8999)

    try await store.keepCached(id)

    #expect(await !store.isCached(id))
  }

  // MARK: - Overlapping a fetch or a parse (#614)

  /// Eviction runs while a document is being fetched: it bounds the cache by what is
  /// on disk, which the document being fetched is not yet, and the fetch writes its
  /// body once it lands.
  @Test func `eviction during a fetch evicts what is on disk and the fetch still writes`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let older = DocumentID.rfc(2119)
    let fetched = DocumentID.rfc(8999)
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(older, format: .text))
    _ = try await store.document(older, formats: [.text], client: fetcher)

    let opening = Task { try await store.document(fetched, formats: [.xml], client: fetcher) }
    await untilWaiting(documents: 1, for: fetched, in: store)
    let evicted = await store.evict(pinned: [], bound: 0)
    await fetcher.gate.open()

    #expect(evicted == [older])
    #expect(try await opening.value == Fixtures.rfc8999())
    #expect(await store.isCached(fetched))
    #expect(await !store.isCached(older))
  }

  /// A second open of a body on disk joins the parse the first started, rather than
  /// parsing it again, and both get the document.
  @Test func `a second open joins the parse of a cached body`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let gate = Gate()
    let parses = Mutex(0)
    let store = sandbox.store(
      parsing: {
        parses.withLock { $0 += 1 }
        await gate.wait()
      })
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    try Fixtures.data("rfc8999.xml").write(to: sandbox.file(id, format: .xml))

    let first = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(parses: 1, for: id, in: store)
    let second = Task { try await store.document(id, formats: [.xml], client: fetcher) }
    await untilWaiting(parses: 2, for: id, in: store)
    await gate.open()

    let expected = try Fixtures.rfc8999()
    #expect(try await first.value == expected)
    #expect(try await second.value == expected)
    #expect(parses.withLock { $0 } == 1)
    #expect(fetcher.documentFetches == 0)
  }

  /// A legacy document is downloading as text when the legacy XML pack is
  /// installed: once the text is on disk, the open reads the document from the pack,
  /// which is the one XML path the pack exists for. The pack is made here from the
  /// committed text fixture, converted as corpus-build converts it.
  @Test func `a pack installed while a document downloads serves it from the pack`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(2119)
    let pack = try Self.legacyPack(holding: id, in: sandbox.root)

    let opening = Task { try await store.document(id, formats: [.text], client: fetcher) }
    await untilWaiting(texts: 1, for: id, in: store)
    _ = try await store.installLegacyPack(from: pack)
    await fetcher.gate.open()

    #expect(try await opening.value.source == .xml)
    #expect(fetcher.textFetches == 1)
    #expect(sandbox.exists(id, format: .text, in: .cache))
  }

  /// A cached legacy text is being parsed when the pack is installed: that open
  /// shows the text's document, and the next reads the pack's, rather than the
  /// parse the pack replaced being kept in memory for every open after.
  @Test func `a pack installed while a cached body parses serves the next open`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let gate = Gate()
    let store = sandbox.store(parsing: { await gate.wait() })
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(2119)
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(id, format: .text))
    let pack = try Self.legacyPack(holding: id, in: sandbox.root)

    let opening = Task { try await store.document(id, formats: [.text], client: fetcher) }
    await untilWaiting(parses: 1, for: id, in: store)
    _ = try await store.installLegacyPack(from: pack)
    await gate.open()

    #expect(try await opening.value.source == .text)
    #expect(try await store.document(id, formats: [.text], client: fetcher).source == .xml)
  }

  /// As above, with a second open joining the held parse after the install: neither
  /// open keeps the parse the pack replaced, whichever of them finishes first.
  @Test func `an open joining a parse a pack replaced does not keep it`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let gate = Gate()
    let store = sandbox.store(parsing: { await gate.wait() })
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(2119)
    try Fixtures.data("rfc2119.txt").write(to: sandbox.file(id, format: .text))
    let pack = try Self.legacyPack(holding: id, in: sandbox.root)

    let first = Task { try await store.document(id, formats: [.text], client: fetcher) }
    await untilWaiting(parses: 1, for: id, in: store)
    _ = try await store.installLegacyPack(from: pack)
    let second = Task { try await store.document(id, formats: [.text], client: fetcher) }
    await untilWaiting(parses: 2, for: id, in: store)
    await gate.open()

    #expect(try await first.value.source == .text)
    #expect(try await second.value.source == .text)
    #expect(try await store.document(id, formats: [.text], client: fetcher).source == .xml)
  }

  /// A legacy XML pack holding `id`, converted from the committed RFC 2119 text the
  /// way corpus-build converts it, with a manifest listing it.
  private static func legacyPack(holding id: DocumentID, in parent: URL) throws -> URL {
    let converted = RFCXMLSerializer().serialize(
      LegacyTextParser.parse(try Fixtures.data("rfc2119.txt")))
    return try DataPackTests.makePack(
      in: parent, files: [DocumentCacheIndex.fileName(for: id, format: .xml): converted])
  }
}

/// Until as many readers wait for `id`'s fetches and parse as given: an open
/// started is not yet an open that has joined one.
func untilWaiting(
  documents: Int = 0, texts: Int = 0, parses: Int = 0, for id: DocumentID,
  in store: DocumentStore
) async {
  let expected = DocumentStore.Waiters(documents: documents, texts: texts, parses: parses)
  while true {
    if await store.waiters(id) == expected { return }
    await Task.yield()
  }
}
