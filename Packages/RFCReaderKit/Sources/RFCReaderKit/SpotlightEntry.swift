import Foundation
import RFCKit

/// What system search knows about an RFC (#178): one item per RFC in the index,
/// which the app turns into a `CSSearchableItem`.
///
/// Plain data, so what is indexed is decided here, under test, and the app only
/// hands it to CoreSpotlight. Obsoleted RFCs are indexed too: people look them up
/// by number, and the description says what replaced them.
public struct SpotlightEntry: Equatable, Sendable {
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
    if metadata.isObsolete {
      let successors = metadata.obsoletedBy.map(\.displayName).joined(separator: ", ")
      description = "Obsoleted by \(successors). \(description)"
        .trimmingCharacters(in: .whitespaces)
    }
    self.description = description
    keywords =
      ["\(id.number)", id.displayName, id.displayName.replacingOccurrences(of: " ", with: "")]
      + [metadata.workingGroup].compactMap { $0 }
      + metadata.authors.map(\.name)
      + metadata.keywords
  }

  /// How long an item stays in Spotlight unless it is indexed again: long enough to
  /// outlive two weekly renewals, so an RFC that has left the index goes eventually
  /// without anything having to delete it.
  public static let lifetime: TimeInterval = 30 * 86_400

  /// What the Spotlight index remembers of the last indexing, which is skipped when
  /// it is unchanged: the RFC index's date, and the week it was indexed in. The
  /// week is there so an index that never changes, on a Mac that stays offline, is
  /// still renewed before its items reach their `lifetime`.
  public static func clientState(indexUpdatedAt: Date, now: Date) -> Data {
    let week = Int(now.timeIntervalSince1970) / (7 * 86_400)
    return Data("\(Int(indexUpdatedAt.timeIntervalSince1970)) \(week)".utf8)
  }

  /// The document a chosen result names, or nil for an identifier this app did not
  /// index.
  public static func documentID(fromIdentifier identifier: String) -> DocumentID? {
    DocumentID(fileStem: identifier)
  }
}
