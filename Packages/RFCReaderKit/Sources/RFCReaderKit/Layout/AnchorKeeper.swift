import CoreGraphics
import Foundation

/// The reader's place under viewport layout, which only the reader moves.
///
/// A scroll the reader makes records the line at the top. A move the engine makes —
/// a pin, a slice landing, a correction of the height — happens between
/// `beginEngineMove()` and `endEngineMove()`, and the scrolls it causes record
/// nothing. That one rule replaces `ReadingPlaceTracker`'s pausing around a
/// rebuild: the engine never records its own moves, so there is nothing to pause.
public struct AnchorKeeper: Sendable, Equatable {
  public enum Place: Sendable, Equatable {
    /// Above the text, where the header is.
    case top
    case line(ReaderAnchor)
  }

  /// The place as it crosses a rebuild, which moves every character offset.
  public enum Carried: Sendable, Equatable {
    case top
    case line(ReadingPlace, fraction: CGFloat)
  }

  public private(set) var place: Place = .top
  private var engineMoves = 0

  public init() {}

  public var isEngineMoving: Bool { engineMoves > 0 }

  public mutating func beginEngineMove() {
    engineMoves += 1
  }

  public mutating func endEngineMove() {
    engineMoves = max(0, engineMoves - 1)
  }

  /// The reader scrolled: `line` is at the top, `anchor` names it. While that line
  /// still holds the character the place names, the character is kept.
  public mutating func userScrolled(to anchor: ReaderAnchor, line: NSRange) {
    guard !isEngineMoving else { return }
    if case .line(let previous) = place,
      previous.characterOffset == line.location || NSLocationInRange(previous.characterOffset, line)
    {
      place = .line(
        ReaderAnchor(characterOffset: previous.characterOffset, fraction: anchor.fraction))
      return
    }
    place = .line(anchor)
  }

  public mutating func userScrolledAboveText() {
    guard !isEngineMoving else { return }
    place = .top
  }

  /// A jump names the place directly, even during an engine move.
  public mutating func jumped(to anchor: ReaderAnchor) {
    place = .line(anchor)
  }

  public func carried(in index: AnchorIndex) -> Carried {
    switch place {
    case .top: .top
    case .line(let anchor):
      .line(ReadingPlace(at: anchor.characterOffset, in: index), fraction: anchor.fraction)
    }
  }

  public mutating func restore(_ carried: Carried, in index: AnchorIndex, length: Int) {
    switch carried {
    case .top:
      place = .top
    case .line(let reading, let fraction):
      let offset = reading.documentOffset(in: index, length: length) ?? 0
      place = .line(
        ReaderAnchor(characterOffset: min(offset, max(0, length - 1)), fraction: fraction))
    }
  }

  /// The place to save as the reading position (#322); nil at the top.
  public func readingPlace(in index: AnchorIndex) -> ReadingPlace? {
    guard case .line(let anchor) = place else { return nil }
    return ReadingPlace(at: anchor.characterOffset, in: index)
  }
}
