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
      url: Self.url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/xml"])
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
          HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/xml"])!
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

  /// Answers every request with `body`, as `contentType`, from `host` or the request's
  /// own.
  struct Answering: HTTPTransport {
    var contentType: String?
    var host: String?
    var body = Data("body".utf8)

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
      if let host { components.host = host }
      let headers = contentType.map { ["Content-Type": $0] } ?? [:]
      return (
        body,
        HTTPURLResponse(
          url: components.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
      )
    }
  }

  private static func isInvalidResponse(_ error: any Error) -> Bool {
    if case .invalidResponse = error as? RFCEditorClient.ClientError { return true }
    return false
  }

  /// A proxy's block page served as `rfcNNNN.txt` would otherwise become that RFC in
  /// the cache, until Remove Offline Copy (#757).
  @Test func `a document body of another type is refused`() async {
    for (format, contentType) in [
      (FileFormat.text, "text/html"), (.xml, "text/html"), (.text, "application/xml"), (.xml, nil),
    ] {
      await #expect {
        _ = try await RFCEditorClient(transport: Answering(contentType: contentType))
          .fetchDocumentData(.rfc(9110), format: format)
      } throws: { Self.isInvalidResponse($0) }
    }
  }

  @Test func `a document body of its own type is read, whatever its parameters`() async throws {
    for (format, contentType) in [
      (FileFormat.text, "text/plain;charset=utf-8"), (.xml, "application/xml;charset=utf-8"),
      (.xml, "text/xml"),
    ] {
      let data = try await RFCEditorClient(transport: Answering(contentType: contentType))
        .fetchDocumentData(.rfc(9110), format: format)
      #expect(data == Data("body".utf8))
    }
  }

  /// A redirect to another host is a captive portal or a proxy, not the RFC Editor.
  @Test func `a body from another host is refused`() async {
    await #expect {
      _ = try await RFCEditorClient(
        transport: Answering(contentType: "text/plain", host: "portal.example")
      )
      .fetchDocumentData(.rfc(9110), format: .text)
    } throws: { Self.isInvalidResponse($0) }
  }

  /// The index, the feed and the registries are XML, and an HTML page in their place
  /// is refused before anything parses or keeps it.
  @Test func `an index, feed or registry that is not XML is refused`() async {
    let client = RFCEditorClient(transport: Answering(contentType: "text/html"))
    await #expect {
      _ = try await client.fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true)
    } throws: { Self.isInvalidResponse($0) }
    await #expect {
      _ = try await client.fetchRecent()
    } throws: { Self.isInvalidResponse($0) }
    await #expect {
      _ = try await client.fetchRegistry(.httpStatusCodes, onExpensiveNetworks: true)
    } throws: { Self.isInvalidResponse($0) }
  }
}
