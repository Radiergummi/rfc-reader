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
  private actor Gate {
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
  private final class GatedFetcher: DocumentFetching {
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
  private struct Sandbox {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "DocumentStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    var directory: URL { root.appending(path: "Documents", directoryHint: .isDirectory) }

    func store() -> DocumentStore {
      DocumentStore(
        directory: directory, caches: root.appending(path: "Caches", directoryHint: .isDirectory))
    }

    /// Where the store keeps `id`'s body in `format`.
    func file(_ id: DocumentID, format: FileFormat) -> URL {
      directory.appending(path: DocumentCacheIndex.fileName(for: id, format: format))
    }

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  /// Until as many readers wait for `id`'s fetches as given: an open started is not
  /// yet an open that has joined one.
  private func untilWaiting(
    documents: Int = 0, texts: Int = 0, for id: DocumentID, in store: DocumentStore
  ) async {
    while true {
      let waiting = await store.waiters(id)
      if waiting.documents == documents, waiting.texts == texts { return }
      await Task.yield()
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
    #expect(await store.cachedNumbers().isEmpty)
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
    #expect(await store.cachedNumbers() == [8999])
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
}
