import RFCKit

/// What an open does in a tab: jump within the document on screen, or go to a new
/// place in the history.
public enum OpenRoute: Equatable, Sendable {
  /// A place in the document on screen, handed to the reader, which resolves it:
  /// an anchor may name nothing in its body, as the RFC Editor's `#page-12`
  /// doesn't, or an entry the reader shows rather than scrolls to (#276), and only
  /// the reader can tell a section's number from its anchor (#482).
  case jump(to: String)
  /// Anywhere else: a new entry in the history.
  case go(to: HistoryEntry)

  /// The route for `link`, in a tab with `selected` in its list and `shown` in its
  /// reader: the RFC a selected BCP, STD or FYI shows is in the reader too (#656).
  /// `arrival` is how a new entry is arrived at.
  public static func route(
    _ link: RFCLink, arrival: HistoryEntry.Arrival = .root, selected: DocumentID?,
    shown: DocumentID?
  ) -> Self {
    if let place = link.place, link.id == selected || link.id == shown {
      return .jump(to: place)
    }
    return .go(to: HistoryEntry(id: link.id, section: link.place, arrival: arrival))
  }
}
