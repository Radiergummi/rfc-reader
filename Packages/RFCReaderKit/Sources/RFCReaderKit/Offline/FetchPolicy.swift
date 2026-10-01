import Foundation

/// Whether a document's body is fetched now, on the path the device has, or waits
/// for a better one (#358).
///
/// `docs/VISION.md` holds the app to being kind to metered and poor connections. A
/// fetch somebody is waiting for goes ahead on any path, as an open always has: the
/// reader asked for it, and one that cannot succeed fails in front of them. A fetch
/// nobody waits for — a mark synced from another device, the bookmark setting turned
/// on — goes ahead only on a path that is neither expensive nor constrained, and not
/// in Low Power Mode; otherwise it waits, and says what for.
///
/// Pure, over a description of the path rather than `NWPath`, so the whole table is
/// tested here; the App target reads `NWPathMonitor` and `ProcessInfo` into it.
public enum FetchPolicy {
  /// Why a body is being fetched.
  public enum Cause: Sendable, Hashable, CaseIterable {
    /// A reader opened the document.
    case open
    /// A reader asked again after a failure.
    case retry
    /// Keep Offline, tapped on this device.
    case keepOfflineTap
    /// Download Now, on a row that was waiting.
    case downloadNow
    /// A Keep Offline mark that arrived from another device.
    case syncedMark
    /// "Keep bookmarked documents offline", turned on.
    case bookmarkSetting

    /// Whether somebody is waiting for the fetch, on this device, now.
    public var isAwaited: Bool {
      switch self {
      case .open, .retry, .keepOfflineTap, .downloadNow: true
      case .syncedMark, .bookmarkSetting: false
      }
    }
  }

  /// `NWPath`'s status, with the one unsatisfied reason worth naming.
  public enum PathStatus: Sendable, Hashable {
    case satisfied
    case unsatisfied
    /// Unsatisfied because iOS's per-app cellular switch is off for the app.
    case cellularDenied
  }

  /// What the policy needs to know of the network path: its status and its cost.
  public struct Path: Sendable, Hashable {
    public var status: PathStatus
    /// Cellular, or a hotspot: `NWPath.isExpensive`.
    public var isExpensive: Bool
    /// Low Data Mode: `NWPath.isConstrained`.
    public var isConstrained: Bool

    public init(status: PathStatus, isExpensive: Bool = false, isConstrained: Bool = false) {
      self.status = status
      self.isExpensive = isExpensive
      self.isConstrained = isConstrained
    }
  }

  /// Why a discretionary fetch waits, which its row says.
  public enum Reason: Sendable, Hashable {
    case offline
    case cellularDenied
    case lowDataMode
    case waitingForWiFi
    case lowPowerMode
  }

  public enum Decision: Sendable, Hashable {
    case fetch
    case deferred(Reason)
  }

  /// Whether a fetch for `cause` goes ahead on `path`. A deferral names the first
  /// reason that holds: no network, then the per-app switch, then what the path
  /// costs — Low Data Mode first, being a setting the reader chose — then the
  /// device's power.
  public static func decide(cause: Cause, path: Path, lowPower: Bool) -> Decision {
    guard !cause.isAwaited else { return .fetch }
    switch path.status {
    case .unsatisfied: return .deferred(.offline)
    case .cellularDenied: return .deferred(.cellularDenied)
    case .satisfied: break
    }
    if path.isConstrained { return .deferred(.lowDataMode) }
    if path.isExpensive { return .deferred(.waitingForWiFi) }
    if lowPower { return .deferred(.lowPowerMode) }
    return .fetch
  }
}
