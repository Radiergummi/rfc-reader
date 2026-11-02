import Foundation

/// When the data files beside the index are fetched again: the revisions and the
/// working groups once a day per launch (#363), the errata once a day as the index
/// is (#314, #387).
public enum DataFileCheck {
  /// Whether a file this launch last fetched at `fetchedAt`, nil when it has not,
  /// is due at `now`: once `IndexCheck.interval` has passed.
  public static func isDue(fetchedAt: Date?, now: Date) -> Bool {
    guard let fetchedAt else { return true }
    return now.timeIntervalSince(fetchedAt) >= IndexCheck.interval
  }

  /// Which networks a fetch of the revisions or the working groups may take, when
  /// one is due (#758).
  public enum Fetch: Sendable, Equatable {
    /// Nothing is kept to show meanwhile, so the fetch takes any network.
    case anyNetwork
    /// A copy is kept and answers meanwhile, so nobody waits for the refresh, which
    /// waits for a network that is neither metered nor in Low Data Mode (#314).
    case cheapNetworks
  }

  /// Whether the revisions or the working groups are due a fetch at `now`, and on
  /// which networks: once `IndexCheck.interval` has passed since the copy kept was
  /// written, which a new launch remembers, and since this run last fetched it.
  ///
  /// - Parameters:
  ///   - keptAt: When the copy kept was written, nil when none can be read.
  ///   - fetchedAt: When this run last fetched it, nil when it has not: what stops a
  ///     fetch whose copy could not be kept from being made at every activation.
  public static func fetch(keptAt: Date?, fetchedAt: Date?, now: Date) -> Fetch? {
    for date in [keptAt, fetchedAt].compactMap(\.self) where !isDue(fetchedAt: date, now: now) {
      return nil
    }
    return keptAt == nil ? .anyNetwork : .cheapNetworks
  }

  /// Whether the errata feed is due at `now`.
  ///
  /// - Parameters:
  ///   - keptCheckedAt: When the feed kept was last checked, nil when none is kept
  ///     or none is in memory.
  ///   - askedAt: When this run last had an answer from the RFC Editor for the feed,
  ///     whatever came of it: a feed that fails to decode or to be kept records no
  ///     check, and would otherwise be downloaded again at every activation.
  public static func isErrataDue(keptCheckedAt: Date?, askedAt: Date?, now: Date) -> Bool {
    if let keptCheckedAt, !IndexCheck.isDue(checkedAt: keptCheckedAt, now: now) { return false }
    if let askedAt, !IndexCheck.isDue(checkedAt: askedAt, now: now) { return false }
    return true
  }
}
