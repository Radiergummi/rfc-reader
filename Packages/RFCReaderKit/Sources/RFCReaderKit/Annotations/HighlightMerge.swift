import Foundation

/// What a new highlight does to those it overlaps (#522): it merges with every one of
/// them into one highlight covering all their ranges, in the new color. The oldest
/// survives, keeping its identity and when it was made; the others are absorbed. A
/// highlight that only touches another, ending where it starts, is not merged.
public enum HighlightMerge {
  /// An existing highlight, where it is in the model text now.
  public struct Existing: Sendable, Equatable {
    public let identifier: UUID
    public let range: Range<Int>
    public let createdAt: Date

    public init(identifier: UUID, range: Range<Int>, createdAt: Date) {
      self.identifier = identifier
      self.range = range
      self.createdAt = createdAt
    }
  }

  public struct Plan: Sendable, Equatable {
    /// The highlight that becomes the merged one, or nil when nothing overlaps and a
    /// new one is made.
    public let survivor: UUID?
    /// The highlights merged into the survivor, which go.
    public let absorbed: [UUID]
    /// What the highlight covers afterwards.
    public let range: Range<Int>
  }

  public static func plan(adding range: Range<Int>, to existing: [Existing]) -> Plan {
    var covered = range
    var merged: [Existing] = []
    var remaining = existing
    // Until nothing more overlaps: a merged range can reach one the new range alone
    // did not.
    while let index = remaining.firstIndex(where: { $0.range.overlaps(covered) }) {
      let next = remaining.remove(at: index)
      merged.append(next)
      let lower = min(covered.lowerBound, next.range.lowerBound)
      let upper = max(covered.upperBound, next.range.upperBound)
      covered = lower..<upper
    }
    let ordered = merged.sorted {
      ($0.createdAt, $0.identifier.uuidString) < ($1.createdAt, $1.identifier.uuidString)
    }
    return Plan(
      survivor: ordered.first?.identifier, absorbed: ordered.dropFirst().map(\.identifier),
      range: covered)
  }
}
