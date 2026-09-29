import RFCKit

/// One step of a tab's navigation history: somewhere the reader can be, a document
/// and optionally a spot inside it.
///
/// The spot is an anchor or a section number — whatever `DocumentView` can hand to
/// `scroll(to:)`. It serves two purposes at once: on the way in it is the deep link's
/// target section, and on the way out it is where the reader had scrolled to, so
/// coming back does not dump them at the top of a 200-page RFC.
public struct HistoryEntry: Hashable, Sendable {
  public let id: DocumentID
  public var section: String?

  public init(id: DocumentID, section: String? = nil) {
    self.id = id
    self.section = section
  }
}
