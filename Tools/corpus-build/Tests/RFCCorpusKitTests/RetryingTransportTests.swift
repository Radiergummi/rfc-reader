import Foundation
import RFCCorpusKit
import RFCKit
import Synchronization
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// What the fetch step does when the RFC Editor fails a request: a failure that can
/// pass is retried a bounded number of times with growing, jittered delays, and one
/// that cannot is not retried at all.
@Suite("Fetch: retrying transport")
struct RetryingTransportTests {
  private static let url = URL(string: "https://www.rfc-editor.org/rfc/rfc1.txt")!

  /// One scripted outcome of a request.
  enum Outcome: Sendable {
    case status(Int)
    case failure(URLError.Code)
  }

  /// A transport that answers with `outcomes` in turn, counting the requests.
  final class ScriptedTransport: HTTPTransport {
    private let outcomes: Mutex<[Outcome]>
    private let count = Mutex(0)

    init(_ outcomes: [Outcome]) { self.outcomes = Mutex(outcomes) }

    var requests: Int { count.withLock { $0 } }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      count.withLock { $0 += 1 }
      let outcome = outcomes.withLock { $0.isEmpty ? .status(200) : $0.removeFirst() }
      switch outcome {
      case .status(let status):
        let response = HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data("body \(status)".utf8), response)
      case .failure(let code):
        throw URLError(code)
      }
    }
  }

  /// The delays a transport asked to sleep for.
  final class Sleeps: Sendable {
    private let delays = Mutex<[Duration]>([])
    var recorded: [Duration] { delays.withLock { $0 } }
    func sleep(_ delay: Duration) { delays.withLock { $0.append(delay) } }
  }

  private static func retrying(
    _ transport: ScriptedTransport, sleeps: Sleeps, jitter: Double = 1
  ) -> RetryingTransport {
    RetryingTransport(
      transport, attempts: 4, baseDelay: .seconds(1), jitter: { jitter },
      sleep: { sleeps.sleep($0) })
  }

  @Test func `a server error is retried until the request succeeds`() async throws {
    let transport = ScriptedTransport([.status(503), .status(500)])
    let sleeps = Sleeps()
    let (data, response) = try await Self.retrying(transport, sleeps: sleeps)
      .response(for: URLRequest(url: Self.url))
    #expect(response.statusCode == 200)
    #expect(data == Data("body 200".utf8))
    #expect(transport.requests == 3)
    #expect(sleeps.recorded == [.seconds(1), .seconds(2)], "the delay doubles")
  }

  @Test func `a network failure and a rate limit are retried too`() async throws {
    let transport = ScriptedTransport([
      .failure(.timedOut), .status(429), .failure(.networkConnectionLost),
    ])
    let response = try await Self.retrying(transport, sleeps: Sleeps()).response(
      for: URLRequest(url: Self.url)
    ).1
    #expect(response.statusCode == 200)
    #expect(transport.requests == 4)
  }

  /// The last answer is the caller's to judge: a status is returned as it came, so
  /// the client still reports it as `httpStatus`.
  @Test func `retries are bounded, and the last answer is returned`() async throws {
    let transport = ScriptedTransport(Array(repeating: .status(502), count: 10))
    let sleeps = Sleeps()
    let response = try await Self.retrying(transport, sleeps: sleeps).response(
      for: URLRequest(url: Self.url)
    ).1
    #expect(response.statusCode == 502)
    #expect(transport.requests == 4)
    #expect(sleeps.recorded.count == 3)
  }

  @Test func `the last network failure is thrown once the attempts run out`() async {
    let transport = ScriptedTransport(Array(repeating: .failure(.timedOut), count: 10))
    await #expect(throws: URLError.self) {
      try await Self.retrying(transport, sleeps: Sleeps()).response(for: URLRequest(url: Self.url))
    }
    #expect(transport.requests == 4)
  }

  @Test(arguments: [404, 403, 400])
  func `a client error is not retried`(status: Int) async throws {
    let transport = ScriptedTransport([.status(status)])
    let sleeps = Sleeps()
    let response = try await Self.retrying(transport, sleeps: sleeps).response(
      for: URLRequest(url: Self.url)
    ).1
    #expect(response.statusCode == status)
    #expect(transport.requests == 1)
    #expect(sleeps.recorded.isEmpty)
  }

  @Test func `a canceled request is not retried`() async {
    let transport = ScriptedTransport([.failure(.cancelled)])
    await #expect(throws: URLError.self) {
      try await Self.retrying(transport, sleeps: Sleeps()).response(for: URLRequest(url: Self.url))
    }
    #expect(transport.requests == 1)
  }

  /// Six downloads at once that fail together must not retry together.
  @Test func `each delay is scaled by the jitter`() async throws {
    let transport = ScriptedTransport([.status(503), .status(503)])
    let sleeps = Sleeps()
    _ = try await Self.retrying(transport, sleeps: sleeps, jitter: 0.5).response(
      for: URLRequest(url: Self.url))
    #expect(sleeps.recorded == [.milliseconds(500), .seconds(1)])
  }

  @Test func `the default jitter stays between half and one and a half`() {
    for _ in 0..<200 {
      #expect((0.5...1.5).contains(RetryingTransport.randomJitter()))
    }
  }
}
