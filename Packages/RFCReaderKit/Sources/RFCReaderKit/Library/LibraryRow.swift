import Foundation
import RFCKit

/// One row of a library list: an RFC, or a BCP, STD or FYI that the reader
/// bookmarked or read as itself (#321).
///
/// A series has no entry of its own in the index, only the RFCs it names, so its
/// row is made of those: titled by the first, dated by the newest. Only Bookmarks
/// and Recently Read ever list one; every other list is of RFCs.
public enum LibraryRow: Hashable, Sendable, Identifiable {
  case rfc(RFCMetadata)
  /// The series' members the index knows, in the series' order. Never empty.
  case series(DocumentID, members: [RFCMetadata])

  /// The row for `id`, or nil when the index knows neither it nor, for a series,
  /// any RFC it names.
  public init?(_ id: DocumentID, in index: RFCIndex) {
    if id.series == .rfc {
      guard let rfc = index[id] else { return nil }
      self = .rfc(rfc)
      return
    }
    let members = index.series(id)?.members.compactMap { index[$0] } ?? []
    guard !members.isEmpty else { return nil }
    self = .series(id, members: members)
  }

  /// The document the row opens, as it was bookmarked or read.
  public var id: DocumentID {
    switch self {
    case .rfc(let rfc): rfc.id
    case .series(let id, _): id
    }
  }

  /// The RFCs the row stands for: its own, or the series'.
  public var members: [RFCMetadata] {
    switch self {
    case .rfc(let rfc): [rfc]
    case .series(_, let members): members
    }
  }

  /// The series has no title in the index, so its first member's stands for it.
  public var title: String {
    members[0].title
  }

  /// The series is as old as its newest member, which is what it says today.
  public var date: PublicationDate {
    newest.date
  }

  /// Obsolescence belongs to a member, not to the series that names it.
  public var isObsolete: Bool {
    switch self {
    case .rfc(let rfc): rfc.isObsolete
    case .series: false
    }
  }

  /// "RFC 2119, RFC 8174": what a series row says under its title. Nil for an RFC.
  public var memberList: String? {
    guard case .series(_, let members) = self else { return nil }
    return members.map(\.id.displayName).joined(separator: ", ")
  }

  /// Newest first: by date, then by number, a series by its newest member's, and
  /// then by the document, so a series and its newest member have an order too.
  static func isNewer(_ lhs: LibraryRow, than rhs: LibraryRow) -> Bool {
    (lhs.date, lhs.newest.number, lhs.id) > (rhs.date, rhs.newest.number, rhs.id)
  }

  private var newest: RFCMetadata {
    members.max { ($0.date, $0.number) < ($1.date, $1.number) } ?? members[0]
  }
}
