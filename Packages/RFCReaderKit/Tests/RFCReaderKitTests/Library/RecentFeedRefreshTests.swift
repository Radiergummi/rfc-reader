import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Just Published at launch (#421): the feed kept first, then a conditional fetch on a
/// cheap network, and the feed kept still shown when that fails.
@Suite("Recent feed refresh")
struct RecentFeedRefreshTests {
  private let sandbox = DocumentStoreTests.Sandbox()
  private let kept = CacheValidators(entityTag: #"W/"feed-1""#, lastModified: nil)

  /// A feed in the shape the RFC Editor serves, with one entry per number.
  private static func feed(_ numbers: [Int]) -> Data {
    let items = numbers.map { "<item><title>RFC \($0): Entry \($0)</title></item>" }
    return Data(
      "<rss version=\"2.0\"><channel>\(items.joined())</channel></rss>".utf8)
  }

  /// Answers with `status`, and `body` for a `200`, as the RFC Editor serves the feed,
  /// or with `error`; keeps the last request.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let status: Int
    private let body: Data
    private let error: (any Error)?
    private let lock = NSLock()
    private var sent: URLRequest?

    init(status: Int = 200, body: Data = Data(), error: (any Error)? = nil) {
      self.status = status
      self.body = body
      self.error = error
    }

    var request: URLRequest? { lock.withLock { sent } }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      lock.withLock { sent = request }
      if let error { throw error }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/xml", "ETag": #"W/"feed-2""#])!
      return (status == 200 ? body : Data(), response)
    }
  }

  private func storeKeeping(_ numbers: [Int]?) async throws -> DocumentStore {
    let store = sandbox.store()
    try FileManager.default.createDirectory(
      at: sandbox.directory, withIntermediateDirectories: true)
    if let numbers { try await store.storeRecentFeed(Self.feed(numbers), validators: kept) }
    return store
  }

  private func run(_ store: DocumentStore, _ transport: Transport) async throws -> [[DocumentID]] {
    var shown: [[DocumentID]] = []
    try await RecentFeedRefresh.run(
      store: store, client: RFCEditorClient(transport: transport),
      show: { shown.append($0.map(\.id)) })
    return shown
  }

  @Test func `a stored feed is kept with its validators`() async throws {
    let store = try await storeKeeping([9000])
    #expect(await store.cachedRecentFeed() == Self.feed([9000]))
    #expect(store.recentFeedCheck()?.validators == kept)
  }

  @Test func `nothing kept fetches the feed whole, and keeps it`() async throws {
    let store = try await storeKeeping(nil)
    let transport = Transport(body: Self.feed([9001]))
    #expect(try await run(store, transport) == [[.rfc(9001)]])
    #expect(transport.request?.value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(await store.cachedRecentFeed() == Self.feed([9001]))
    #expect(
      store.recentFeedCheck()?.validators
        == CacheValidators(entityTag: #"W/"feed-2""#, lastModified: nil))
  }

  @Test func `an unchanged feed shows the one kept, asked for with its validators`()
    async throws
  {
    let store = try await storeKeeping([9000])
    let transport = Transport(status: 304)
    #expect(try await run(store, transport) == [[.rfc(9000)]])
    #expect(transport.request?.value(forHTTPHeaderField: "If-None-Match") == #"W/"feed-1""#)
    #expect(await store.cachedRecentFeed() == Self.feed([9000]))
  }

  @Test func `a changed feed replaces the one kept`() async throws {
    let store = try await storeKeeping([9000])
    let transport = Transport(body: Self.feed([9001, 9000]))
    #expect(try await run(store, transport) == [[.rfc(9000)], [.rfc(9001), .rfc(9000)]])
    #expect(await store.cachedRecentFeed() == Self.feed([9001, 9000]))
  }

  @Test func `a failed fetch leaves the feed kept shown`() async throws {
    let store = try await storeKeeping([9000])
    var shown: [[DocumentID]] = []
    await #expect(throws: URLError.self) {
      try await RecentFeedRefresh.run(
        store: store,
        client: RFCEditorClient(transport: Transport(error: URLError(.notConnectedToInternet))),
        show: { shown.append($0.map(\.id)) })
    }
    #expect(shown == [[.rfc(9000)]])
    #expect(await store.cachedRecentFeed() == Self.feed([9000]))
  }

  @Test func `the fetch waits for a cheap network`() async throws {
    let transport = Transport(status: 304)
    _ = try await run(try await storeKeeping([9000]), transport)
    let request = try #require(transport.request)
    #expect(!request.allowsExpensiveNetworkAccess)
    #expect(!request.allowsConstrainedNetworkAccess)
  }
}
