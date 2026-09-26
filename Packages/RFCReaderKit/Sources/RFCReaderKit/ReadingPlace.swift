import Foundation

/// A character position that survives a rebuild: the nearest anchor at or before
/// it, of any kind, and how far past that anchor it is.
///
/// A rebuild — a resize changes the column, and the column is a build input —
/// produces a new storage in which every character offset has moved, so an offset
/// cannot be carried across one. An anchor can, and the text of a block mostly does
/// not depend on the measure, so "this many characters into that paragraph" names
/// the same line in both. The exception is a table, which grids at a wide measure
/// and stacks at a narrow one, so its text changes shape and length; a place inside
/// one lands somewhere in the same table, which `documentOffset` keeps it inside. A
/// section anchor alone is too coarse: it restores to the heading, which in a long
/// section is screens away from where the reader was.
public struct ReadingPlace: Sendable, Equatable {
  /// Nil ahead of the first anchor, where `offset` counts from the document start.
  public let anchor: String?
  public let offset: Int

  public init(anchor: String?, offset: Int) {
    self.anchor = anchor
    self.offset = offset
  }

  public init(at documentOffset: Int, in index: AnchorIndex) {
    let anchor = index.anchor(at: documentOffset)
    self.anchor = anchor
    self.offset = documentOffset - (anchor.flatMap(index.offset(of:)) ?? 0)
  }

  /// Where this place is in the document `index` describes, or nil if its anchor
  /// is not in it. Clamped to the anchor's own block: a block that came back
  /// shorter — a table re-shaped for another column — must not push the place
  /// into whatever follows it.
  public func documentOffset(in index: AnchorIndex, length: Int) -> Int? {
    let start: Int
    if let anchor {
      guard let found = index.offset(of: anchor) else { return nil }
      start = found
    } else {
      start = 0
    }
    let end = index.firstOffset(after: start) ?? length
    return max(start, min(start + offset, end - 1))
  }

  /// The place to record when `topLine` is the line at the top of the viewport:
  /// `previous`, while that line still holds it, and otherwise the line's start.
  ///
  /// A restore puts the line *holding* a place at the top, and that line starts
  /// earlier than the place whenever the new column wraps somewhere else. Recording
  /// the line's start again would walk the place back a little on every rebuild —
  /// and a live resize rebuilds many times. Only reaching another line moves it.
  public static func tracking(
    _ previous: Self?, topLine: NSRange, in index: AnchorIndex, length: Int
  ) -> Self {
    if let previous,
      let offset = previous.documentOffset(in: index, length: length),
      offset == topLine.location || NSLocationInRange(offset, topLine)
    {
      return previous
    }
    return ReadingPlace(at: topLine.location, in: index)
  }
}

extension AnchorIndex {
  /// The first anchor's offset strictly after `offset`: where the block starting
  /// there ends. A binary search, like `anchor(at:)`, because tracking runs it on
  /// every scroll report.
  fileprivate func firstOffset(after offset: Int) -> Int? {
    var low = 0
    var high = entries.count
    while low < high {
      let middle = (low + high) / 2
      if entries[middle].offset <= offset { low = middle + 1 } else { high = middle }
    }
    return low < entries.count ? entries[low].offset : nil
  }
}
