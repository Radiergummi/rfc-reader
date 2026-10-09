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
  /// When the index kept was downloaded, and its validators with it. A check that
  /// finds it unchanged moves `checkedAt`, never this.
  public var fetchedAt: Date
  public var validators: CacheValidators?

  public init(checkedAt: Date, fetchedAt: Date, validators: CacheValidators?) {
    self.checkedAt = checkedAt
    self.fetchedAt = fetchedAt
    self.validators = validators
  }

  /// How long an index is taken as current before a launch checks it again.
  public static let interval: TimeInterval = 86_400

  /// Whether an index last checked at `checkedAt` is due for a check at `now`.
  public static func isDue(checkedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(checkedAt) > interval
  }

  /// How long the validators of a downloaded index are sent before a check asks
  /// for the whole index again. The RFC Editor sends only an `ETag`; were it to
  /// stay the same while the index changes, every check would answer `304`, and
  /// the list would say it was current while missing new RFCs.
  public static let validatorLifetime: TimeInterval = 7 * 86_400

  /// The validators a check at `now` sends, or nil when the index kept was fetched
  /// more than `validatorLifetime` ago and the check should fetch it whole.
  public func validators(at now: Date) -> CacheValidators? {
    now.timeIntervalSince(fetchedAt) > Self.validatorLifetime ? nil : validators
  }
}
