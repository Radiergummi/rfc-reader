import Foundation
import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A transport that retries what can pass: a network failure, a rate limit or a
/// server error. A full fetch is some 18,000 requests, and without this one dropped
/// connection or 503 left a document missing until the next run.
///
/// Bounded, so a server that stays down fails the run instead of stalling it; each
/// delay doubles from `baseDelay` and is scaled by a jitter, so concurrent downloads
/// that fail together do not all come back at the same moment. After the last
/// attempt the answer is returned as it came, a status included, for the client to
/// report.
public struct RetryingTransport: HTTPTransport {
  /// What `corpus-build` sends as its User-Agent, so the RFC Editor's operators can
  /// tell a bulk fetch from a reader.
  public static let userAgent =
    "rfc-reader corpus-build (+https://github.com/Radiergummi/rfc-reader)"

  private let transport: any HTTPTransport
  private let attempts: Int
  private let baseDelay: Duration
  private let jitter: @Sendable () -> Double
  private let sleep: @Sendable (Duration) async throws -> Void

  /// `attempts` counts the first request. `jitter` returns the factor each delay is
  /// scaled by, and `sleep` waits; both are parameters so a test can see the delays
  /// without waiting them out.
  public init(
    _ transport: any HTTPTransport,
    attempts: Int = 4,
    baseDelay: Duration = .seconds(2),
    jitter: @escaping @Sendable () -> Double = RetryingTransport.randomJitter,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.transport = transport
    self.attempts = max(attempts, 1)
    self.baseDelay = baseDelay
    self.jitter = jitter
    self.sleep = sleep
  }

  /// A factor between half and one and a half.
  @Sendable public static func randomJitter() -> Double {
    Double.random(in: 0.5...1.5)
  }

  public func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
    var delay = baseDelay
    for _ in 1..<attempts {
      do {
        let (data, response) = try await transport.data(for: url)
        if !Self.isTransient(status: response.statusCode) { return (data, response) }
      } catch let error as URLError where error.code != .cancelled {
        // A network failure: retried like a transient status.
      }
      try await sleep(delay * jitter())
      delay *= 2
    }
    return try await transport.data(for: url)
  }

  /// A status that says the same request may succeed later.
  static func isTransient(status: Int) -> Bool {
    status == 408 || status == 429 || (500..<600).contains(status)
  }
}
