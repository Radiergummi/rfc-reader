import Foundation

/// Where rows sit in a collection, and collections in the sidebar (#349).
///
/// Positions are `Double`s so a move takes the midpoint of its new neighbours and
/// writes one row. Halving a gap runs out eventually, and two devices appending
/// offline can land on one position; both call for renumbering first.
public enum CollectionOrder {
  /// The gap between neighbours after appending or renumbering.
  public static let spacing: Double = 1

  /// Narrower than this, a gap is not split: the rows are renumbered first.
  public static let minimumGap: Double = 1e-9

  public enum Placement: Equatable, Sendable {
    case position(Double)
    case renumberFirst
  }

  /// One spacing after the last position, or the first position when there is none.
  public static func appending(after last: Double?) -> Double {
    (last ?? 0) + spacing
  }

  /// Between two neighbours, either of which may be missing at an end.
  public static func placement(between before: Double?, and after: Double?) -> Placement {
    switch (before, after) {
    case (nil, nil):
      .position(spacing)
    case (let before?, nil):
      .position(before + spacing)
    case (nil, let after?):
      .position(after - spacing)
    case (let before?, let after?):
      after - before > minimumGap ? .position((before + after) / 2) : .renumberFirst
    }
  }

  /// Evenly spaced positions for `count` rows, in the order they already have.
  public static func renumbered(count: Int) -> [Double] {
    (0..<count).map { Double($0 + 1) * spacing }
  }

  /// Where a row moved in a *visible* list goes in the full one.
  ///
  /// The visible list may hide obsolete documents, or hold only the rows paged in
  /// so far, so a move is never resolved by offset. `above` and `below` are the
  /// visible rows either side of the drop point; `full` is every row but the moved
  /// one, in order. The row goes right after `above` where there is one, otherwise
  /// right before `below`.
  public static func neighbours<Key: Equatable>(
    above: Key?, below: Key?, in full: [Key]
  ) -> (before: Key?, after: Key?) {
    if let above, let index = full.firstIndex(of: above) {
      let next = full.index(after: index)
      return (above, next < full.endIndex ? full[next] : nil)
    }
    if let below, let index = full.firstIndex(of: below) {
      return (index > full.startIndex ? full[full.index(before: index)] : nil, below)
    }
    return (nil, full.first)
  }
}
