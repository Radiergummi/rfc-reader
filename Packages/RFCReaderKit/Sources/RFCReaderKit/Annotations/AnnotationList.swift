import Foundation
import RFCKit

/// What the Annotations tab lists (#522): every highlight of the document, in document
/// order, with its quote and the section it is in; then those drawn nowhere, the
/// ambiguous ones first, each marked as such. Without a build to place them in, as
/// when the document failed to load, the stored quotes alone, oldest first.
public enum AnnotationList {
  public enum Placement: Sendable, Equatable {
    /// Where it is: the anchor a click scrolls to, and the section it is in.
    case placed(anchor: String, section: String?)
    /// Its quote is in several places, each of which the reader may choose.
    case ambiguous([Target])
    /// Its quote is nowhere in the document.
    case detached
    /// The document is not here to place it in.
    case unplaced
  }

  public struct Row: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let quote: String
    public let color: HighlightColor
    public let placement: Placement
  }

  public static func rows(
    _ highlights: [AnnotationSnapshot.HighlightEntry],
    statuses: [UUID: HighlightPlacement.Status]?
  ) -> [Row] {
    guard let statuses else {
      return highlights.sorted { $0.createdAt < $1.createdAt }.map {
        Row(id: $0.id, quote: $0.quote.exact, color: $0.color, placement: .unplaced)
      }
    }
    var placed: [(start: Int, row: Row)] = []
    var ambiguous: [Row] = []
    var detached: [Row] = []
    for entry in highlights.sorted(by: { $0.createdAt < $1.createdAt }) {
      switch statuses[entry.id] {
      case .placed(let range, let target, let section)?:
        let anchor: String =
          if case .range(let start, _, _) = target { start.anchor } else { section ?? "" }
        placed.append(
          (
            range.lowerBound,
            Row(
              id: entry.id, quote: entry.quote.exact, color: entry.color,
              placement: .placed(anchor: anchor, section: section))
          ))
      case .ambiguous(let places)?:
        ambiguous.append(
          Row(
            id: entry.id, quote: entry.quote.exact, color: entry.color,
            placement: .ambiguous(places)))
      case .detached?, nil:
        // One not placed yet, made since the build placed the others, is listed apart
        // until it is.
        detached.append(
          Row(id: entry.id, quote: entry.quote.exact, color: entry.color, placement: .detached))
      }
    }
    return placed.sorted { $0.start < $1.start }.map(\.row) + ambiguous + detached
  }
}
