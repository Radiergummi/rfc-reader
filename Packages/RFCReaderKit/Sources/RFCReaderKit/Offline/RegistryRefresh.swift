import Foundation
import RFCKit

/// Which registries are fetched when they are due (#175), and on which networks.
///
/// A registry already kept answers lookups while it is refreshed, so the refresh is
/// a fetch nobody is waiting for, and waits for a network that is neither metered
/// nor in Low Data Mode, like the daily index check (#314). One never fetched has
/// nothing to answer with, and takes any network. The fetches run one at a time,
/// so the first fetches go first: a refresh waiting for a cheap network would
/// otherwise hold them back.
public enum RegistryRefresh {
  /// Registries change more often than RFCs, but not by the day.
  public static let maximumAge: TimeInterval = 7 * 86_400

  /// Whether registries last checked at `checkedAt` are due a check at `now`: the
  /// palette asks as it opens, since the app may stay open for weeks after the
  /// check at launch.
  public static func isDue(checkedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(checkedAt) > maximumAge
  }

  public struct Fetch: Hashable, Sendable {
    public let registry: IANARegistry
    public let onExpensiveNetworks: Bool
  }

  /// - Parameters:
  ///   - stale: The registries due a fetch.
  ///   - cached: The registries whose kept entries could be read.
  public static func fetches(stale: [IANARegistry], cached: Set<IANARegistry>) -> [Fetch] {
    let first = stale.filter { !cached.contains($0) }
    let refreshes = stale.filter { cached.contains($0) }
    return first.map { Fetch(registry: $0, onExpensiveNetworks: true) }
      + refreshes.map { Fetch(registry: $0, onExpensiveNetworks: false) }
  }
}
