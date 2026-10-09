import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Conditional index fetch")
struct ConditionalIndexFetchTests {
  private static func transport(status: Int, headers: [String: String] = [:])
    -> ScriptedTransport
  {
    ScriptedTransport(status: status, body: Data("<rfc-index/>".utf8), headers: headers)
  }

  private let validators = CacheValidators(
    entityTag: #""5321fefa-2""#, lastModified: "Sat, 26 Sep 2026 20:00:00 GMT")

  @Test func `validators are read from the response headers`() {
    let response = HTTPURLResponse(
      url: RFCEditorEndpoints.index, statusCode: 200, httpVersion: nil,
      headerFields: ["ETag": #""5321fefa-2""#, "Last-Modified": "Sat, 26 Sep 2026 20:00:00 GMT"])!
    #expect(CacheValidators(response: response) == validators)
  }

  @Test func `a response without validators has none`() {
    let response = HTTPURLResponse(
      url: RFCEditorEndpoints.index, statusCode: 200, httpVersion: nil, headerFields: [:])!
    #expect(CacheValidators(response: response) == nil)
  }

  @Test func `the request carries the validators it was given`() async throws {
    let transport = Self.transport(status: 304)
    _ = try await RFCEditorClient(transport: transport)
      .fetchIndexData(unlessMatching: validators, onExpensiveNetworks: true)
    let request = try #require(transport.request)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""5321fefa-2""#)
    #expect(
      request.value(forHTTPHeaderField: "If-Modified-Since") == "Sat, 26 Sep 2026 20:00:00 GMT")
  }

  @Test func `a request without validators is unconditional`() async throws {
    let transport = Self.transport(status: 200)
    _ = try await RFCEditorClient(transport: transport)
      .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true)
    let request = try #require(transport.request)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
  }

  @Test func `not modified is unchanged`() async throws {
    let fetched = try await RFCEditorClient(transport: Self.transport(status: 304))
      .fetchIndexData(unlessMatching: validators, onExpensiveNetworks: true)
    #expect(fetched == .unchanged)
  }

  @Test func `a new index comes with its own validators`() async throws {
    let transport = Self.transport(status: 200, headers: ["ETag": #""next""#])
    let fetched = try await RFCEditorClient(transport: transport)
      .fetchIndexData(unlessMatching: validators, onExpensiveNetworks: true)
    #expect(
      fetched
        == .changed(
          Data("<rfc-index/>".utf8), CacheValidators(entityTag: #""next""#, lastModified: nil)))
  }

  #if !canImport(FoundationNetworking)
    @Test func `a fetch nobody asked for waits for a cheap network`() async throws {
      let transport = Self.transport(status: 304)
      _ = try await RFCEditorClient(transport: transport)
        .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: false)
      let request = try #require(transport.request)
      #expect(!request.allowsExpensiveNetworkAccess)
      #expect(!request.allowsConstrainedNetworkAccess)
    }

    @Test func `the session for a fetch nobody asked for waits for a cheap network`() {
      let configuration = URLSession.rfcEditorOnCheapNetworks.configuration
      #expect(configuration.waitsForConnectivity)
      #expect(!configuration.allowsExpensiveNetworkAccess)
      #expect(!configuration.allowsConstrainedNetworkAccess)
      #expect(configuration.urlCache == nil)
    }

    @Test func `the session for a fetch someone asked for fails fast`() {
      #expect(!URLSession.rfcEditor.configuration.waitsForConnectivity)
    }

    @Test func `a fetch someone asked for takes any network`() async throws {
      let transport = Self.transport(status: 304)
      _ = try await RFCEditorClient(transport: transport)
        .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true)
      let request = try #require(transport.request)
      #expect(request.allowsExpensiveNetworkAccess)
      #expect(request.allowsConstrainedNetworkAccess)
    }
  #endif
}
