import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The client's transport and errors (#148).
@Suite("Client transport", .serialized)
struct ClientTransportTests {
  /// A `URLProtocol` that answers every request with `StubProtocol.response`, and
  /// remembers the last request it saw. Serialized suite: one stub at a time.
  final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: URLResponse?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      Self.lastRequest = request
      client?.urlProtocol(self, didReceive: Self.response!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data("body".utf8))
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  /// The stub's state is shared; each test starts from none, not the last test's.
  init() {
    StubProtocol.response = nil
    StubProtocol.lastRequest = nil
  }

  /// One session for the suite, answered by the stub.
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: configuration)
  }()

  private static let url = URL(string: "https://www.rfc-editor.org/rfc/rfc9110.xml")!

  @Test func `the client asks for the formats it reads`() async throws {
    StubProtocol.response = HTTPURLResponse(
      url: Self.url, statusCode: 200, httpVersion: nil, headerFields: nil)
    let data = try await RFCEditorClient(transport: URLSessionTransport(session: Self.session))
      .fetchDocumentData(.rfc(9110), format: .xml)
    #expect(String(decoding: data, as: UTF8.self) == "body")
    #expect(
      StubProtocol.lastRequest?.value(forHTTPHeaderField: "Accept")
        == "application/xml, text/plain, application/json")
  }

  @Test func `a response that is not HTTP is an invalid response`() async throws {
    StubProtocol.response = URLResponse(
      url: Self.url, mimeType: nil, expectedContentLength: 4, textEncodingName: nil)
    await #expect {
      _ = try await URLSessionTransport(session: Self.session).response(
        for: URLRequest(url: Self.url))
    } throws: { error in
      guard case .invalidResponse(let url) = error as? RFCEditorClient.ClientError else {
        return false
      }
      return url == Self.url
    }
  }

  /// A malformed index names what it was reading and keeps why it failed.
  @Test func `a decoding error keeps the error beneath it`() async throws {
    struct Garbage: HTTPTransport {
      func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (
          Data("<not-the-index".utf8),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    }
    await #expect {
      _ = try await RFCEditorClient(transport: Garbage()).fetchIndex()
    } throws: { error in
      guard case .decoding(let context, let underlying) = error as? RFCEditorClient.ClientError
      else { return false }
      return context == "rfc-index.xml" && underlying is RFCIndexParser.ParseError
    }
  }
}
