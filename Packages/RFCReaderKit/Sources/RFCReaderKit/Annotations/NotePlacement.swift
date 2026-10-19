import Foundation
import RFCKit

/// What a note is on (#523): a highlight, which several notes may share, or a target
/// of its own, a section or a range, as "Add Note to Figure" makes one covering
/// exactly the block.
public enum NoteOwner: Sendable, Hashable {
  case highlight(UUID)
  case target(Target)
}

/// A note to open the editor on (#523): one there is, or a new one on what it will
/// be on, which is made once it has text.
public enum NoteRequest: Sendable, Hashable {
  case existing(UUID)
  case new(NoteOwner)
}

/// Where a document's notes are in one build (#523), placed after its highlights
/// (`HighlightPlacement`), since a note on a highlight is where its highlight is. What
/// the gutter markers stand by, what the Annotations tab says of each note, and what
/// to write back: relocations of a note's own range, and notes put on the highlight
/// that covers them now that theirs is gone. Pure, and made off the main actor.
public struct NotePlacement: Sendable, Equatable {
  public enum Status: Sendable, Equatable {
    /// On the highlight it names, or was put on (`repoints`), wherever that is.
    case onHighlight(UUID)
    /// Its own target, where it is now in the model text, and the section it starts in.
    case placed(Range<Int>, section: String?)
    /// Its own range's quote is in several places, so it is placed at none.
    case ambiguous
    /// Its own target is nowhere, or its highlight is gone and none covers it: kept,
    /// and listed apart.
    case detached
  }

  /// A note's marker, at the storage offset where its target starts: where the line
  /// it is level with begins.
  public struct Marker: Sendable, Equatable {
    public let note: UUID
    public let location: Int

    public init(note: UUID, location: Int) {
      self.note = note
      self.location = location
    }
  }

  public let statuses: [UUID: Status]
  /// In storage order, the notes of one place in the order they were made.
  public let markers: [Marker]
  /// Notes whose own range relocation found elsewhere than they record.
  public let relocations: [UUID: Target]
  /// Notes whose highlight is gone, and the highlight that covers each now.
  public let repoints: [UUID: UUID]

  public static let none = NotePlacement(
    statuses: [:], markers: [], relocations: [:], repoints: [:])

  init(
    statuses: [UUID: Status], markers: [Marker], relocations: [UUID: Target],
    repoints: [UUID: UUID]
  ) {
    self.statuses = statuses
    self.markers = markers
    self.relocations = relocations
    self.repoints = repoints
  }

  /// `notes` in `built`, whose highlights `highlights` placed. A translation's build
  /// places none, as it draws no highlight.
  public init(
    _ notes: [AnnotationSnapshot.NoteEntry], highlights: HighlightPlacement,
    in built: BuiltDocument
  ) {
    guard !built.isTranslation else {
      self = .none
      return
    }
    let text = built.text.string as NSString
    self.init(notes, highlights: highlights, in: built.positions.model) { range in
      built.positions.drawnRanges(forModel: range, in: text).first?.location
    }
  }

  /// `notes` in the model text alone, with no marker: where they are in the document,
  /// without a build to show them, as an export places them (#524).
  public init(
    _ notes: [AnnotationSnapshot.NoteEntry], highlights: HighlightPlacement, in model: ModelText
  ) {
    self.init(notes, highlights: highlights, in: model) { _ in nil }
  }

  /// - Parameter markerLocation: the storage offset a marker for a note at a range of
  ///   the model text stands at, or nil for none.
  private init(
    _ notes: [AnnotationSnapshot.NoteEntry], highlights: HighlightPlacement,
    in model: ModelText, markerLocation: (Range<Int>) -> Int?
  ) {
    guard highlights.isPlaced, !notes.isEmpty else {
      self = .none
      return
    }
    let relocator = Relocator(model)
    var statuses: [UUID: Status] = [:]
    var markers: [Marker] = []
    var relocations: [UUID: Target] = [:]
    var repoints: [UUID: UUID] = [:]
    // The highlights placed, by where they are, for a note whose own is gone.
    let placed = highlights.statuses.compactMap { identifier, status -> (UUID, Range<Int>)? in
      if case .placed(let range, _, _) = status { (identifier, range) } else { nil }
    }
    .sorted { ($0.1.lowerBound, $0.0.uuidString) < ($1.1.lowerBound, $1.0.uuidString) }

    func marker(_ note: UUID, at range: Range<Int>) {
      if let location = markerLocation(range) {
        markers.append(Marker(note: note, location: location))
      }
    }

    for note in notes {
      if var highlight = note.highlight {
        if highlights.statuses[highlight] == nil {
          // Its highlight is gone: the one that now covers where it was, if any.
          guard
            let range = note.current.flatMap({ relocator.relocate($0).target })?
              .range(in: model),
            let covering = placed.first(where: {
              $0.1.lowerBound <= range.lowerBound && $0.1.upperBound >= range.upperBound
            })
          else {
            statuses[note.id] = .detached
            continue
          }
          highlight = covering.0
          repoints[note.id] = highlight
        }
        statuses[note.id] = .onHighlight(highlight)
        if case .placed(let range, _, _)? = highlights.statuses[highlight] {
          marker(note.id, at: range)
        }
        continue
      }
      guard let current = note.current else {
        statuses[note.id] = .detached
        continue
      }
      var relocation = relocator.relocate(current)
      // A relocated position that no longer holds starts over from the original.
      if note.relocated != nil, !relocation.isExact, let target = note.target {
        relocation = relocator.relocate(target)
      }
      if case .ambiguous = relocation {
        statuses[note.id] = .ambiguous
        continue
      }
      guard let target = relocation.target, let range = target.range(in: model) else {
        statuses[note.id] = .detached
        continue
      }
      statuses[note.id] = .placed(
        range, section: model.section(containing: range.lowerBound)?.anchor)
      if case .range = target, target != current { relocations[note.id] = target }
      marker(note.id, at: range)
    }
    // Stable: notes come oldest first, so those of one place keep that order.
    markers = markers.enumerated().sorted {
      ($0.element.location, $0.offset) < ($1.element.location, $1.offset)
    }.map(\.element)
    self.init(statuses: statuses, markers: markers, relocations: relocations, repoints: repoints)
  }

  /// Whether `notes` are placed as `others` are: the same notes, on the same
  /// highlights and targets. A note's text, which changes as it is typed, places
  /// nothing.
  public static func placesAlike(
    _ notes: [AnnotationSnapshot.NoteEntry], _ others: [AnnotationSnapshot.NoteEntry]
  ) -> Bool {
    notes.map(\.placementKey) == others.map(\.placementKey)
  }

  /// The highlight a note is on now: the one it names, or the one it was put on.
  public func highlight(of note: AnnotationSnapshot.NoteEntry) -> UUID? {
    if case .onHighlight(let highlight)? = statuses[note.id] { return highlight }
    return note.highlight
  }
}

extension AnnotationSnapshot.NoteEntry {
  /// What placing a note reads of it: not its text.
  fileprivate var placementKey: [AnyHashable] {
    [id, highlight as AnyHashable, target as AnyHashable, relocated as AnyHashable]
  }
}
