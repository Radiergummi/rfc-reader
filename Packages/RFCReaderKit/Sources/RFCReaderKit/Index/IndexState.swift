import Foundation

/// Where the library's index stands: not asked for yet, loading, ready, or failed.
public enum IndexState: Equatable, Sendable {
  case idle
  case loading
  case ready(updatedAt: Date)
  /// What kind of failure, for the sentence the status line says, and the error's
  /// own description, which it shows second (#759).
  case failed(LoadFailure.Kind, message: String)

  public var isReady: Bool {
    if case .ready = self { true } else { false }
  }

  public var isFailed: Bool {
    if case .failed = self { true } else { false }
  }

  public static func failed(_ error: any Error) -> IndexState {
    .failed(LoadFailure(error: error).kind, message: error.localizedDescription)
  }

  /// Whether a background refresh checks the index at `now` (#191): one last
  /// checked over a day ago, or one that failed. Not one still loading, which a
  /// background refresh waits for instead.
  public func isCheckDue(now: Date) -> Bool {
    switch self {
    case .ready(let checkedAt): IndexCheck.isDue(checkedAt: checkedAt, now: now)
    case .failed: true
    case .idle, .loading: false
    }
  }
}
