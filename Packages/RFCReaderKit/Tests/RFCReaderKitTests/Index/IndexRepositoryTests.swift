import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The index as `LibraryModel` loads it (#595): read from the copy kept at launch, or
/// fetched on any network when there is none; checked once a day on a cheap network,
/// with the kept copy's validators; fetched again on any network when a person asks,
/// which replaces the automatic check (#983); and settled whatever comes of it.
@Suite("Index repository", .hangGuard)
@MainActor
struct IndexRepositoryTests {
  private let sandbox = DocumentStoreTests.Sandbox()

  nonisolated private static let entityTag = "\"index-1\""

  /// Answers the index with the committed sample and an `ETag`, or with a `304` when
  /// `answersUnchanged`; everything else with a `404`. Records the index requests and
  /// whether each sent the `ETag`. Fails the first `failing` index requests, as a
  /// path with no network does, and holds each while `holds` until it is canceled, as
  /// a session waiting for a cheap network does, saying so on `held`. Gives up on a
  /// held request after half a minute, so one never canceled fails the test rather
  /// than hanging it.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var conditional: [Bool] = []
    private var failing: Int
    private let answersUnchanged: Bool
    private let holds: Bool
    private let heldRequests = AsyncStream<Void>.makeStream()
    /// Yields when an index request is being held.
    var held: AsyncStream<Void> { heldRequests.stream }

    init(failing: Int = 0, answersUnchanged: Bool = false, holds: Bool = false) {
      self.failing = failing
      self.answersUnchanged = answersUnchanged
      self.holds = holds
    }

    /// How many index requests were sent.
    var indexRequests: Int { lock.withLock { conditional.count } }
    /// Whether each index request sent the `ETag` kept.
    var sentEntityTag: [Bool] { lock.withLock { conditional } }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      guard request.url!.lastPathComponent == "rfc-index.xml" else {
        return (Data(), Self.response(to: request, status: 404))
      }
      let fails = lock.withLock {
        conditional.append(
          request.value(forHTTPHeaderField: "If-None-Match") == IndexRepositoryTests.entityTag)
        failing -= 1
        return failing >= 0
      }
      if fails { throw URLError(.notConnectedToInternet) }
      if holds {
        heldRequests.continuation.yield()
        try await Task.sleep(for: .seconds(30))
        throw URLError(.timedOut)
      }
      if answersUnchanged {
        return (Data(), Self.response(to: request, status: 304))
      }
      let data = try Fixtures.rfcKitData("rfc-index-sample.xml")
      return (data, Self.response(to: request, status: 200))
    }

    private static func response(to request: URLRequest, status: Int) -> HTTPURLResponse {
      HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: [
          "Content-Type": "application/xml", "ETag": IndexRepositoryTests.entityTag,
        ])!
    }
  }

  /// What the repository told its owner, in order.
  private final class Calls {
    var made: [String] = []
  }

  private func repository(
    any: Transport, cheap: Transport, calls: Calls = Calls(),
    now: @escaping () -> Date = { .now }
  ) -> IndexRepository {
    let repository = IndexRepository(
      store: sandbox.store(), client: RFCEditorClient(transport: any),
      clientOnCheapNetworks: RFCEditorClient(transport: cheap), textIndexLocation: nil,
      now: now)
    repository.onApplied = { calls.made.append("applied") }
    repository.onSettled = { calls.made.append("settled") }
    return repository
  }

  /// The day after the index kept was checked, when the next launch checks it.
  private static var nextDay: Date { .now.addingTimeInterval(IndexCheck.interval + 60) }

  @Test func `with nothing kept, launch fetches the index on any network and keeps it`()
    async throws
  {
    defer { sandbox.remove() }
    let any = Transport()
    let cheap = Transport()
    let calls = Calls()
    let repository = repository(any: any, cheap: cheap, calls: calls)
    await repository.bootstrap()
    #expect(repository.indexState.isReady)
    #expect(repository.metadata(.rfc(2119)) != nil)
    #expect(repository.indexVersion == 1)
    #expect(await repository.settledSearch() != nil)
    #expect(any.indexRequests == 1)
    #expect(cheap.indexRequests == 0)
    #expect(sandbox.store().indexCheck()?.validators?.entityTag == Self.entityTag)
    // Spotlight and the bookmarks before the links held for the index.
    #expect(calls.made == ["applied", "settled"])
  }

  @Test func `a launch with the index kept reads it without asking the RFC Editor`() async {
    defer { sandbox.remove() }
    await repository(any: Transport(), cheap: Transport()).bootstrap()
    let any = Transport()
    let cheap = Transport()
    let relaunched = repository(any: any, cheap: cheap)
    await relaunched.bootstrap()
    #expect(relaunched.indexState.isReady)
    #expect(relaunched.metadata(.rfc(2119)) != nil)
    #expect(any.indexRequests == 0)
    #expect(cheap.indexRequests == 0)
  }

  @Test
  func
    `a day later, launch checks on a cheap network with the validators, and a 304 keeps the index`()
    async throws
  {
    defer { sandbox.remove() }
    await repository(any: Transport(), cheap: Transport()).bootstrap()
    let any = Transport()
    let cheap = Transport(answersUnchanged: true)
    let calls = Calls()
    let relaunched = repository(any: any, cheap: cheap, calls: calls, now: { Self.nextDay })
    await relaunched.bootstrap()
    await relaunched.check().value
    #expect(any.indexRequests == 0)
    #expect(cheap.sentEntityTag == [true])
    #expect(relaunched.indexState.isReady)
    #expect(relaunched.indexVersion == 1)
    #expect(calls.made == ["applied", "settled"])
  }

  @Test func `a first fetch that fails settles the index as failed, with no search`() async throws {
    defer { sandbox.remove() }
    let calls = Calls()
    let repository = repository(any: Transport(failing: 1), cheap: Transport(), calls: calls)
    await repository.bootstrap()
    #expect(repository.indexState.isFailed)
    // Required: waiting on an index that never settles would outlast the time limit.
    try #require(repository.hasSettled)
    #expect(await repository.settledSearch() == nil)
    #expect(calls.made == ["settled"])
  }

  @Test func `Retry after a failure fetches on any network and shows the index`() async {
    defer { sandbox.remove() }
    let any = Transport(failing: 1)
    let repository = repository(any: any, cheap: Transport())
    await repository.bootstrap()
    #expect(repository.indexState.isFailed)
    repository.retry()
    await repository.refreshNow()
    #expect(repository.indexState.isReady)
    #expect(repository.metadata(.rfc(2119)) != nil)
    // Retry and the refresh that joined it fetched once between them.
    #expect(any.indexRequests == 2)
  }

  /// A `304` with nothing kept sent no validators: there is no index to wait for, so
  /// what waits for it goes ahead, though the state stays loading (#758).
  @Test func `a 304 to a first fetch settles the index with none`() async throws {
    defer { sandbox.remove() }
    let any = Transport(answersUnchanged: true)
    let repository = repository(any: any, cheap: Transport())
    await repository.bootstrap()
    #expect(any.sentEntityTag == [false])
    #expect(repository.indexState == .loading)
    try #require(repository.hasSettled)
    #expect(await repository.settledSearch() == nil)
  }

  /// #983: the automatic check may wait for a cheap network for as long as there is
  /// none; a person's refresh doesn't wait behind it.
  @Test func `a person's refresh replaces the automatic check that waits for a cheap network`()
    async
  {
    defer { sandbox.remove() }
    await repository(any: Transport(), cheap: Transport()).bootstrap()
    let any = Transport()
    let cheap = Transport(holds: true)
    let relaunched = repository(any: any, cheap: cheap, now: { Self.nextDay })
    await relaunched.bootstrap()
    var held = cheap.held.makeAsyncIterator()
    await held.next()
    await relaunched.refreshNow()
    #expect(any.sentEntityTag == [true])
    #expect(cheap.indexRequests == 1)
    #expect(relaunched.indexState.isReady)
    // The index fetched again, installed over the one kept.
    #expect(relaunched.indexVersion == 2)
  }

  @Test func `an intent that asks before launch waits for the index`() async {
    defer { sandbox.remove() }
    let repository = repository(any: Transport(), cheap: Transport())
    let asked = Task { await repository.settledSearch() }
    #expect(!repository.hasSettled)
    await repository.bootstrap()
    #expect(await asked.value != nil)
  }

  @Test func `a series is shown as its first member once the index names it`() async {
    defer { sandbox.remove() }
    let repository = repository(any: Transport(), cheap: Transport())
    let series = DocumentID(series: .bcp, number: 14)
    // While the index loads, a series waits for it; an RFC never does.
    #expect(repository.documentShown(for: series) == nil)
    #expect(repository.documentShown(for: .rfc(8174)) == .rfc(8174))
    await repository.bootstrap()
    #expect(repository.documentShown(for: series) == .rfc(2119))
  }

  @Test func `a series is shown from its own file once the index has failed`() async {
    defer { sandbox.remove() }
    let repository = repository(any: Transport(failing: 1), cheap: Transport())
    let series = DocumentID(series: .bcp, number: 14)
    await repository.bootstrap()
    #expect(repository.documentShown(for: series) == series)
  }

  @Test func `a second bootstrap does nothing`() async {
    defer { sandbox.remove() }
    let any = Transport()
    let calls = Calls()
    let repository = repository(any: any, cheap: Transport(), calls: calls)
    await repository.bootstrap()
    await repository.bootstrap()
    #expect(any.indexRequests == 1)
    #expect(calls.made == ["applied", "settled"])
  }
}
