import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Just Published's feed asked for only when it changed, and only on a cheap network
/// (#421), as the index is.
@Suite("Recent feed fetch")
struct RecentFeedFetchTests {
  private let validators = CacheValidators(entityTag: #"W/"feed-1""#, lastModified: nil)

  @Test func `the request carries the validators it was given`() async throws {
    let transport = ScriptedTransport(status: 304, body: Data())
    _ = try await RFCEditorClient(transport: transport)
      .fetchRecentData(unlessMatching: validators, onExpensiveNetworks: false)
    let request = try #require(transport.request)
    #expect(request.url == RFCEditorEndpoints.recentFeed)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == #"W/"feed-1""#)
  }

  @Test func `not modified is unchanged`() async throws {
    let fetched = try await RFCEditorClient(transport: ScriptedTransport(status: 304, body: Data()))
      .fetchRecentData(unlessMatching: validators, onExpensiveNetworks: false)
    #expect(fetched == .unchanged)
  }

  @Test func `a new feed comes with its own validators, and parses`() async throws {
    let body = try Fixtures.data("rfcrss.xml")
    let transport = ScriptedTransport(status: 200, body: body, headers: ["ETag": #"W/"feed-2""#])
    let fetched = try await RFCEditorClient(transport: transport)
      .fetchRecentData(unlessMatching: validators, onExpensiveNetworks: false)
    #expect(
      fetched == .changed(body, CacheValidators(entityTag: #"W/"feed-2""#, lastModified: nil)))
    #expect(try RecentRFC.parseFeed(body).first?.id == .rfc(10050))
  }

  @Test func `a page that is not a feed is refused`() {
    #expect(throws: (any Error).self) { try RecentRFC.parseFeed(Data("<html/>".utf8)) }
  }

  #if !canImport(FoundationNetworking)
    @Test func `a fetch nobody asked for waits for a cheap network`() async throws {
      let transport = ScriptedTransport(status: 304, body: Data())
      _ = try await RFCEditorClient(transport: transport)
        .fetchRecentData(unlessMatching: nil, onExpensiveNetworks: false)
      let request = try #require(transport.request)
      #expect(!request.allowsExpensiveNetworkAccess)
      #expect(!request.allowsConstrainedNetworkAccess)
    }
  #endif
}
