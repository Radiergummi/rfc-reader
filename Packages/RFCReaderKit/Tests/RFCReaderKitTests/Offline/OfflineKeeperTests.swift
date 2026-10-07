import Foundation
import RFCKit
import Synchronization
import Testing

@testable import RFCReaderKit

/// The keeper carrying out the reconciler's plan against the document store's own
/// sequences (#358): moves without a fetch, fetches into the kept tier, and #116's
/// rule for a fetch no longer wanted. Built on the store's tests' sandbox and gated
/// fetcher.
@Suite("Offline keeper", .timeLimit(.minutes(1)))
struct OfflineKeeperTests {
  private typealias Sandbox = DocumentStoreTests.Sandbox
  private typealias GatedFetcher = DocumentStoreTests.GatedFetcher

  @MainActor @Test func `marking a cached document moves it without a fetch`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    _ = try await store.document(id, formats: [.xml], client: fetcher)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
  }

  @MainActor @Test func `marking a document on neither tier fetches it into the kept tier`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  @MainActor @Test func `unmarking a kept document moves it back into the cache`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: []).value

    #expect(!sandbox.exists(id, format: .xml, in: .kept))
    #expect(sandbox.exists(id, format: .xml, in: .cache))
  }

  /// #116's case: the fetch nobody waits for any more is canceled, and nothing is
  /// written.
  @MainActor @Test func `a mark removed while its fetch runs keeps nothing`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    await keeper.reconcile(wanted: [id]).value
    await untilWaiting(documents: 1, for: id, in: store)

    await keeper.reconcile(wanted: []).value
    await untilWaiting(documents: 0, for: id, in: store)
    await fetcher.gate.open()
    await keeper.untilSettled(id)

    #expect(await !store.isCached(id))
  }

  /// A tapped Keep Offline is the keeper's own fetch, so unmarking leaves it as it
  /// leaves any other.
  @MainActor @Test func `unmarking during a fetch a reader asked for keeps nothing`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    let tapped = Task { try await keeper.fetchNow(id) }
    await untilWaiting(documents: 1, for: id, in: store)

    await keeper.reconcile(wanted: []).value
    await fetcher.gate.open()

    await #expect(throws: CancellationError.self) { try await tapped.value }
    #expect(await !store.isCached(id))
  }

  @MainActor @Test func `a second fetch a reader asks for joins the first`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    let first = Task { try await keeper.fetchNow(id) }
    await untilWaiting(documents: 1, for: id, in: store)

    let second = Task { try await keeper.fetchNow(id) }
    await fetcher.gate.open()
    try await first.value
    try await second.value

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  /// The reconciler's plan promises a document in both tiers ends with one.
  @MainActor @Test func `a wanted body in both tiers loses its cached copy`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    try await store.keep(id, formats: [.xml], client: fetcher)
    try FileManager.default.createDirectory(
      at: sandbox.file(id, format: .xml).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: sandbox.file(id, format: .xml, in: .kept), to: sandbox.file(id, format: .xml))
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value

    #expect(sandbox.exists(id, format: .xml, in: .kept))
    #expect(!sandbox.exists(id, format: .xml, in: .cache))
  }

  @MainActor @Test func `reconciling again while a fetch runs starts no second one`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    await keeper.reconcile(wanted: [id]).value
    await untilWaiting(documents: 1, for: id, in: store)

    await keeper.reconcile(wanted: [id]).value
    #expect(await store.waiters(id).documents == 1)
    await fetcher.gate.open()
    await keeper.untilSettled(id)

    #expect(fetcher.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  /// The plan leaves a cached body alone while a download may still write it; the
  /// keeper moves it once that download has ended, with nothing else to start it.
  @MainActor @Test func `a body left to a running download is moved once it ends`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    try FileManager.default.createDirectory(
      at: sandbox.file(id, format: .xml).deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Fixtures.data("rfc8999.xml").write(to: sandbox.file(id, format: .xml))
    let reading = Task { try await store.originalText(id, client: fetcher) }
    await untilWaiting(texts: 1, for: id, in: store)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    #expect(sandbox.exists(id, format: .xml, in: .cache))
    await fetcher.gate.open()
    _ = try await reading.value
    // Nothing to await: the keeper runs again on its own. The suite's time limit
    // cancels the wait when it never does.
    while !sandbox.exists(id, format: .xml, in: .kept) {
      try Task.checkCancellation()
      await Task.yield()
    }

    #expect(!sandbox.exists(id, format: .xml, in: .cache))
    #expect(fetcher.documentFetches == 0)
  }

  // MARK: - The network

  /// A path the policy does not allow starts nothing, and the status says what the
  /// documents wait for.
  @MainActor @Test func `a deferred path fetches nothing and says why`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    await fetcher.gate.open()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id], policy: .deferred(.waitingForWiFi)).value
    await keeper.untilSettled(id)

    #expect(fetcher.documentFetches == 0)
    #expect(keeper.status.state(of: id) == .waiting(.waitingForWiFi))
  }

  /// A fetch nobody waits for goes through the session that never uses an
  /// expensive or constrained path; one somebody waits for, through the other.
  @MainActor @Test func `only a fetch nobody waits for uses the client for cheap networks`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let anyNetwork = GatedFetcher()
    let cheapNetworks = GatedFetcher()
    await anyNetwork.gate.open()
    await cheapNetworks.gate.open()
    let synced = DocumentID.rfc(8999)
    let tapped = DocumentID.rfc(9000)
    let keeper = OfflineKeeper(
      store: store, client: anyNetwork, clientFailingOnExpensiveNetworks: cheapNetworks
    ) { _ in [.xml] }

    await keeper.reconcile(wanted: [synced]).value
    await keeper.untilSettled(synced)
    try await keeper.fetchNow(tapped)

    #expect(cheapNetworks.documentFetches == 1)
    #expect(anyNetwork.documentFetches == 1)
  }

  /// Keep Offline tapped on cellular: the run its mark starts finds a path that
  /// allows no fetch nobody waits for, and leaves the tapped one running.
  @MainActor @Test func `a deferred path leaves running a fetch somebody waits for`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    let tapped = Task { try await keeper.fetchNow(id) }
    await untilWaiting(documents: 1, for: id, in: store)

    await keeper.reconcile(wanted: [id], policy: .deferred(.waitingForWiFi)).value
    #expect(await store.waiters(id).documents == 1)
    await fetcher.gate.open()
    try await tapped.value

    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  /// Download Now on a document the keeper is fetching on cheap networks only: that
  /// fetch is left, and one that takes any path starts.
  @MainActor @Test func `fetching now replaces a fetch nobody waits for`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let anyNetwork = GatedFetcher()
    let cheapNetworks = GatedFetcher()
    await anyNetwork.gate.open()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(
      store: store, client: anyNetwork, clientFailingOnExpensiveNetworks: cheapNetworks
    ) { _ in [.xml] }
    await keeper.reconcile(wanted: [id]).value
    await untilWaiting(documents: 1, for: id, in: store)

    try await keeper.fetchNow(id)
    await cheapNetworks.gate.open()

    #expect(anyNetwork.documentFetches == 1)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  @MainActor @Test func `a kept document says nothing once its fetch has written it`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    await untilWaiting(documents: 1, for: id, in: store)
    #expect(keeper.status.state(of: id) == .downloading)
    await fetcher.gate.open()
    await keeper.untilSettled(id)

    #expect(keeper.status.kept == [id])
    #expect(keeper.status.state(of: id) == nil)
  }

  /// A failed fetch is not started again by the next run, whatever starts it: its
  /// row offers Retry, which fetches on any path.
  @MainActor @Test func `a failed fetch waits for Retry`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = FailingFetcher(failures: 1)
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)
    #expect(keeper.status.state(of: id) == .failed)
    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)
    #expect(fetcher.fetches == 1)

    try await keeper.fetchNow(id)

    #expect(fetcher.fetches == 2)
    #expect(keeper.status.state(of: id) == nil)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  /// Download Now refused by the path, as when it joins a download running on the
  /// session for cheap networks: somebody is waiting, so the row offers Retry rather
  /// than falling silent until a path change that may never come.
  @MainActor @Test func `a fetch somebody waits for that the path refuses is failed`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = FailingFetcher(failures: 1, error: Self.pathRefused)
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await #expect(throws: URLError.self) { try await keeper.fetchNow(id) }

    #expect(keeper.status.state(of: id) == .failed)
  }

  /// A discretionary fetch the path refuses is not failed: the run the path change
  /// starts says it waits.
  @MainActor @Test func `a fetch nobody waits for that the path refuses is not failed`()
    async throws
  {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = FailingFetcher(failures: 1, error: Self.pathRefused)
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }

    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)

    #expect(keeper.status.state(of: id) == nil)
  }

  /// What a session that may not use an expensive path throws when the device moves
  /// to one.
  private static let pathRefused = URLError(
    .notConnectedToInternet,
    userInfo: [
      NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.expensive.rawValue
    ])

  /// A new path is a reason to try a failed fetch again: the failure may have been
  /// the old one's.
  @MainActor @Test func `forgetting the failures lets the next run fetch again`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = FailingFetcher(failures: 1)
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    await keeper.reconcile(wanted: [id]).value
    await keeper.untilSettled(id)

    await keeper.reconcile(wanted: [id], forgettingFailures: true).value
    await keeper.untilSettled(id)

    #expect(fetcher.fetches == 2)
    #expect(sandbox.exists(id, format: .xml, in: .kept))
  }

  /// Fails its first `failures` fetches with `error`, a server's by default, then serves RFC
  /// 8999's XML, at once.
  private final class FailingFetcher: DocumentFetching {
    private let state: Mutex<(fetches: Int, failuresLeft: Int)>
    private let error: URLError

    init(failures: Int, error: URLError = URLError(.badServerResponse)) {
      state = Mutex((0, failures))
      self.error = error
    }

    var fetches: Int { state.withLock { $0.fetches } }

    @concurrent
    func fetchPreferredDocument(_ id: DocumentID, availableFormats: [FileFormat]?) async throws
      -> RFCEditorClient.FetchedDocument
    {
      let fails = state.withLock { state in
        state.fetches += 1
        defer { state.failuresLeft = max(0, state.failuresLeft - 1) }
        return state.failuresLeft > 0
      }
      if fails { throw error }
      let data = try Fixtures.data("rfc8999.xml")
      return RFCEditorClient.FetchedDocument(
        data: data, format: .xml, document: try RFCXMLParser.parse(data), xmlParseFailure: nil)
    }

    func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
      throw URLError(.badServerResponse)
    }
  }
}
