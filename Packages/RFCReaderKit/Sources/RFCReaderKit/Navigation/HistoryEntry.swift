import RFCKit

/// One step of a tab's navigation history: somewhere the reader can be, a document
/// and optionally a spot inside it.
///
/// The spot is an anchor or a section number — whatever `DocumentView` can hand to
/// `scroll(to:)`. It serves two purposes at once: on the way in it is the deep link's
/// target section, and on the way out it is where the reader had scrolled to, so
/// coming back does not dump them at the top of a 200-page RFC.
public struct HistoryEntry: Hashable, Sendable, Codable {
  /// How the tab came to a place, which decides the readers stacked for it on iOS
  /// (#263, `ReaderPath`).
  public enum Arrival: String, Hashable, Sendable, Codable {
    /// From outside the reader: a row in the list, a link from another app, Go to
    /// RFC. The readers are stacked again from here.
    case root
    /// By a link followed inside the reader: a citation of another RFC, which
    /// pushes a reader, or a jump within the document, which does not.
    case citation
  }

  /// The document: an RFC, or a draft's revision (#728).
  public let document: ReadableDocument
  public var section: String?
  public let arrival: Arrival

  public init(document: ReadableDocument, section: String? = nil, arrival: Arrival = .root) {
    self.document = document
    self.section = section
    self.arrival = arrival
  }

  public init(id: DocumentID, section: String? = nil, arrival: Arrival = .root) {
    self.init(document: .rfc(id), section: section, arrival: arrival)
  }

  /// The RFC, BCP, STD or FYI, unless the place is in a draft, which has no row in
  /// the list and no index entry.
  public var id: DocumentID? { document.rfc }
}
