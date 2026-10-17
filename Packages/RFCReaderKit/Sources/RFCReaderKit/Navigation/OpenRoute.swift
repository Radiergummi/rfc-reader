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
    if let place = link.place, link.id == selected || link.id == shown {
      return .jump(place: place, reveals: link.section != nil)
    }
    return .navigate(HistoryEntry(id: link.id, section: link.place, arrival: arrival))
  }

  /// Whether an open reveals the document in the list, setting the sidebar to All,
  /// since a narrowed filter may be hiding it. Every open does, but a jump to an
  /// anchor, which leaves the list as it is.
  public var reveals: Bool {
    switch self {
    case .jump(_, let reveals): reveals
    case .navigate: true
    }
  }

  /// Whether the open has to change the list to show its document's row: only
  /// where the route reveals at all, and the row is not among `shown`, the rows on
  /// show, or there are none yet. Revealing then clears whatever can hide a row,
  /// the filter, the search and the obsolete option alike (#769); a list that
  /// already shows it is the reader's, and stays as it is.
  ///
  /// A jump stays in the document on screen, whose row is `selected`; a navigation
  /// goes to its entry's.
  public func reveals(selected: DocumentID?, among shown: [DocumentID]?) -> Bool {
    guard reveals else { return false }
    let row: DocumentID? =
      switch self {
      case .jump: selected
      case .navigate(let entry): entry.id
      }
    guard let row, let shown else { return true }
    return !shown.contains(row)
  }
}
