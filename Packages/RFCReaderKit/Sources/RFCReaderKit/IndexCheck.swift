import Foundation
import RFCKit

/// When the index was last checked against the RFC Editor's, and what identified
/// the copy kept, so the next check asks only whether it changed (#314).
///
/// Kept beside the index rather than read from the index file's date, because a
/// check that finds nothing new writes nothing else: the date the list shows is
/// when the index was known to be current, not when it last changed.
public struct IndexCheck: Codable, Sendable, Hashable {
  public var checkedAt: Date
  public var validators: CacheValidators?

  public init(checkedAt: Date, validators: CacheValidators?) {
    self.checkedAt = checkedAt
    self.validators = validators
  }

  /// How long an index is taken as current before a launch checks it again.
  public static let interval: TimeInterval = 86_400

  /// Whether an index last checked at `checkedAt` is due for a check at `now`.
  public static func isDue(checkedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(checkedAt) > interval
  }
}
