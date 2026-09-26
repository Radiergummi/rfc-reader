import Foundation

/// Every anchor in a built document, sorted by character offset.
///
/// Anchors are the reader's only stable handle on a position: deep links, the table
/// of contents and reading positions all key off them, and the index is what turns
/// one into a text location and back.
public struct AnchorIndex: Sendable, Equatable {
  public struct Entry: Sendable, Equatable {
    public let anchor: String
    public let offset: Int
    /// A section's heading as the reader draws it, which is what an in-document
    /// reference's preview names; nil for any other anchor. Only a section has
    /// one, which the builder knows and nothing downstream can tell by looking.
    /// See `DocumentTextBuilder.mark`.
    public let heading: String?

    /// True when the anchor names a `Section`. Derived from `heading`, so the
    /// two cannot disagree: a section without a heading would have no card.
    public var isSection: Bool {
      heading != nil
    }

    public init(anchor: String, offset: Int, heading: String? = nil) {
      self.anchor = anchor
      self.offset = offset
      self.heading = heading
    }
  }

  public let entries: [Entry]
  private let offsets: [String: Int]
  private let headings: [String: String]

  public init(_ entries: [Entry]) {
    let sorted = entries.sorted { $0.offset < $1.offset }
    self.entries = sorted
    self.offsets = Dictionary(
      sorted.map { ($0.anchor, $0.offset) }, uniquingKeysWith: { first, _ in first })
    self.headings = Dictionary(
      sorted.compactMap { entry in entry.heading.map { (entry.anchor, $0) } },
      uniquingKeysWith: { first, _ in first })
  }

  /// Just the section anchors, as an index of their own: what section tracking
  /// hit-tests against.
  public var sections: AnchorIndex {
    AnchorIndex(entries.filter(\.isSection))
  }

  public func offset(of anchor: String) -> Int? {
    offsets[anchor]
  }

  /// The heading of the section this anchor names, or nil when it names anything
  /// else — a figure, a table, a paragraph.
  public func heading(of anchor: String) -> String? {
    headings[anchor]
  }

  /// The anchor covering `offset`: the last entry at or before it, or nil if the
  /// offset falls ahead of the first anchor.
  public func anchor(at offset: Int) -> String? {
    var low = 0
    var high = entries.count
    while low < high {
      let middle = (low + high) / 2
      if entries[middle].offset <= offset { low = middle + 1 } else { high = middle }
    }
    return low > 0 ? entries[low - 1].anchor : nil
  }
}
