import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The data files beside the index (#595, #758): the revisions and the working groups
/// fetched once a day by the copy kept, which a new launch remembers, on any network
/// when nothing is kept and on a cheap one when a copy is.
@Suite("Data file refresher")
@MainActor
struct DataFileRefresherTests {
  private let sandbox = DocumentStoreTests.Sandbox()

  nonisolated private static let revisions = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 1_000), revisions: [:])
  nonisolated private static let newerRevisions = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 2_000), revisions: [:])
  nonisolated private static let groups = WorkingGroups(
    generatedAt: Date(timeIntervalSince1970: 1_000), groups: [])
  /// A registry in the shape IANA serves, with one record.
  nonisolated private static let statusCodes = """
    <?xml version='1.0' encoding='UTF-8'?>
    <registry xmlns="http://www.iana.org/assignments" id="http-status-codes">
      <registry id="http-status-codes-1">
        <record>
          <value>425</value>
          <description>Too Early</description>
        </record>
      </registry>
    </registry>
    """

  /// Answers `revisions.json` and `groups.json` with `revisions` and `groups`, and
  /// everything else with a `404`; counts the requests for each file. Holds a request
  /// for `holding` until it is canceled, as a session waiting for a cheap network does,
  /// and says so on `held`. Gives up on it after half a minute, so a refresh that is
  /// never canceled fails the test rather than hanging it: the time limit cancels the
  /// test, not the refresh's own task. Fails the first `failing` requests, as a path
  /// with no network does.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let revisions: RFCRevisions
    private let holding: String?
    private let lock = NSLock()
    private var sent: [String] = []
    private var failing: Int
    private let heldRequests = AsyncStream<Void>.makeStream()
    /// Yields when a request for `holding` is being held.
    var held: AsyncStream<Void> { heldRequests.stream }

    init(
      revisions: RFCRevisions = DataFileRefresherTests.revisions, holding: String? = nil,
      failing: Int = 0
    ) {
      self.revisions = revisions
      self.holding = holding
      self.failing = failing
    }

    func requests(for file: String) -> Int {
      lock.withLock { sent.count(where: { $0 == file }) }
    }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let file = request.url!.lastPathComponent
      let fails = lock.withLock {
        sent.append(file)
        failing -= 1
        return failing >= 0
      }
      if fails { throw URLError(.notConnectedToInternet) }
      if file == holding {
        heldRequests.continuation.yield()
        try await Task.sleep(for: .seconds(30))
        throw URLError(.timedOut)
      }
      let body: Data? =
        switch file {
        case "revisions.json": try revisions.encoded()
        case "groups.json": try DataFileRefresherTests.groups.encoded()
        case "http-status-codes.xml": Data(DataFileRefresherTests.statusCodes.utf8)
        default: nil
        }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil,
        headerFields: [
          "Content-Type": file.hasSuffix(".xml") ? "application/xml" : "application/json"
        ])!
      return (body ?? Data(), response)
    }
  }

  private func refresher(
    any: Transport, cheap: Transport, now: @escaping () -> Date = { .now }
  ) -> DataFileRefresher {
    DataFileRefresher(
      store: sandbox.store(), client: RFCEditorClient(transport: any),
      clientOnCheapNetworks: RFCEditorClient(transport: cheap), now: now)
  }

  @Test func `with nothing kept, both files are fetched on any network, and kept`() async throws {
    defer { sandbox.remove() }
    let any = Transport()
    let cheap = Transport()
    let refresher = refresher(any: any, cheap: cheap)
    await refresher.refreshAll()
    #expect(refresher.revisions == Self.revisions)
    #expect(refresher.workingGroups == Self.groups)
    #expect(any.requests(for: "revisions.json") == 1)
    #expect(any.requests(for: "groups.json") == 1)
    #expect(cheap.requests(for: "revisions.json") == 0)
    #expect(cheap.requests(for: "groups.json") == 0)
    #expect(await sandbox.store().cachedRevisions()?.value == Self.revisions)
    #expect(await sandbox.store().cachedWorkingGroups()?.value == Self.groups)
  }

  /// What #758 is about: a new process no longer counts as never fetched.
  @Test func `a second launch the same day fetches neither file`() async throws {
    defer { sandbox.remove() }
    await refresher(any: Transport(), cheap: Transport()).refreshAll()
    let any = Transport()
    let cheap = Transport()
    let relaunched = refresher(any: any, cheap: cheap)
    await relaunched.refreshAll()
    #expect(relaunched.revisions == Self.revisions)
    #expect(relaunched.workingGroups == Self.groups)
    for transport in [any, cheap] {
      #expect(transport.requests(for: "revisions.json") == 0)
      #expect(transport.requests(for: "groups.json") == 0)
    }
  }

  @Test func `a due refresh with a copy kept waits for a cheap network`() async throws {
    defer { sandbox.remove() }
    await refresher(any: Transport(), cheap: Transport()).refreshAll()
    let any = Transport()
    let cheap = Transport(revisions: Self.newerRevisions)
    let nextDay = Date.now.addingTimeInterval(IndexCheck.interval + 60)
    let refresher = refresher(any: any, cheap: cheap, now: { nextDay })
    await refresher.refreshAll()
    #expect(refresher.revisions == Self.newerRevisions)
    #expect(cheap.requests(for: "revisions.json") == 1)
    #expect(cheap.requests(for: "groups.json") == 1)
    #expect(any.requests(for: "revisions.json") == 0)
    #expect(any.requests(for: "groups.json") == 0)
  }

  /// Within a run too: activation after activation asks once a day.
  @Test func `a refresh after one that fetched asks for nothing`() async throws {
    defer { sandbox.remove() }
    let any = Transport()
    let refresher = refresher(any: any, cheap: Transport())
    await refresher.refreshAll()
    await refresher.refreshAll()
    #expect(any.requests(for: "revisions.json") == 1)
    #expect(any.requests(for: "groups.json") == 1)
  }

  @Test func `a failed fetch is asked again at the next refresh`() async throws {
    defer { sandbox.remove() }
    let any = Transport(failing: 1)
    let refresher = refresher(any: any, cheap: Transport())
    await refresher.refreshRevisions()
    #expect(refresher.revisions == nil)
    await refresher.refreshRevisions()
    #expect(refresher.revisions == Self.revisions)
    #expect(any.requests(for: "revisions.json") == 2)
  }

  /// The fetch is recorded before the write, so a copy that cannot be kept is not
  /// downloaded again at every activation.
  @Test func `a fetch whose copy cannot be kept is not asked again the same day`()
    async throws
  {
    defer { sandbox.remove() }
    // A folder where the file goes, so neither a read nor a write of it succeeds.
    let blocked = sandbox.directory.appending(path: "revisions.json", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try Data().write(to: blocked.appending(path: "occupied"))
    let any = Transport()
    let cheap = Transport()
    let refresher = refresher(any: any, cheap: cheap)
    await refresher.refreshRevisions()
    await refresher.refreshRevisions()
    #expect(refresher.revisions == Self.revisions)
    #expect(any.requests(for: "revisions.json") + cheap.requests(for: "revisions.json") == 1)
  }

  @Test func `the revisions report the copy kept and each change`() async throws {
    defer { sandbox.remove() }
    try await sandbox.store().storeRevisions(Self.revisions.encoded())
    let nextDay = Date.now.addingTimeInterval(IndexCheck.interval + 60)
    let refresher = refresher(
      any: Transport(), cheap: Transport(revisions: Self.newerRevisions), now: { nextDay })
    var reported: [RFCRevisions?] = []
    refresher.onRevisionsChanged = { [weak refresher] in reported.append(refresher?.revisions) }
    await refresher.refreshRevisions()
    #expect(reported == [Self.revisions, Self.newerRevisions])
  }

  // MARK: - The bookmark refresh

  /// A background refresh on a phone network would otherwise post nothing about a
  /// revised bookmark (#758, answer 1).
  @Test func `the bookmark refresh fetches due revisions on any network`() async throws {
    defer { sandbox.remove() }
    try await sandbox.store().storeRevisions(Self.revisions.encoded())
    let any = Transport(revisions: Self.newerRevisions)
    let cheap = Transport()
    let nextDay = Date.now.addingTimeInterval(IndexCheck.interval + 60)
    let refresher = refresher(any: any, cheap: cheap, now: { nextDay })
    await refresher.refreshRevisions(onExpensiveNetworks: true)
    #expect(refresher.revisions == Self.newerRevisions)
    #expect(any.requests(for: "revisions.json") == 1)
    #expect(cheap.requests(for: "revisions.json") == 0)
  }

  @Test func `the bookmark refresh does not fetch revisions that are not due`() async throws {
    defer { sandbox.remove() }
    try await sandbox.store().storeRevisions(Self.revisions.encoded())
    let any = Transport()
    let refresher = refresher(any: any, cheap: Transport())
    await refresher.refreshRevisions(onExpensiveNetworks: true)
    #expect(refresher.revisions == Self.revisions)
    #expect(any.requests(for: "revisions.json") == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `the bookmark refresh replaces a refresh waiting for a cheap network`()
    async throws
  {
    defer { sandbox.remove() }
    try await sandbox.store().storeRevisions(Self.revisions.encoded())
    let any = Transport(revisions: Self.newerRevisions)
    let cheap = Transport(holding: "revisions.json")
    let nextDay = Date.now.addingTimeInterval(IndexCheck.interval + 60)
    let refresher = refresher(any: any, cheap: cheap, now: { nextDay })
    let waiting = Task { await refresher.refreshRevisions() }
    // Awaited rather than polled: a loop yielding the main actor took this past the
    // time limit when the whole suite ran on the iOS Simulator in CI. A
    // refresh that never asks the cheap-network client ends at the time limit, which
    // cancels the wait.
    var held = cheap.held.makeAsyncIterator()
    await held.next()
    try #require(cheap.requests(for: "revisions.json") == 1)
    await refresher.refreshRevisions(onExpensiveNetworks: true)
    #expect(refresher.revisions == Self.newerRevisions)
    #expect(any.requests(for: "revisions.json") == 1)
    await waiting.value
  }

  // MARK: - Registries

  /// The first fetch of a registry takes any network, and an intent waits for it;
  /// one that fails leaves the others readable.
  @Test func `registries never kept are fetched on any network for who waits`() async throws {
    defer { sandbox.remove() }
    let any = Transport()
    let cheap = Transport()
    let refresher = refresher(any: any, cheap: cheap)
    let entries = await refresher.loadedRegistryEntries()
    #expect(entries.map(\.value) == ["425"])
    #expect(refresher.registryMatches(for: "425").map(\.value) == ["425"])
    #expect(any.requests(for: "http-status-codes.xml") == 1)
    #expect(cheap.requests(for: "http-status-codes.xml") == 0)
  }

  @Test func `registries kept within their age are read, not fetched`() async throws {
    defer { sandbox.remove() }
    try await sandbox.store().storeRegistry(Data(Self.statusCodes.utf8), for: .httpStatusCodes)
    let any = Transport()
    let cheap = Transport()
    let refresher = refresher(any: any, cheap: cheap)
    let entries = await refresher.loadedRegistryEntries()
    #expect(entries.map(\.value) == ["425"])
    #expect(any.requests(for: "http-status-codes.xml") == 0)
    #expect(cheap.requests(for: "http-status-codes.xml") == 0)
  }
}
