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
}
