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
