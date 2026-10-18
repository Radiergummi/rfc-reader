import Foundation
import RFCKit

/// Where a document's highlights are in one build (#522): each relocated against the
/// build's model text, then drawn where the build shows it. What a text view draws,
/// what the Annotations tab says of each highlight, and the relocations to write back.
/// Pure, and made off the main actor: relocation reads the whole model text.
public struct HighlightPlacement: Sendable, Equatable {
  /// What became of one highlight in this document.
  public enum Status: Sendable, Equatable {
    /// Where it is now, in the model text, the target that says so, and the section
    /// (or the abstract) it starts in.
    case placed(Range<Int>, Target, section: String?)
    /// Its quote is in several places, so it is drawn in none: each place it could go,
    /// with the target that would put it there.
    case ambiguous([Target])
    /// Its quote is nowhere: kept, and listed apart.
    case detached
  }

  /// What the text view draws.
  public let marks: HighlightMarks
  public let statuses: [UUID: Status]
  /// The highlights relocation found somewhere other than what they record, to be
  /// written to their relocated fields.
  public let relocations: [UUID: Target]

  public static let none = HighlightPlacement(
    marks: HighlightMarks([]), statuses: [:], relocations: [:])

  init(marks: HighlightMarks, statuses: [UUID: Status], relocations: [UUID: Target]) {
    self.marks = marks
    self.statuses = statuses
    self.relocations = relocations
  }

  /// `highlights` in `built`. A translation's build has no highlight drawn: its
  /// sentences are not the original's (#749).
  public init(_ highlights: [AnnotationSnapshot.HighlightEntry], in built: BuiltDocument) {
    guard !built.isTranslation, !highlights.isEmpty else {
      self = .none
      return
    }
    let model = built.positions.model
    let relocator = Relocator(model)
    var marks: [HighlightMark] = []
    var statuses: [UUID: Status] = [:]
    var relocations: [UUID: Target] = [:]
    for entry in highlights {
      var relocation = relocator.relocate(entry.current)
      // A relocated position that no longer holds starts over from the original.
      if entry.relocated != nil, !relocation.isExact {
        relocation = relocator.relocate(entry.target)
      }
      if case .ambiguous(let ranges) = relocation {
        statuses[entry.id] = .ambiguous(
          ranges.compactMap { Target(covering: $0, in: model, quote: entry.quote) })
        continue
      }
      guard let target = relocation.target, let range = target.range(in: model) else {
        statuses[entry.id] = .detached
        continue
      }
      statuses[entry.id] = .placed(
        range, target, section: model.section(containing: range.lowerBound)?.anchor)
      if target != entry.current { relocations[entry.id] = target }
      for drawn in built.positions.drawnRanges(forModel: range) {
        marks.append(HighlightMark(range: drawn, color: entry.color, highlight: entry.id))
      }
    }
    self.marks = HighlightMarks(marks)
    self.statuses = statuses
    self.relocations = relocations
  }
}

/// One stretch of a build's storage a highlight covers, and its color.
public struct HighlightMark: Sendable, Equatable {
  public let range: NSRange
  public let color: HighlightColor
  public let highlight: UUID

  public init(range: NSRange, color: HighlightColor, highlight: UUID) {
    self.range = range
    self.color = color
    self.highlight = highlight
  }
}

/// A build's highlight marks, by where they start, for a fragment to find its own.
public struct HighlightMarks: Sendable, Equatable {
  public let marks: [HighlightMark]

  public init(_ marks: [HighlightMark]) {
    self.marks = marks.sorted { $0.range.location < $1.range.location }
  }

  /// The marks that meet `range`, whole: where a mark starts and ends decides which of
  /// its corners round, as a requirement band's does.
  public func marks(meeting range: NSRange) -> [HighlightMark] {
    // Marks do not overlap, so the ends are in order too.
    let first = marks.partitioningIndex { NSMaxRange($0.range) > range.location }
    return Array(marks[first...].prefix { $0.range.location < NSMaxRange(range) })
  }

  /// The highlight at storage offset `offset`, if any.
  public func highlight(at offset: Int) -> HighlightMark? {
    marks(meeting: NSRange(location: offset, length: 1)).first
  }
}

extension HighlightMarks {
  /// The Highlights rotor's stops (#522): every mark, said as highlighted in its color,
  /// since VoiceOver sees nothing of what the fragments draw.
  public func rotorItems(locale: Locale = .interface) -> [AccessibleReading.RotorItem] {
    marks.map { mark in
      AccessibleReading.RotorItem(range: mark.range, label: Self.spoken(mark.color, locale: locale))
    }
  }

  /// A sentence each, rather than the color's name put into one.
  private static func spoken(_ color: HighlightColor, locale: Locale) -> String {
    switch color {
    case .yellow: String(kit: "Highlighted, yellow", locale: locale)
    case .green: String(kit: "Highlighted, green", locale: locale)
    case .blue: String(kit: "Highlighted, blue", locale: locale)
    case .pink: String(kit: "Highlighted, pink", locale: locale)
    case .purple: String(kit: "Highlighted, purple", locale: locale)
    case .underline: String(kit: "Underlined", locale: locale)
    }
  }
}
