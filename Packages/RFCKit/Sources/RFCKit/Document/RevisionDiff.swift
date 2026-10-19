import Foundation

/// What changed from one document to another (#729): two revisions of a draft, or a
/// draft and the RFC it became. Read as a redline of the newer one, so everything here
/// is said of the newer document's sections and blocks, and what went is said where it
/// stood.
///
/// Sections are paired by anchor and title first: an author's anchor survives a
/// revision, but a text draft's, or an unnamed XML section's, is its number, which
/// an inserted section moves on, so an anchor alone pairs by position. The rest are
/// paired as `SectionAlignment` pairs an RFC with its successor, by title and prose,
/// one to one, the best first. A pair whose title changed is retitled. A paired section whose place in the order changed is
/// moved; one left over in the newer document is added, in the older removed.
///
/// Within a pair of sections, the top-level blocks are matched by their text, and
/// what is left between two matched blocks is paired in order where both are of a
/// kind: two paragraphs are reworded, word by word (`WordDiff`); any other two are
/// replaced, the old shown above the new, since a figure or code block diffed inside
/// reads as noise. A block of the newer document that pairs with none is inserted,
/// one of the older removed.
public struct RevisionDiff: Sendable, Equatable {
  /// A top-level block of a section, by the section's anchor and the block's index.
  public struct BlockKey: Hashable, Sendable {
    public var section: String
    public var index: Int

    public init(section: String, index: Int) {
      self.section = section
      self.index = index
    }
  }

  /// What became of a block of the newer document.
  public enum BlockChange: Hashable, Sendable {
    /// New in this revision.
    case inserted
    /// A paragraph whose words changed: the runs from the old to the new.
    case reworded([WordDiff.Run])
    /// Any other block that changed: the old one, shown above it.
    case replaced(Block)
  }

  /// What became of a section of the newer document, where anything did.
  public enum SectionChange: Hashable, Sendable {
    /// New in this revision.
    case added
    /// Here, and elsewhere in the older one: under its number there, if it had one
    /// other than its number here.
    case moved(from: String?)
  }

  /// A section of the older document that is gone, and the newer section it stood
  /// after: nil before the first.
  public struct RemovedSection: Hashable, Sendable {
    public var section: Section
    public var after: String?
  }

  public private(set) var sections: [String: SectionChange] = [:]
  public private(set) var blocks: [BlockKey: BlockChange] = [:]
  /// Blocks of the older document that are gone, before the newer block they stood
  /// before: a section's count of blocks for after its last.
  public private(set) var removedBlocks: [BlockKey: [Block]] = [:]
  public private(set) var removedSections: [RemovedSection] = []
  /// Sections of the newer document whose heading changed, with the older heading.
  public private(set) var retitled: [String: String] = [:]
  /// The key the abstract's blocks are compared under, as a section's are.
  public static let abstractKey = "abstract"

  /// Whether nothing changed.
  public var isEmpty: Bool {
    sections.isEmpty && blocks.isEmpty && removedBlocks.isEmpty && removedSections.isEmpty
      && retitled.isEmpty
  }

  public init(from old: RFCDocument, to new: RFCDocument) {
    let oldSections = old.allSections.filter { !$0.holdsOnlyReferences }
    let newSections = new.allSections.filter { !$0.holdsOnlyReferences }
    compare(old.header.abstract, new.header.abstract, in: Self.abstractKey)
    let pairs = Self.pair(oldSections, newSections, old: old, new: new)
    let oldByAnchor = Dictionary(
      oldSections.map { ($0.anchor, $0) }, uniquingKeysWith: { first, _ in first })

    // Moved: a pair outside the longest run of pairs that keeps the older order.
    let oldOrder = Dictionary(
      oldSections.enumerated().map { ($1.anchor, $0) }, uniquingKeysWith: { first, _ in first })
    let pairedInOrder = newSections.compactMap { section in
      pairs[section.anchor].flatMap { oldOrder[$0] }.map { (section.anchor, $0) }
    }
    let kept = Set(Self.longestIncreasing(pairedInOrder.map(\.1)).map { pairedInOrder[$0].0 })

    var pairedOld: Set<String> = []
    for section in newSections {
      if let oldAnchor = pairs[section.anchor], let oldSection = oldByAnchor[oldAnchor] {
        pairedOld.insert(oldAnchor)
        if !kept.contains(section.anchor) {
          // Its number there, unless it kept it.
          let number = oldSection.number == section.number ? nil : oldSection.number
          sections[section.anchor] = .moved(from: number)
        }
        compare(oldSection.blocks, section.blocks, in: section.anchor)
        if oldSection.displayTitle != section.displayTitle,
          oldSection.titleText != section.titleText
        {
          retitled[section.anchor] = oldSection.displayTitle
        }
      } else {
        sections[section.anchor] = .added
      }
    }

    // Each removed section after the newer counterpart of the older one before it.
    var lastPaired: String?
    let newOf = Dictionary(pairs.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    for section in oldSections {
      if pairedOld.contains(section.anchor) {
        lastPaired = newOf[section.anchor]
      } else {
        removedSections.append(RemovedSection(section: section, after: lastPaired))
      }
    }
  }

  /// Newer section anchor to older: by anchor, then by `SectionAlignment`, one to one.
  private static func pair(
    _ oldSections: [Section], _ newSections: [Section], old: RFCDocument, new: RFCDocument
  ) -> [String: String] {
    let oldAnchors = Set(oldSections.map(\.anchor))
    let oldTitles = Dictionary(
      oldSections.map { ($0.anchor, $0.titleText) }, uniquingKeysWith: { first, _ in first })
    var pairs: [String: String] = [:]
    var takenOld: Set<String> = []
    for section in newSections where oldTitles[section.anchor] == section.titleText {
      pairs[section.anchor] = section.anchor
      takenOld.insert(section.anchor)
    }
    let newAnchors = Set(newSections.map(\.anchor))
    for candidate in SectionAlignment.candidates(from: old, to: new)
    where pairs[candidate.newSection] == nil && !takenOld.contains(candidate.oldSection)
      && newAnchors.contains(candidate.newSection) && oldAnchors.contains(candidate.oldSection)
    {
      pairs[candidate.newSection] = candidate.oldSection
      takenOld.insert(candidate.oldSection)
    }
    return pairs
  }

  /// The blocks of one pair of sections, matched by their text.
  private mutating func compare(_ old: [Block], _ new: [Block], in section: String) {
    let oldKeys = old.map(Self.fingerprint)
    let newKeys = new.map(Self.fingerprint)
    let difference = newKeys.difference(from: oldKeys)
    var removed: Set<Int> = []
    var inserted: Set<Int> = []
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    // Walk both in order, a gap at a time: the unmatched old and new blocks between
    // two matched ones.
    var oldIndex = 0
    var newIndex = 0
    while oldIndex < old.count || newIndex < new.count {
      var gone: [Int] = []
      var came: [Int] = []
      while oldIndex < old.count, removed.contains(oldIndex) {
        gone.append(oldIndex)
        oldIndex += 1
      }
      while newIndex < new.count, inserted.contains(newIndex) {
        came.append(newIndex)
        newIndex += 1
      }
      settle(gone: gone.map { old[$0] }, came: came, in: new, section: section, before: newIndex)
      if oldIndex < old.count, newIndex < new.count, !removed.contains(oldIndex),
        !inserted.contains(newIndex)
      {
        oldIndex += 1
        newIndex += 1
      } else if gone.isEmpty, came.isEmpty {
        // Nothing matched and nothing left on one side: the rest of the other.
        if oldIndex < old.count {
          oldIndex += 1
        } else {
          newIndex += 1
        }
      }
    }
  }

  /// One gap: pairs its blocks in order where both are of a kind, and says the rest
  /// inserted or removed, the removed before the newer block at `before`.
  private mutating func settle(
    gone: [Block], came: [Int], in new: [Block], section: String, before: Int
  ) {
    var leftOver: [Block] = []
    var remaining = came[...]
    for block in gone {
      guard let index = remaining.first, Self.kind(of: new[index]) == Self.kind(of: block) else {
        leftOver.append(block)
        continue
      }
      remaining = remaining.dropFirst()
      let key = BlockKey(section: section, index: index)
      if case .paragraph(let oldParagraph) = block, case .paragraph(let newParagraph) = new[index] {
        blocks[key] = .reworded(
          WordDiff.runs(from: oldParagraph.plainText, to: newParagraph.plainText))
      } else {
        blocks[key] = .replaced(block)
      }
    }
    for index in remaining {
      blocks[BlockKey(section: section, index: index)] = .inserted
    }
    if !leftOver.isEmpty {
      // Before the first of the gap's newer blocks, or the matched one after it.
      let position = came.first ?? before
      removedBlocks[BlockKey(section: section, index: position), default: []] += leftOver
    }
  }

  /// What a block is matched by: its text, whitespace as one space, with no anchor,
  /// which a revision renumbers.
  static func fingerprint(_ block: Block) -> String {
    let parts = [block].flattened.flatMap { block -> [String] in
      switch block {
      case .preformatted(let content): [content.text]
      case .figure(let figure): [figure.title ?? ""]
      default: block.proseRuns.map(\.plainText)
      }
    }
    return "\(kind(of: block))|"
      + parts.joined(separator: "\u{1F}").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  private static func kind(of block: Block) -> Int {
    switch block {
    case .paragraph: 0
    case .list: 1
    case .definitionList: 2
    case .preformatted: 3
    case .figure: 4
    case .table: 5
    case .blockQuote: 6
    case .aside: 7
    case .references: 8
    case .index: 9
    }
  }

  /// The indices of a longest strictly increasing run of `values`, in order.
  static func longestIncreasing(_ values: [Int]) -> [Int] {
    guard !values.isEmpty else { return [] }
    var tails: [Int] = []
    var previous = [Int](repeating: -1, count: values.count)
    for (index, value) in values.enumerated() {
      var low = 0
      var high = tails.count
      while low < high {
        let middle = (low + high) / 2
        if values[tails[middle]] < value { low = middle + 1 } else { high = middle }
      }
      if low > 0 { previous[index] = tails[low - 1] }
      if low == tails.count { tails.append(index) } else { tails[low] = index }
    }
    var run: [Int] = []
    var index = tails.last ?? -1
    while index >= 0 {
      run.append(index)
      index = previous[index]
    }
    return run.reversed()
  }
}
