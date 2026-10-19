import Foundation

/// What the library list shows in place of its rows while there is no index to list
/// (#770): the index downloading, or why it could not be loaded. Nil when the list
/// has an index, or is only reading the one kept or bundled, which its status line
/// says.
public enum IndexPlaceholder: Equatable, Sendable {
  /// The bytes received so far. The RFC Editor sends the index without a length, so
  /// there is no fraction to show.
  case downloading(bytesReceived: Int64)
  case failed(LoadFailure.Kind, message: String)

  /// - Parameter bytesReceived: The bytes the index's download has received, nil when
  ///   none is under way. A Retry's download shows in place of the failure it retries.
  public init?(state: IndexState, hasIndex: Bool, bytesReceived: Int64?) {
    guard !hasIndex else { return nil }
    if let bytesReceived {
      self = .downloading(bytesReceived: bytesReceived)
    } else if case .failed(let kind, let message) = state {
      self = .failed(kind, message: message)
    } else {
      return nil
    }
  }

  /// Which of a download's byte counts the placeholder is told of: one each time
  /// another 100 KB has arrived, so the main actor hears of the download in steps it
  /// shows rather than at every packet.
  public struct ProgressSteps: Sendable {
    private var last: Int64 = 0

    public init() {}

    /// Whether `bytes` is a step past the last one, which it then is.
    public mutating func isStep(_ bytes: Int64) -> Bool {
      guard bytes >= last + 100_000 else { return false }
      last = bytes
      return true
    }
  }
}
