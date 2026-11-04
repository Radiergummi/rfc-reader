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

  /// Answers the index with the committed sample, or with a `304` when
  /// `answersUnchanged`, and `revisions.json` with `revisions`; everything else with a
  /// `404`. Counts the requests for each file.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let answersUnchanged: Bool
    private let revisions: RFCRevisions
    private let lock = NSLock()
    private var sent: [String] = []

    init(
      answersUnchanged: Bool = false,
      revisions: RFCRevisions = BookmarkWatcherTests.revisions
    ) {
      self.answersUnchanged = answersUnchanged
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
      switch file {
      case "rfc-index.xml" where answersUnchanged:
        (status, body) = (304, Data())
      case "rfc-index.xml":
        (status, body) = (200, try Fixtures.rfcKitData("rfc-index-sample.xml"))
      case "revisions.json":
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

  /// The parts the watcher reads, wired as `LibraryModel` wires them, over an
  /// in-memory store holding a bookmark of RFC 2119.
  /// How many comparisons got as far as posting.
  private final class Posts {
    var count = 0
  }

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

  /// A `304` to a request that sent no validators settles the index with none and
  /// leaves it loading: the refresh goes on rather than waiting for an index that
  /// never comes (#758).
  @Test func `the refresh returns after a 304 with nothing kept`() async throws {
    defer { sandbox.remove() }
    let any = Transport(answersUnchanged: true)
    let parts = try parts(any: any, cheap: Transport())
    await parts.indexes.bootstrap()
    try #require(parts.indexes.indexState == .loading)
    // Required: a refresh waiting on an index that never settles would outlast the
    // time limit, which cannot end the wait.
    try #require(parts.indexes.hasSettled)

    await parts.watcher.refresh()

    #expect(parts.dataFiles.revisions == Self.revisions)
    #expect(any.requests(for: "revisions.json") == 1)
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

  /// The system may suspend the app once the refresh returns, so the comparisons it
  /// started, the index's at launch and the revisions', have posted and kept their
  /// baseline by then.
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
