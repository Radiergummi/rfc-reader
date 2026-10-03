import CoreSpotlight
import CryptoKit
import Foundation
import RFCKit

/// What system search knows about an RFC (#178): one item per RFC in the index,
/// which the app turns into a `CSSearchableItem`.
///
/// Plain data, so what is indexed is decided here, under test, and the app only
/// hands it to CoreSpotlight. Obsoleted RFCs are indexed too: people look them up
/// by number, and the description says what replaced them.
public struct SpotlightEntry: Sendable {
  /// The domain every RFC is indexed under, so the set can be replaced as a whole.
  public static let domain = "rfc-index"

  /// The document's file stem, `rfc9110`, which is how a chosen result comes back.
  public var identifier: String
  /// `RFC 9110: HTTP Semantics`.
  public var title: String
  /// The abstract, after "Obsoleted by RFC …." where it applies.
  public var description: String
  /// The number as it is written (`9110`, `RFC 9110`, `RFC9110`), the working group,
  /// the authors and the index's keywords.
  public var keywords: [String]

  public init(_ metadata: RFCMetadata) {
    let id = metadata.id
    identifier = id.fileStem
    title = "\(id.displayName): \(metadata.title)"
    var description = metadata.abstract ?? ""
    if let note = metadata.obsoletionNote {
      description = "\(note). \(description)".trimmingCharacters(in: .whitespaces)
    }
    self.description = description
    keywords =
      ["\(id.number)", id.displayName, id.description]
      + [metadata.namedWorkingGroup].compactMap { $0 }
      + metadata.authors.map(\.name)
      + metadata.keywords
  }

  /// How long an item stays in Spotlight unless it is indexed again: long enough to
  /// outlive two weekly renewals, so an RFC that has left the index goes eventually
  /// without anything having to delete it.
  public static let lifetime: TimeInterval = 30 * 86_400

  /// What the Spotlight index remembers of the last indexing, which is skipped when
  /// it is unchanged: a digest of the entries, and the week they were indexed in.
  /// The digest is of what is indexed, not of when the index arrived, so a refresh
  /// that brings the same index, or an app update's bundled one, is told apart by
  /// its content alone. The week is there so an index that never changes, on a Mac
  /// that stays offline, is still renewed before its items reach their `lifetime`.
  public static func clientState(for entries: [SpotlightEntry], now: Date) -> Data {
    var digest = SHA256()
    // Each field ends with a unit separator and each entry with a record
    // separator, so text moved from one field into the next is a change.
    for entry in entries {
      for field in [entry.identifier, entry.title, entry.description] + entry.keywords {
        digest.update(data: Data(field.utf8))
        digest.update(data: Data([0x1F]))
      }
      digest.update(data: Data([0x1E]))
    }
    return Data(digest.finalize()) + Data(" \(week(of: now))".utf8)
  }

  /// Whether an activation should check the index again (#178): when the week has
  /// turned since the last check, so an app left running renews its items before
  /// they reach their `lifetime`. Within the week the client state could not have
  /// changed without a new index, which checks by itself.
  public static func isRecheckDue(lastCheckedAt: Date, now: Date) -> Bool {
    week(of: now) != week(of: lastCheckedAt)
  }

  private static func week(of date: Date) -> Int {
    Int(date.timeIntervalSince1970) / (7 * 86_400)
  }

  /// The document a chosen Spotlight result names, or nil for an activity that is
  /// not one, or an identifier this app did not index.
  public static func documentID(from activity: NSUserActivity) -> DocumentID? {
    guard activity.activityType == CSSearchableItemActionType,
      let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    else { return nil }
    return DocumentID(fileStem: identifier)
  }
}
