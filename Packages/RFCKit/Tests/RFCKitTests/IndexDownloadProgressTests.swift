import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The index's download reports the bytes it has received (#770), for the first
/// launch's progress: the RFC Editor sends no `Content-Length`, so bytes are all there
/// is to report.
@Suite("Index download progress")
struct IndexDownloadProgressTests {
  /// Reports the body's bytes in two halves before answering with it.
  private struct Reporting: HTTPTransport {
    let body = Data("<rfc-index/>".utf8)

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      (body, HTTPURLResponse.served(from: request.url!, statusCode: 200))
    }

    func response(
      for request: URLRequest, onReceived: @escaping @Sendable (Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
      onReceived(Int64(body.count / 2))
      onReceived(Int64(body.count))
      return try await response(for: request)
    }
  }

  private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int64] = []
    var all: [Int64] { lock.withLock { counts } }
    func append(_ count: Int64) { lock.withLock { counts.append(count) } }
  }

  @Test func `the index's bytes are reported as they arrive`() async throws {
    let received = Received()
    _ = try await RFCEditorClient(transport: Reporting())
      .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true) { received.append($0) }
    #expect(received.all == [6, 12])
  }

  /// A transport that cannot tell answers as it always does, and reports nothing.
  @Test func `a transport that cannot report still answers`() async throws {
    let received = Received()
    let fetched = try await RFCEditorClient(
      transport: ScriptedTransport(status: 200, body: Data("<rfc-index/>".utf8))
    )
    .fetchIndexData(unlessMatching: nil, onExpensiveNetworks: true) { received.append($0) }
    #expect(fetched == .changed(Data("<rfc-index/>".utf8), nil))
    #expect(received.all.isEmpty)
  }
}
