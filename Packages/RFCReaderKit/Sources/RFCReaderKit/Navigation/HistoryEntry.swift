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

  public let id: DocumentID
  public var section: String?
  public let arrival: Arrival

  public init(id: DocumentID, section: String? = nil, arrival: Arrival = .root) {
    self.id = id
    self.section = section
    self.arrival = arrival
  }

  private enum CodingKeys: String, CodingKey {
    case id, section, arrival
  }

  /// A place kept before arrivals were (#263) was arrived at from outside, as far
  /// as anyone can tell: its tab comes back with one reader.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(DocumentID.self, forKey: .id)
    section = try container.decodeIfPresent(String.self, forKey: .section)
    arrival = try container.decodeIfPresent(Arrival.self, forKey: .arrival) ?? .root
  }
}
