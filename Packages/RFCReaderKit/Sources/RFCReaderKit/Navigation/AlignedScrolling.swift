import Foundation
import RFCKit

/// Where one of two documents read side by side should be, given where the other is
/// (#187): the counterpart of the section the leading side is in, as far through it
/// as the leading side is through its own.
///
/// The counterparts are `SectionAlignment`'s rows, so only documents joined by an
/// obsoletes edge are paired. A section is matched to its best match on the other
/// side, the highest score among its rows: a section split in two follows the half
/// most like it. How far through a section is counted in characters, from its heading
/// to the next section's, at any depth; the last runs to the end of its document.
public struct AlignedScrolling: Sendable, Equatable {
  /// One of the two documents, as its build has it.
  public struct Side: Sendable, Equatable {
    public var document: DocumentID
    /// The build's section anchors (`AnchorIndex.sections`).
    public var sections: AnchorIndex
    /// The build's length, where the last section ends.
    public var length: Int

    public init(document: DocumentID, sections: AnchorIndex, length: Int) {
      self.document = document
      self.sections = sections
      self.length = length
    }
  }

  /// What the following side does.
  public enum Follow: Sendable, Equatable {
    /// Goes to this character.
    case offset(Int)
    /// Goes to its top: the leading side is above its first section.
    case top
    /// Holds still: the leading side is in this section, which has no counterpart.
    case unaligned(section: String)
  }

  /// Each section's best match, keyed by document and then by anchor.
  private let counterparts: [DocumentID: [String: String]]

  /// The rows between `first` and `second`, in either direction; any other row is
  /// some other pair's, aligned alongside so that it is not taken for this one's.
  public init(rows: [AlignedSection], between first: DocumentID, and second: DocumentID) {
    let pair = Set([first, second])
    var best: [DocumentID: [String: (anchor: String, score: Double)]] = [:]
    func keep(_ from: DocumentID, _ section: String, _ to: String, _ score: Double) {
      if let kept = best[from]?[section], kept.score >= score { return }
      best[from, default: [:]][section] = (to, score)
    }
    for row in rows where pair == Set([row.old, row.new]) {
      keep(row.old, row.oldSection, row.newSection, row.score)
      keep(row.new, row.newSection, row.oldSection, row.score)
    }
    counterparts = best.mapValues { $0.mapValues(\.anchor) }
  }

  public static func == (lhs: AlignedScrolling, rhs: AlignedScrolling) -> Bool {
    lhs.counterparts == rhs.counterparts
  }

  /// The section of the other document that `section`, of `document`, became or came
  /// from; nil when it has none.
  public func counterpart(of section: String, in document: DocumentID) -> String? {
    counterparts[document]?[section]
  }

  /// Where `following` goes when `leading` is at `offset`, the character of its
  /// reader's line; nil above the text.
  public func follow(_ offset: Int?, from leading: Side, to following: Side) -> Follow {
    guard let offset, let section = leading.sections.anchor(at: offset),
      let start = leading.sections.offset(of: section)
    else { return .top }
    guard let counterpart = counterpart(of: section, in: leading.document),
      let target = following.sections.offset(of: counterpart)
    else { return .unaligned(section: section) }
    let span = leading.end(ofSectionAt: start) - start
    let targetSpan = following.end(ofSectionAt: target) - target
    let fraction = span > 0 ? Double(offset - start) / Double(span) : 0
    return .offset(target + Int((fraction * Double(targetSpan)).rounded(.down)))
  }
}

extension AlignedScrolling.Side {
  /// Where the section starting at `start` ends: at the next section, or the end.
  fileprivate func end(ofSectionAt start: Int) -> Int {
    let next = sections.entries.partitioningIndex { $0.offset > start }
    return next < sections.entries.endIndex ? sections.entries[next].offset : length
  }
}
