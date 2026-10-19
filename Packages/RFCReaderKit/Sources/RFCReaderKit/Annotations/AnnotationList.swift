import Foundation
import RFCKit

/// What the Annotations tab lists (#522, #523): every highlight of the document, with
/// the notes on it, and every note on a target of its own, a block or a section, in
/// document order, with its quote and the section it is in; then those placed
/// nowhere, the ambiguous ones first, each marked as such. Without a build to place
/// them in, as when the document failed to load, the stored quotes alone, oldest
/// first.
public enum AnnotationList {
  public enum Placement: Sendable, Equatable {
    /// Where it is: the anchor a click scrolls to, and the section it is in.
    case placed(anchor: String, section: String?)
    /// Its quote is in several places, each of which the reader may choose; none for
    /// a note.
    case ambiguous([Target])
    /// Its quote is nowhere in the document.
    case detached
    /// The document is not here to place it in.
    case unplaced
  }

  /// A note as a row shows it: its first line.
  public struct NoteLine: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let firstLine: String
  }

  public struct Row: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// What it covers; for a note on a section, nothing, its section saying it.
    public let quote: String
    /// A highlight's color; nil for a note on a target of its own.
    public let color: HighlightColor?
    public let placement: Placement
    /// The notes on it: a highlight's, or the one note a row of its own stands for.
    public let notes: [NoteLine]

    /// Whether it stands for a note on a target of its own, rather than a highlight.
    public var isNote: Bool { color == nil }
  }

  public static func rows(
    _ highlights: [AnnotationSnapshot.HighlightEntry],
    notes: [AnnotationSnapshot.NoteEntry] = [],
    statuses: [UUID: HighlightPlacement.Status]?,
    noteStatuses: NotePlacement? = nil
  ) -> [Row] {
    let known = Set(highlights.map(\.id))
    // The note each highlight has, as placement puts them: on a highlight that is gone,
    // a note is on the one that covers it.
    var onHighlight: [UUID: [NoteLine]] = [:]
    var ownNotes: [AnnotationSnapshot.NoteEntry] = []
    for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
      let highlight = noteStatuses?.highlight(of: note) ?? note.highlight
      if let highlight, known.contains(highlight) {
        onHighlight[highlight, default: []].append(line(of: note))
      } else {
        ownNotes.append(note)
      }
    }
    guard let statuses else {
      return highlights.sorted { $0.createdAt < $1.createdAt }.map {
        Row(
          id: $0.id, quote: $0.quote.exact, color: $0.color, placement: .unplaced,
          notes: onHighlight[$0.id] ?? [])
      }
        + ownNotes.map { row(of: $0, placement: .unplaced) }
    }
    var placed: [(start: Int, row: Row)] = []
    var ambiguous: [Row] = []
    var detached: [Row] = []
    for entry in highlights.sorted(by: { $0.createdAt < $1.createdAt }) {
      let notes = onHighlight[entry.id] ?? []
      switch statuses[entry.id] {
      case .placed(let range, let target, let section)?:
        let anchor: String =
          if case .range(let start, _, _) = target { start.anchor } else { section ?? "" }
        placed.append(
          (
            range.lowerBound,
            Row(
              id: entry.id, quote: entry.quote.exact, color: entry.color,
              placement: .placed(anchor: anchor, section: section), notes: notes)
          ))
      case .ambiguous(let places)?:
        ambiguous.append(
          Row(
            id: entry.id, quote: entry.quote.exact, color: entry.color,
            placement: .ambiguous(places), notes: notes))
      case .detached?, nil:
        // One not placed yet, made since the build placed the others, is listed apart
        // until it is.
        detached.append(
          Row(
            id: entry.id, quote: entry.quote.exact, color: entry.color, placement: .detached,
            notes: notes))
      }
    }
    for note in ownNotes {
      switch noteStatuses?.statuses[note.id] {
      case .placed(let range, let section)?:
        let anchor: String =
          switch note.current {
          case .range(let start, _, _)?: start.anchor
          case .section(let anchor)?: anchor
          case nil: section ?? ""
          }
        placed.append(
          (range.lowerBound, row(of: note, placement: .placed(anchor: anchor, section: section))))
      case .ambiguous?:
        ambiguous.append(row(of: note, placement: .ambiguous([])))
      case .detached?, .onHighlight?, nil:
        detached.append(row(of: note, placement: .detached))
      }
    }
    return placed.enumerated().sorted {
      ($0.element.start, $0.offset) < ($1.element.start, $1.offset)
    }.map(\.element.row) + ambiguous + detached
  }

  private static func row(of note: AnnotationSnapshot.NoteEntry, placement: Placement) -> Row {
    let quote = if case .range(_, _, let quote)? = note.target { quote.exact } else { "" }
    return Row(id: note.id, quote: quote, color: nil, placement: placement, notes: [line(of: note)])
  }

  private static func line(of note: AnnotationSnapshot.NoteEntry) -> NoteLine {
    let text = NoteBody(markdown: note.body).plainText
    let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    return NoteLine(id: note.id, firstLine: first)
  }
}
