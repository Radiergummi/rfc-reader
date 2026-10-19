import RFCKit

/// What an open does in a tab: jump within the document on screen, or go to a new
/// place in the history.
public enum OpenRoute: Equatable, Sendable {
  /// A place in the document on screen, handed to the reader, which resolves it:
  /// an anchor may name nothing in its body, as the RFC Editor's `#page-12`
  /// doesn't, or an entry the reader shows rather than scrolls to (#276), and only
  /// the reader can tell a section's number from its anchor (#482).
  case jump(place: String, reveals: Bool)
  /// Anywhere else: a new entry in the history.
  case navigate(HistoryEntry)

  /// The route for `link`, in a tab with `selected` in its list and `shown` in its
  /// reader: the RFC a selected BCP, STD or FYI shows is in the reader too (#656).
  /// `arrival` is how a new entry is arrived at.
  public static func route(
    _ link: RFCLink, arrival: HistoryEntry.Arrival = .root, selected: DocumentID?,
    shown: DocumentID?
  ) -> Self {
    route(
      .rfc(link), arrival: arrival, selected: selected.map(ReadableDocument.rfc),
      shown: shown.map(ReadableDocument.rfc))
  }

  /// The route for `link`, to an RFC or a draft (#728), in a tab with `selected` and
  /// `shown` as above: a draft is both, having no series to show a member of.
  public static func route(
    _ link: ReadableLink, arrival: HistoryEntry.Arrival = .root, selected: ReadableDocument?,
    shown: ReadableDocument?
  ) -> Self {
    if let place = link.place, link.document == selected || link.document == shown {
      // A section of an RFC reveals its row; a draft has none.
      let reveals = if case .rfc(let link) = link { link.section != nil } else { false }
      return .jump(place: place, reveals: reveals)
    }
    return .navigate(HistoryEntry(document: link.document, section: link.place, arrival: arrival))
  }

  /// Whether an open reveals the document in the list, setting the sidebar to All,
  /// since a narrowed filter may be hiding it. Every open of an RFC does, but a jump
  /// to an anchor, which leaves the list as it is; no open of a draft does, a draft
  /// having no row (#728).
  public var reveals: Bool {
    switch self {
    case .jump(_, let reveals): reveals
    case .navigate(let entry): entry.id != nil
    }
  }

  /// Whether the open has to change the list to show its document's row: only
  /// where the route reveals at all, and the row is not among `shown`, the rows on
  /// show, or there are none yet. Revealing then clears whatever can hide a row,
  /// the filter, the search and the obsolete option alike (#769); a list that
  /// already shows it is the reader's, and stays as it is.
  public func reveals(selected: DocumentID?, among shown: [DocumentID]?) -> Bool {
    guard reveals else { return false }
    guard let row = row(selected: selected), let shown else { return true }
    return !shown.contains(row)
  }

  /// The row the open asks the list for, with `selected` the row the list has
  /// selected: a jump stays in the document on screen, whose row that is, which may
  /// be the BCP, STD or FYI it is a member of; a navigation goes to its entry's.
  public func row(selected: DocumentID?) -> DocumentID? {
    switch self {
    case .jump: selected
    case .navigate(let entry): entry.id
    }
  }
}
