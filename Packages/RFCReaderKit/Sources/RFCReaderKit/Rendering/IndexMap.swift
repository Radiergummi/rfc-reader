import Foundation

/// Where a built document's index is: its groups' letters and its top-level entries'
/// terms, as UTF-16 ranges of the built text. Recorded by the builder as it sets the
/// index, so the overlays over it (the pinned letter, the A–Z rail, type-select) read
/// it rather than searching the text. Empty for a document without an index.
public struct IndexMap: Sendable, Equatable {
  public struct Group: Sendable, Equatable {
    public let label: String
    public let anchor: String
    public let labelRange: NSRange
  }

  /// A top-level entry: subentries are sorted under their heading entry, not across
  /// the index, so they have no place in type-select's order.
  public struct Entry: Sendable, Equatable {
    /// The term as type-select matches it (`key(_:)`).
    public let key: String
    public let termRange: NSRange
  }

  /// From the first group's letter to the end of the last entry.
  public let range: NSRange
  public let groups: [Group]
  public let entries: [Entry]

  public static let empty = IndexMap(
    range: NSRange(location: NSNotFound, length: 0), groups: [], entries: [])

  public var isEmpty: Bool { groups.isEmpty }

  /// `text` as type-select compares it: case and diacritics folded, so `é` is `e`.
  public static func key(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
