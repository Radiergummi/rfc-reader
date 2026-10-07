import Foundation
import Network
import RFCReaderKit

/// The network path and Low Power Mode, as `FetchPolicy` reads them (#358), with a
/// call whenever either changes.
///
/// Only the reading of `NWPathMonitor` and `ProcessInfo` is here; what they decide
/// is `FetchPolicy`'s, in RFCReaderKit, where it is tested.
final class NetworkConditions {
  /// The path, or nil until the monitor has reported one, which it does at once.
  private(set) var path: FetchPolicy.Path?
  private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

  private let monitor = NWPathMonitor()
  private var powerChanges: (any NSObjectProtocol)?

  /// Starts watching, calling `changed` on the main actor after each change.
  func start(_ changed: @escaping @MainActor @Sendable () -> Void) {
    monitor.pathUpdateHandler = { [weak self] path in
      let read = Self.policyPath(of: path)
      Task { @MainActor in
        guard let self, read != self.path else { return }
        self.path = read
        changed()
      }
    }
    monitor.start(queue: DispatchQueue(label: "me.mazetti.rfc-reader.network"))
    powerChanges = NotificationCenter.default.addObserver(
      forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard isLowPower != self.isLowPower else { return }
        self.isLowPower = isLowPower
        changed()
      }
    }
  }

  /// Whether a fetch for `cause` goes ahead now: nil until the path is known.
  func decision(for cause: FetchPolicy.Cause) -> FetchPolicy.Decision? {
    path.map { FetchPolicy.decide(cause: cause, path: $0, lowPower: isLowPower) }
  }

  private nonisolated static func policyPath(of path: NWPath) -> FetchPolicy.Path {
    let status: FetchPolicy.PathStatus =
      switch path.status {
      case .satisfied: .satisfied
      case .requiresConnection: .requiresConnection
      case .unsatisfied: path.unsatisfiedReason == .cellularDenied ? .cellularDenied : .unsatisfied
      @unknown default: .unsatisfied
      }
    return FetchPolicy.Path(
      status: status, isExpensive: path.isExpensive, isConstrained: path.isConstrained)
  }
}
