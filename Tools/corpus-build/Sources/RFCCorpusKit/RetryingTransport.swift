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
/// that fail together do not all come back at the same moment; a `Retry-After`
/// that asks for longer is waited out instead, up to a cap. After the last
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

  /// The longest a `Retry-After` is waited out, so one answer cannot stall a run.
  public static let longestRetryAfter = Duration.seconds(60)

  public func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var delay = baseDelay
    for _ in 1..<attempts {
      var retryAfter = Duration.zero
      do {
        let (data, response) = try await transport.response(for: request)
        if !Self.isTransient(status: response.statusCode) { return (data, response) }
        retryAfter = Self.retryAfter(response)
      } catch let error as URLError where error.code != .cancelled {
        // A network failure: retried like a transient status.
      }
      // The server's wait when it asks for longer than the backoff would, spread
      // upwards only by the same jitter: never shorter than asked, and downloads
      // told the same wait do not all come back at once.
      let factor = jitter()
      try await sleep(max(delay * factor, retryAfter * (1 + abs(factor - 1))))
      delay *= 2
    }
    return try await transport.response(for: request)
  }

  /// The wait a `Retry-After` header asks for, capped at `longestRetryAfter`; zero
  /// when there is none. Only its delay in seconds is read: the HTTP-date form is
  /// left to the backoff.
  private static func retryAfter(_ response: HTTPURLResponse) -> Duration {
    guard
      let value = response.value(forHTTPHeaderField: "Retry-After")?
        .trimmingCharacters(in: .whitespaces),
      !value.isEmpty, value.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) })
    else { return .zero }
    // Digits too many for an Int ask for longer than the cap.
    guard let seconds = Int(value) else { return longestRetryAfter }
    return min(.seconds(seconds), longestRetryAfter)
  }

  /// A status that says the same request may succeed later.
  static func isTransient(status: Int) -> Bool {
    status == 408 || status == 429 || (500..<600).contains(status)
  }
}
