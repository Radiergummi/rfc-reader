import Foundation
import RFCKit
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

  @MainActor @Test func `a fetch a reader asked for joins the reconciler's`() async throws {
    let sandbox = Sandbox()
    defer { sandbox.remove() }
    let store = sandbox.store()
    let fetcher = GatedFetcher()
    let id = DocumentID.rfc(8999)
    let keeper = OfflineKeeper(store: store, client: fetcher) { _ in [.xml] }
    await keeper.reconcile(wanted: [id]).value
    await untilWaiting(documents: 1, for: id, in: store)

    let tapped = Task { try await keeper.fetchNow(id) }
    await fetcher.gate.open()
    try await tapped.value

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
}
