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

/// What folding needs to know of a build, worked out once per build rather than on
/// every toggle: where each paragraph starts, and the outline's entries, which are
/// the sections and the abstract, each with where its heading's paragraph starts.
public struct FoldingIndex: Sendable {
  public struct Entry: Sendable, Equatable {
    public let anchor: String
    /// Where the anchor is: the heading.
    public let offset: Int
    /// Where the heading's paragraph starts, which is where its disclosure is.
    public let paragraph: Int
    /// How deep it is nested, 1 for a top-level section or the abstract.
    public let depth: Int
  }

  /// Every paragraph, in order.
  let paragraphs: [NSRange]
  /// The sections and the abstract, in order.
  let entries: [Entry]
  let length: Int

  public init(_ built: BuiltDocument) {
    let string = built.text.string as NSString
    var paragraphs: [NSRange] = []
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length),
      options: [.byParagraphs, .substringNotRequired]
    ) { _, _, enclosing, _ in paragraphs.append(enclosing) }
    self.paragraphs = paragraphs
    length = string.length
    // The abstract has a heading of its own but no section, so it is an entry of the
    // outline beside the sections: otherwise nothing could open it.
    let abstract = built.anchors.entries.filter { $0.anchor == DocumentTextBuilder.abstractAnchor }
    entries = (abstract + built.anchors.sections.entries)
      .sorted { $0.offset < $1.offset }
      .map { entry in
        Entry(
          anchor: entry.anchor, offset: entry.offset,
          paragraph: string.paragraphRange(for: NSRange(location: entry.offset, length: 0))
            .location,
          depth: entry.depth ?? 1
        )
      }
  }

  /// Where a line put at `offset` lands: the last character for the end of the text,
  /// where TextKit lays out no fragment and a placement would find nothing.
  public func lineOffset(for offset: Int) -> Int {
    min(offset, max(0, length - 1))
  }

  /// The entry whose text `offset` is in: the last at or before it.
  func entry(covering offset: Int) -> Entry? {
    let after = entries.partitioningIndex { $0.offset > offset }
    return after > 0 ? entries[after - 1] : nil
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
    hidden(in: FoldingIndex(built))
  }

  /// The paragraphs this folding hides: in the outline, every one but the headings and
  /// an expanded entry's own text, which runs to the next heading of any level; a
  /// heading only where every section it is nested in is expanded (`outline(in:)`).
  public func hidden(in index: FoldingIndex) -> HiddenText {
    guard mode == .outline else { return HiddenText() }
    let outline = outline(in: index)
    let headings = Dictionary(
      zip(index.entries, outline).map { ($0.paragraph, $1.headingShown) },
      uniquingKeysWith: { first, _ in first })
    var next = 0
    var textShown = false
    var paragraphs: [(range: NSRange, isHidden: Bool)] = []
    paragraphs.reserveCapacity(index.paragraphs.count)
    for paragraph in index.paragraphs {
      // The entries are in order, as the paragraphs are: one pass over both.
      while next < index.entries.count, index.entries[next].offset <= paragraph.location {
        textShown = outline[next].textShown
        next += 1
      }
      paragraphs.append((paragraph, !(headings[paragraph.location] ?? textShown)))
    }
    return HiddenText(paragraphs: paragraphs, length: index.length)
  }

  public func disclosures(in built: BuiltDocument) -> [Int: Bool] {
    disclosures(in: FoldingIndex(built))
  }

  /// The headings that have a disclosure, by where their paragraph starts, each open
  /// or not: in the outline, every one it shows; in Normal, none.
  public func disclosures(in index: FoldingIndex) -> [Int: Bool] {
    guard mode == .outline else { return [:] }
    return Dictionary(
      zip(index.entries, outline(in: index)).filter(\.1.headingShown).map { entry, _ in
        (entry.paragraph, expanded.contains(entry.anchor))
      },
      uniquingKeysWith: { first, _ in first })
  }

  public func toggling(heading offset: Int, in built: BuiltDocument) -> Folding? {
    toggling(heading: offset, in: FoldingIndex(built))
  }

  /// This folding with the section of the heading whose paragraph `offset` is in
  /// opened, or closed if it was open; nil where `offset` is in no heading this mode
  /// discloses.
  public func toggling(heading offset: Int, in index: FoldingIndex) -> Folding? {
    guard mode == .outline, let entry = index.entry(covering: offset) else { return nil }
    // In the heading's paragraph: from its start to the paragraph after it. Found by
    // halving, as the pointer asks on every move over the gutter.
    let after = index.paragraphs.partitioningIndex { $0.location > entry.paragraph }
    guard after > 0, NSLocationInRange(offset, index.paragraphs[after - 1]) else { return nil }
    var toggled = self
    if toggled.expanded.remove(entry.anchor) == nil {
      toggled.expanded.insert(entry.anchor)
    }
    return toggled
  }

  public func expanding(toShow offset: Int, in built: BuiltDocument) -> Folding {
    expanding(toShow: offset, in: FoldingIndex(built))
  }

  /// This folding with what `offset` is in shown: a jump, a find hit or a restored
  /// place inside a folded section, or in the abstract, expands it and every section
  /// it is nested in. Unchanged in a mode that folds nothing.
  public func expanding(toShow offset: Int, in index: FoldingIndex) -> Folding {
    guard mode != .normal, let entry = index.entry(covering: offset) else { return self }
    var expanded = self
    expanded.expanded.formUnion(index.anchors(enclosing: entry) + [entry.anchor])
    return expanded
  }

  /// Each outline entry, in order: whether its heading is shown, which is where every
  /// section it is nested in is expanded, and whether its own text is, which is where
  /// its heading is shown and it is expanded itself.
  private func outline(in index: FoldingIndex) -> [(headingShown: Bool, textShown: Bool)] {
    // The sections the entry is nested in, outermost first, each with whether what
    // it holds is shown.
    var enclosing: [(depth: Int, isOpen: Bool)] = []
    return index.entries.map { entry in
      while let last = enclosing.last, last.depth >= entry.depth {
        enclosing.removeLast()
      }
      let headingShown = enclosing.last?.isOpen ?? true
      let textShown = headingShown && expanded.contains(entry.anchor)
      enclosing.append((entry.depth, textShown))
      return (headingShown, textShown)
    }
  }
}

extension FoldingIndex {
  /// The anchors of the sections `entry` is nested in: each shallower heading
  /// before it, back to the top level.
  func anchors(enclosing entry: Entry) -> [String] {
    guard let position = entries.firstIndex(of: entry) else { return [] }
    var depth = entry.depth
    var anchors: [String] = []
    for earlier in entries[..<position].reversed() where earlier.depth < depth {
      anchors.append(earlier.anchor)
      depth = earlier.depth
    }
    return anchors
  }
}

/// The text a folding hides, as runs of whole paragraphs: what the layout skips.
public struct HiddenText: Sendable, Equatable {
  /// A run of hidden paragraphs, and where the shown paragraph nearest it starts:
  /// the one before it, or the one after it for a run at the start of the text.
  private struct Run: Sendable, Equatable {
    var range: NSRange
    var shownBefore: Int?
  }

  private var runs: [Run] = []
  private var length = 0

  public init() {}

  /// From every paragraph in order, each hidden or not: consecutive hidden ones are
  /// one run.
  init(paragraphs: [(range: NSRange, isHidden: Bool)], length: Int) {
    self.length = length
    var lastShown: Int?
    for paragraph in paragraphs {
      guard paragraph.isHidden else {
        lastShown = paragraph.range.location
        continue
      }
      if let last = runs.last, NSMaxRange(last.range) == paragraph.range.location {
        runs[runs.count - 1].range.length += paragraph.range.length
      } else {
        runs.append(Run(range: paragraph.range, shownBefore: lastShown))
      }
    }
  }

  public var isEmpty: Bool { runs.isEmpty }

  /// The runs of hidden text, in order.
  public var ranges: [NSRange] { runs.map(\.range) }

  /// Whether the character at `offset` is hidden.
  public func contains(_ offset: Int) -> Bool {
    run(containing: offset) != nil
  }

  /// `offset` where it is shown; otherwise where the shown paragraph before its run
  /// starts, or, for a run at the start of the text, the first shown character after
  /// it: where a reader's line in folded text is kept. Nil only when nothing is shown.
  public func shownOffset(near offset: Int) -> Int? {
    guard let index = run(containing: offset) else { return offset }
    if let before = runs[index].shownBefore { return before }
    let after = NSMaxRange(runs[index].range)
    return after < length ? after : nil
  }

  /// The end of the text counts as in the last paragraph, as TextKit's location for it
  /// is: ⌘↓ puts the insertion point there, and a reveal of it has to open what it is in.
  private func run(containing offset: Int) -> Int? {
    let after = runs.partitioningIndex { $0.range.location > offset }
    guard after > 0 else { return nil }
    let run = runs[after - 1].range
    guard NSLocationInRange(offset, run) || (offset == length && NSMaxRange(run) == length)
    else { return nil }
    return after - 1
  }
}
