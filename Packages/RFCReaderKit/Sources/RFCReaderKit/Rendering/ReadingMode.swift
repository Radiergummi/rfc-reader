import Foundation

/// How the reader shows a document (#188): all of it, or a mode that folds some of it
/// away. Every mode is a presentation of the one built document: it decides which
/// paragraphs are laid out, and changes nothing in the text storage, so every offset,
/// anchor and reading position holds across a switch.
public enum ReadingMode: String, CaseIterable, Identifiable, Sendable {
  case normal
  /// Headings only, each section expandable in place (#698).
  case outline

  public var id: String { rawValue }

  /// What the Reading Mode menu calls it.
  public var name: String {
    switch self {
    case .normal: "Normal"
    case .outline: "Outline"
    }
  }
}

/// A window's reading mode and the sections it has expanded in place. Window state:
/// nothing of it is kept.
public struct Folding: Sendable, Equatable {
  public var mode: ReadingMode
  /// The anchors of the sections whose own text is shown although the mode folds it.
  public var expanded: Set<String>

  public init(mode: ReadingMode = .normal, expanded: Set<String> = []) {
    self.mode = mode
    self.expanded = expanded
  }

  /// The paragraphs this folding hides in `built`.
  public func hidden(in built: BuiltDocument) -> HiddenText {
    guard mode == .outline else { return HiddenText() }
    let string = built.text.string as NSString
    let sections = built.anchors.sections.entries
    // A heading's paragraph is shown; so is a paragraph in an expanded section's own
    // text, which runs to the next heading of any level.
    let headings = Set(
      sections.map { string.paragraphRange(for: NSRange(location: $0.offset, length: 0)).location })
    let shownSpans: [Range<Int>] = sections.indices.compactMap { index in
      guard expanded.contains(sections[index].anchor) else { return nil }
      let end = index + 1 < sections.count ? sections[index + 1].offset : string.length
      return sections[index].offset..<end
    }
    var paragraphs: [(range: NSRange, isHidden: Bool)] = []
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length),
      options: [.byParagraphs, .substringNotRequired]
    ) { _, _, enclosing, _ in
      let start = enclosing.location
      let isShown = headings.contains(start) || shownSpans.contains { $0.contains(start) }
      paragraphs.append((enclosing, !isShown))
    }
    return HiddenText(paragraphs: paragraphs)
  }

  /// This folding with what `offset` is in shown: a jump, a find hit or a restored
  /// place inside a folded section expands that section. Unchanged in a mode that
  /// folds nothing.
  public func expanding(toShow offset: Int, in built: BuiltDocument) -> Folding {
    guard mode != .normal, let section = built.anchors.sections.anchor(at: offset) else {
      return self
    }
    var expanded = self
    expanded.expanded.insert(section)
    return expanded
  }
}

/// The text a folding hides, as runs of whole paragraphs: what the layout skips.
public struct HiddenText: Sendable, Equatable {
  /// Each run of hidden paragraphs, in order, with where the shown paragraph before it
  /// starts (nil for a run at the start of the text).
  private var runs: [(range: NSRange, shownBefore: Int?)] = []

  public init() {}

  /// From every paragraph in order, each hidden or not: consecutive hidden ones are
  /// one run.
  init(paragraphs: [(range: NSRange, isHidden: Bool)]) {
    var lastShown: Int?
    for paragraph in paragraphs {
      guard paragraph.isHidden else {
        lastShown = paragraph.range.location
        continue
      }
      if let last = runs.last, NSMaxRange(last.range) == paragraph.range.location {
        runs[runs.count - 1].range.length += paragraph.range.length
      } else {
        runs.append((paragraph.range, lastShown))
      }
    }
  }

  public static func == (lhs: HiddenText, rhs: HiddenText) -> Bool {
    lhs.runs.map(\.range) == rhs.runs.map(\.range)
      && lhs.runs.map(\.shownBefore) == rhs.runs.map(\.shownBefore)
  }

  public var isEmpty: Bool { runs.isEmpty }

  /// The runs of hidden text, in order.
  public var ranges: [NSRange] { runs.map(\.range) }

  /// Whether the character at `offset` is hidden.
  public func contains(_ offset: Int) -> Bool {
    run(containing: offset) != nil
  }

  /// `offset` where it is shown, otherwise where the shown paragraph before its run
  /// starts: where a reader's line in folded text is kept. Nil only for a run at the
  /// start of the text.
  public func shownOffset(atOrBefore offset: Int) -> Int? {
    guard let index = run(containing: offset) else { return offset }
    return runs[index].shownBefore
  }

  private func run(containing offset: Int) -> Int? {
    let after = runs.partitioningIndex { $0.range.location > offset }
    guard after > 0, NSLocationInRange(offset, runs[after - 1].range) else { return nil }
    return after - 1
  }
}
