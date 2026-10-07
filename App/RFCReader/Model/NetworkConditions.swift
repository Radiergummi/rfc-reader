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

  /// Starts watching. `pathChanged` is called on every update of the path, even one
  /// that reads the same, as a move to another Wi-Fi network does; `powerChanged`
  /// when Low Power Mode is turned on or off.
  func start(
    pathChanged: @escaping @MainActor @Sendable () -> Void,
    powerChanged: @escaping @MainActor @Sendable () -> Void
  ) {
    // On the main queue, so the updates arrive in the order they were made.
    monitor.pathUpdateHandler = { [weak self] path in
      MainActor.assumeIsolated {
        self?.path = Self.policyPath(of: path)
        pathChanged()
      }
    }
    monitor.start(queue: .main)
    powerChanges = NotificationCenter.default.addObserver(
      forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard isLowPower != self.isLowPower else { return }
        self.isLowPower = isLowPower
        powerChanged()
      }
    }
  }

  /// Whether a fetch for `cause` goes ahead now: nil until the path is known.
  func decision(for cause: FetchPolicy.Cause) -> FetchPolicy.Decision? {
    path.map { FetchPolicy.decide(cause: cause, path: $0, lowPower: isLowPower) }
  }

  private static func policyPath(of path: NWPath) -> FetchPolicy.Path {
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
