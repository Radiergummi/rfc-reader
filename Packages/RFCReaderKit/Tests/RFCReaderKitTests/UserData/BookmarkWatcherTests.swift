import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// The bookmark comparison and the background refresh that drives it (#191, #595):
/// the refresh returns whatever comes of the index (#758), fetches due revisions on
/// any network, and waits for the comparison, which keeps the baseline.
@Suite("Bookmark watcher", .hangGuard)
@MainActor
struct BookmarkWatcherTests {
  private let sandbox = DocumentStoreTests.Sandbox()

  nonisolated private static let revisions = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 1_000), revisions: [:])
  nonisolated private static let newerRevisions = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 2_000), revisions: [:])

  /// How `Transport` answers the index.
  private enum IndexAnswer {
    /// The committed sample.
    case sample
    /// A `304`.
    case unchanged
    /// No network.
    case failing
    /// Held until canceled, as a session waiting for a cheap network holds it, saying
    /// so on `Transport.held`; given up on after half a minute, so one never canceled
    /// fails the test rather than hanging it.
    case held
  }

  /// Answers the index as `index` says, and `revisions.json` with `revisions`;
  /// everything else with a `404`. Counts the requests for each file.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let index: IndexAnswer
    private let revisions: RFCRevisions
    private let lock = NSLock()
    private var sent: [String] = []
    private let heldRequests = AsyncStream<Void>.makeStream()
    /// Yields when an index request is being held.
    var held: AsyncStream<Void> { heldRequests.stream }

    init(index: IndexAnswer = .sample, revisions: RFCRevisions = BookmarkWatcherTests.revisions) {
      self.index = index
      self.revisions = revisions
    }

    func requests(for file: String) -> Int {
      lock.withLock { sent.count(where: { $0 == file }) }
    }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let file = request.url!.lastPathComponent
      lock.withLock { sent.append(file) }
      let status: Int
      let body: Data
      switch (file, index) {
      case ("rfc-index.xml", .sample):
        (status, body) = (200, try Fixtures.rfcKitData("rfc-index-sample.xml"))
      case ("rfc-index.xml", .unchanged):
        (status, body) = (304, Data())
      case ("rfc-index.xml", .failing):
        throw URLError(.notConnectedToInternet)
      case ("rfc-index.xml", .held):
        heldRequests.continuation.yield()
        try await Task.sleep(for: .seconds(30))
        throw URLError(.timedOut)
      case ("revisions.json", _):
        (status, body) = (200, try revisions.encoded())
      default:
        (status, body) = (404, Data())
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: [
          "Content-Type": file.hasSuffix(".xml") ? "application/xml" : "application/json"
        ])!
      return (body, response)
    }
  }

  /// How many comparisons changed the baseline and handed its notices, none or some,
  /// to `post`.
  private final class Posts {
    var count = 0
  }

  /// The parts the watcher reads, wired as `LibraryModel` wires them, over an
  /// in-memory store holding a bookmark of RFC 2119.
  private struct Parts {
    let posts: Posts
    let indexes: IndexRepository
    let dataFiles: DataFileRefresher
    let watcher: BookmarkWatcher
    /// A context does not keep its container alive.
    let container: ModelContainer
  }

  private func parts(
    any: Transport, cheap: Transport, now: @escaping () -> Date = { .now },
    isStoredInMemory: Bool = false
  ) throws -> Parts {
    let store = sandbox.store()
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    try BookmarkStore.toggle(.rfc(2119), title: "RFC 2119", in: container.mainContext)
    let indexes = IndexRepository(
      store: store, client: RFCEditorClient(transport: any),
      clientOnCheapNetworks: RFCEditorClient(transport: cheap), textIndexLocation: nil,
      now: now)
    let dataFiles = DataFileRefresher(
      store: store, client: RFCEditorClient(transport: any),
      clientOnCheapNetworks: RFCEditorClient(transport: cheap), now: now)
    let posts = Posts()
    let watcher = BookmarkWatcher(
      store: store, container: container, indexes: indexes, dataFiles: dataFiles,
      isStoredInMemory: isStoredInMemory, bootstrap: { await indexes.bootstrap() },
      post: { _ in posts.count += 1 })
    indexes.onApplied = { _ in watcher.compare() }
    dataFiles.onRevisionsChanged = { watcher.compare() }
    return Parts(
      posts: posts, indexes: indexes, dataFiles: dataFiles, watcher: watcher, container: container)
  }

  /// A `304` to a request that sent no validators settles the index as failed: the
  /// refresh goes on rather than waiting for an index that never comes (#758), and
  /// asks for the index again (#1073).
  @Test func `the refresh after a 304 with nothing kept asks for the index again`()
    async throws
  {
    defer { sandbox.remove() }
    let any = Transport(index: .unchanged)
    let cheap = Transport()
    let parts = try parts(any: any, cheap: cheap)
    await parts.indexes.bootstrap()
    try #require(parts.indexes.indexState.isFailed)
    // Required: a refresh waiting on an index that never settles would outlast the
    // time limit, which cannot end the wait.
    try #require(parts.indexes.hasSettled)

    await parts.watcher.refresh()

    #expect(parts.dataFiles.revisions == Self.revisions)
    #expect(any.requests(for: "revisions.json") == 1)
    #expect(cheap.requests(for: "rfc-index.xml") == 1)
    #expect(parts.indexes.indexState.isReady)
  }

  /// A background refresh on a phone network would otherwise post nothing about a
  /// revised bookmark (#758, answer 1).
  @Test func `the refresh fetches due revisions on an expensive network`() async throws {
    defer { sandbox.remove() }
    try await sandbox.store().storeRevisions(Self.revisions.encoded())
    let any = Transport(revisions: Self.newerRevisions)
    let cheap = Transport()
    let nextDay = Date.now.addingTimeInterval(IndexCheck.interval + 60)
    let parts = try parts(any: any, cheap: cheap, now: { nextDay })
    await parts.indexes.bootstrap()
    try #require(parts.indexes.hasSettled)

    await parts.watcher.refresh()

    #expect(parts.dataFiles.revisions == Self.newerRevisions)
    #expect(any.requests(for: "revisions.json") == 1)
    #expect(cheap.requests(for: "revisions.json") == 0)
  }

  /// The system may suspend the app once the refresh returns, so the comparisons
  /// before then, the index's at launch and the revisions', have each kept their
  /// baseline and handed it to `post`: the first baseline, then the one with the
  /// revisions in it.
  @Test func `the refresh waits for the comparison, which keeps the baseline`() async throws {
    defer { sandbox.remove() }
    let parts = try parts(any: Transport(), cheap: Transport())
    await parts.indexes.bootstrap()
    try #require(parts.indexes.hasSettled)

    await parts.watcher.refresh()

    // Read before anything else is awaited, which would let a comparison left running
    // finish.
    #expect(parts.posts.count == 2)
    let baseline = try #require(await sandbox.store().bookmarkBaseline())
    #expect(baseline.index?[.rfc(2119)] != nil)
    #expect(baseline.revisions != nil)
  }

  /// Canceled, as iOS cancels it when the background task expires, the refresh
  /// cancels the index check it is waiting for, which may wait for a cheap network
  /// for as long as there is none (#314), and returns. The revisions fetched before
  /// are kept, and the failure shown is left as it was.
  @Test func `a canceled refresh cancels the index check and returns`() async throws {
    defer { sandbox.remove() }
    let cheap = Transport(index: .held)
    let parts = try parts(any: Transport(index: .failing), cheap: cheap)
    await parts.indexes.bootstrap()
    // A failed index is checked at every refresh.
    try #require(parts.indexes.indexState.isFailed)

    let refreshing = Task { await parts.watcher.refresh() }
    var held = cheap.held.makeAsyncIterator()
    await held.next()
    let canceled = ContinuousClock.now
    refreshing.cancel()
    await refreshing.value

    // Well short of the half minute a check left running is held for.
    #expect(ContinuousClock.now - canceled < .seconds(10))
    #expect(parts.indexes.indexState.isFailed)
    #expect(parts.dataFiles.revisions == Self.revisions)
  }

  /// A store that fell back to memory reads as no bookmarks: a baseline of none would
  /// start every one afresh at the next launch that opens the real store (#152).
  @Test func `a store kept in memory keeps no baseline`() async throws {
    defer { sandbox.remove() }
    let parts = try parts(any: Transport(), cheap: Transport(), isStoredInMemory: true)
    await parts.indexes.bootstrap()
    try #require(parts.indexes.hasSettled)

    await parts.watcher.refresh()

    #expect(await sandbox.store().bookmarkBaseline() == nil)
  }
}
