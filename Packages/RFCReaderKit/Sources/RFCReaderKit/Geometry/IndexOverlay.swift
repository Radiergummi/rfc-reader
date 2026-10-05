import Foundation

/// What the index's overlays show, as functions of where the reader is: the App
/// target reads the viewport and places views by these, and decides nothing itself.
/// Offsets are UTF-16 offsets into the built text; distances are points from the top
/// of the part of the viewport the bars leave uncovered, down positive.
extension IndexMap {
  /// Whether any of the index is on screen: its range meets `visible` somewhere a
  /// folding does not hide. The viewport can span a folded index, as the outline
  /// shows the headings around it.
  public func isShowing(visible: NSRange, hidden: HiddenText) -> Bool {
    guard !isEmpty else { return false }
    let shown = NSIntersectionRange(range, visible)
    guard shown.length > 0 else { return false }
    // The runs are in order and do not overlap: skip every one that covers where
    // the shown part has got to.
    var location = shown.location
    for run in hidden.ranges {
      if run.location > location { break }
      location = max(location, NSMaxRange(run))
    }
    return location < NSMaxRange(shown)
  }

  /// The group the character at `offset` is in: the last whose letter starts at or
  /// before it. Nil above the first, where the index's own heading is.
  public func group(at offset: Int) -> Int? {
    groups.lastIndex { $0.labelRange.location <= offset }
  }
}

/// The current group's letter pinned at the top of the text, as Contacts pins a
/// section's.
public enum StickyLetter {
  /// How far above the top a label may sit and still count as at the top: a jump puts
  /// it there to within a rounding error, which is not past it.
  static let tolerance: CGFloat = 0.5

  /// How far above its place the letter is drawn, 0 or less; nil while it should not
  /// show at all, which is while the current group's own label is in view at or below
  /// the top, so a letter is never on screen twice. The next group's label, rising
  /// under the pinned letter, pushes it up by as much as they overlap.
  ///
  /// - Parameter currentLabelTop: where the current group's label starts, nil when
  ///   its fragment is not on screen (scrolled away above).
  /// - Parameter nextLabelTop: where the next group's label starts, nil when it is not
  ///   on screen.
  /// - Parameter height: the pinned letter's height.
  public static func offset(currentLabelTop: CGFloat?, nextLabelTop: CGFloat?, height: CGFloat)
    -> CGFloat?
  {
    if let currentLabelTop, currentLabelTop > -tolerance { return nil }
    guard let nextLabelTop else { return 0 }
    return min(0, nextLabelTop - height)
  }
}

/// The A–Z rail beside the index: a row per group, as `UITableView`'s section index
/// draws one. Rows are measured from the rail's top.
public struct IndexRail: Equatable {
  public struct Row: Equatable {
    /// A group's letter, or `IndexRail.dot` where a short rail leaves letters out.
    public let text: String
    public let center: CGFloat
  }

  public static let width: CGFloat = 18
  public static let idealRowHeight: CGFloat = 16
  /// Below this the letters crowd; the rail leaves every other one out instead.
  public static let minimumRowHeight: CGFloat = 11
  public static let dot = "•"

  public let rows: [Row]
  /// From the first row's top to the last's bottom.
  public let height: CGFloat
  private let groupCount: Int

  /// The rail for `labels`, in at most `available` points of height.
  public init(labels: [String], available: CGFloat) {
    groupCount = labels.count
    guard !labels.isEmpty else {
      rows = []
      height = 0
      return
    }
    let count = CGFloat(labels.count)
    var texts = labels
    var rowHeight = Self.idealRowHeight
    if count * Self.idealRowHeight > available {
      rowHeight = available / count
    }
    if rowHeight < Self.minimumRowHeight {
      // An odd number of rows, so both ends are letters, alternating with dots.
      var shown = max(1, Int(available / Self.minimumRowHeight))
      if shown.isMultiple(of: 2) { shown -= 1 }
      texts = (0..<shown).map { row in
        guard row.isMultiple(of: 2) else { return Self.dot }
        guard shown > 1 else { return labels[0] }
        let share = Double(row) / Double(shown - 1) * Double(labels.count - 1)
        return labels[Int(share.rounded())]
      }
      rowHeight = available / CGFloat(shown)
    }
    rows = texts.enumerated().map { row in
      Row(text: row.element, center: (CGFloat(row.offset) + 0.5) * rowHeight)
    }
    height = CGFloat(texts.count) * rowHeight
  }

  /// The group a point at `y` falls on: its share of the rail, whatever the rows
  /// show, clamped to the ends, so a drag past the rail stays on the first or last
  /// group. Nil for a rail without groups.
  public func group(at y: CGFloat) -> Int? {
    guard groupCount > 0, height > 0 else { return nil }
    let share = Int((y / height * CGFloat(groupCount)).rounded(.down))
    return min(max(share, 0), groupCount - 1)
  }

  /// Where the rail's center goes across a view `viewWidth` wide whose text column is
  /// `column` wide and centered: in the middle of the trailing gutter, less what
  /// covers its edge (macOS's overlay scroller, iOS's safe area); where that leaves
  /// less than the rail's width, the rail keeps its width against that edge.
  public static func centerX(viewWidth: CGFloat, column: CGFloat, trailingObstruction: CGFloat)
    -> CGFloat
  {
    let gutter = (viewWidth - column) / 2
    let room = max(gutter - trailingObstruction, width)
    return viewWidth - trailingObstruction - room / 2
  }
}

/// Typing to an index, as one types to a list in the Finder: the characters typed in
/// quick succession select the first entry they start, or the entry where the
/// typed term would be.
public struct IndexTypeSelect {
  /// How long a pause starts a new buffer, as `NSTableView`'s does.
  public static let timeout: TimeInterval = 1

  public private(set) var buffer = ""
  private var lastKey = -TimeInterval.infinity

  public init() {}

  /// Takes `characters` typed at `time` (seconds, any clock that only moves on),
  /// answering whether they are type-select's. A letter or digit always is; a space
  /// or punctuation only extends a buffer that holds something, so a space with
  /// nothing typed still pages; a control or function key never is.
  public mutating func type(_ characters: String, at time: TimeInterval) -> Bool {
    if time - lastKey > Self.timeout { buffer = "" }
    guard let first = characters.first,
      characters.allSatisfy({ !$0.isNewline && $0 != "\t" && !Self.isFunctionKey($0) })
    else { return false }
    guard !buffer.isEmpty || first.isLetter || first.isNumber else { return false }
    buffer += characters
    lastKey = time
    return true
  }

  /// The entry the buffer selects among `keys`, the entries' keys (`IndexMap.key`)
  /// in index order: the first the buffer starts, or else the first that sorts after
  /// it, or else the last. Nil with nothing typed or no entries.
  public func match(in keys: [String]) -> Int? {
    let typed = IndexMap.key(buffer)
    guard !typed.isEmpty, !keys.isEmpty else { return nil }
    return keys.firstIndex { $0.hasPrefix(typed) }
      ?? keys.firstIndex { $0 > typed }
      ?? keys.count - 1
  }

  /// AppKit's arrow and function keys arrive as characters in the private use area,
  /// U+F700 to U+F8FF.
  private static func isFunctionKey(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
  }
}
