import Foundation
import RFCKit

/// The text an annotation's position counts in: the document **model's**, never the
/// storage's, which adds section numbers, list markers, chip characters and stacked
/// table labels of its own and changes with the column (#522). What each element's
/// text is, is fixed by the design ("The model text", in
/// `docs/superpowers/specs/2026-09-30-highlights-and-notes-design.md`), and this is
/// its one implementation.
///
/// The whole document is one string, so that every anchor is a range of it: the
/// abstract, then every section the reader draws in document order, each its own
/// text, set apart by a newline that belongs to no anchor. A section's text holds its
/// heading and its own blocks, not its subsections, which follow it. An anchor's text
/// holds the text of every anchored block inside it, so the anchors nest, and a
/// position under one is a position under each anchor around it.
///
/// Offsets inside are UTF-16 units, as the storage's are; a `Position` counts Unicode
/// scalars into its anchor's text, and converts at the edge (`position(at:isEnd:)`,
/// `offset(of:)`).
public struct ModelText: Sendable {
  /// One anchor, and the range of the text it holds.
  public struct Span: Sendable, Hashable {
    public let anchor: String
    public let range: Range<Int>
    /// The span this one lies inside, as an index into `spans`; nil at the top.
    public let parent: Int?
    /// Whether this is a section's span, or the abstract's: what a search widens to
    /// after the anchor itself (`Relocation`).
    public let isSection: Bool
  }

  /// The text, as UTF-16 units.
  public let units: [UInt16]
  /// Every anchor's span, by where it starts, an outer span ahead of an inner one that
  /// starts with it.
  public let spans: [Span]
  private let spanIndex: [String: Int]

  /// The abstract's anchor, as the builder marks it.
  public static let abstractAnchor = DocumentTextBuilder.abstractAnchor

  public init(_ document: RFCDocument) {
    var writer = Writer()
    writer.write(document)
    self.init(units: writer.units, spans: writer.spans)
  }

  init(units: [UInt16], spans: [Span]) {
    self.units = units
    self.spans = spans
    var index: [String: Int] = [:]
    for (offset, span) in spans.enumerated() where index[span.anchor] == nil {
      index[span.anchor] = offset
    }
    spanIndex = index
  }

  public var length: Int { units.count }

  /// The text in `range`.
  public func text(in range: Range<Int>) -> String {
    let clamped = range.clamped(to: 0..<units.count)
    return String(decoding: units[clamped], as: UTF16.self)
  }

  /// The span of `anchor`, or nil when the document has no such anchor, or the
  /// reader does not draw it (a bibliography's).
  public func span(of anchor: String) -> Span? {
    spanIndex[anchor].map { spans[$0] }
  }

  /// The section, or the abstract, whose own text holds `offset`.
  public func section(containing offset: Int) -> Span? {
    var index = innermost(containing: offset, isEnd: false)
    while let current = index {
      if spans[current].isSection { return spans[current] }
      index = spans[current].parent
    }
    return nil
  }

  /// The innermost span holding `offset`: a start holds the character at it, an end
  /// the character before it, so a range that ends where a paragraph does ends in the
  /// paragraph, not in the join after it.
  func innermost(containing offset: Int, isEnd: Bool) -> Int? {
    // The last span to start at or before the offset (before it, for an end), then
    // out through the spans around it. The spans nest, so the innermost one holding
    // the offset is around that one, or is it.
    let after = spans.partitioningIndex { span in
      isEnd ? span.range.lowerBound >= offset : span.range.lowerBound > offset
    }
    var index = after > 0 ? after - 1 : nil
    while let current = index {
      let range = spans[current].range
      let holds =
        isEnd
        ? range.lowerBound < offset && offset <= range.upperBound
        : range.lowerBound <= offset && offset < range.upperBound
      if holds { return current }
      index = spans[current].parent
    }
    return nil
  }

  /// The position at `offset`, under the innermost anchor that holds it, or nil
  /// where no anchor does: the newline between two sections.
  public func position(at offset: Int, isEnd: Bool) -> Position? {
    guard let index = innermost(containing: offset, isEnd: isEnd) else { return nil }
    let span = spans[index]
    return Position(
      anchor: span.anchor, offset: scalars(in: span.range.lowerBound..<offset))
  }

  /// The position at `offset`, under `anchor` rather than the innermost one, or nil
  /// when the anchor does not hold it.
  public func position(at offset: Int, under anchor: String) -> Position? {
    guard let span = span(of: anchor), span.range.lowerBound <= offset,
      offset <= span.range.upperBound
    else { return nil }
    return Position(anchor: anchor, offset: scalars(in: span.range.lowerBound..<offset))
  }

  /// Where `position` is in the text, or nil when its anchor is gone or its offset
  /// runs past the anchor's text.
  public func offset(of position: Position) -> Int? {
    guard let span = span(of: position.anchor), position.offset >= 0 else { return nil }
    var offset = span.range.lowerBound
    var remaining = position.offset
    while remaining > 0 {
      guard offset < span.range.upperBound else { return nil }
      offset += UTF16.isLeadSurrogate(units[offset]) ? 2 : 1
      remaining -= 1
    }
    return offset
  }

  /// How many Unicode scalars the units in `range` hold.
  func scalars(in range: Range<Int>) -> Int {
    var count = 0
    for index in range where !UTF16.isTrailSurrogate(units[index]) {
      count += 1
    }
    return count
  }
}

/// A place in a document's model text: an anchor, and how many Unicode scalars into
/// that anchor's text (`ModelText`). The anchor is the innermost one holding the
/// place, so a block gaining an anchor of its own leaves every position into its
/// section valid.
public struct Position: Sendable, Hashable, Codable {
  public var anchor: String
  public var offset: Int

  public init(anchor: String, offset: Int) {
    self.anchor = anchor
    self.offset = offset
  }
}

extension ModelText {
  /// Writes the model text, element by element, as the design defines it.
  struct Writer {
    var units: [UInt16] = []
    var spans: [Span] = []
    /// The spans being written, innermost last, as indexes into `spans`.
    private var open: [Int] = []
    /// Whether anything has been written at the top level, so the next section is
    /// set apart from it.
    private var hasUnit = false

    mutating func write(_ document: RFCDocument) {
      if !document.header.abstract.isEmpty {
        hasUnit = true
        anchored(ModelText.abstractAnchor, isSection: true) {
          $0.blocks(document.header.abstract)
        }
      }
      for section in document.sections {
        write(section)
      }
    }

    /// A section the reader draws: its own text, then each subsection's after it.
    /// One the reader leaves out, a bibliography, is left out with everything in it,
    /// as `DocumentTextBuilder.appendSection` leaves it.
    private mutating func write(_ section: Section) {
      guard !section.holdsOnlyReferences else { return }
      if hasUnit { text("\n") }
      hasUnit = true
      anchored(section.anchor, isSection: true) { writer in
        writer.text(section.title.plainText)
        writer.text("\n")
        writer.blocks(section.blocks)
      }
      for subsection in section.subsections {
        write(subsection)
      }
    }

    /// Blocks, joined by newlines. A bibliography's list is no part of the text.
    mutating func blocks(_ blocks: [Block]) {
      var first = true
      for block in blocks {
        if case .references = block { continue }
        if !first { text("\n") }
        first = false
        self.block(block)
      }
    }

    private mutating func block(_ block: Block) {
      switch block {
      case .paragraph(let paragraph):
        anchored(paragraph.anchor) { $0.text(paragraph.plainText) }
      case .list(let list):
        for (index, item) in list.items.enumerated() {
          if index > 0 { text("\n") }
          anchored(item.anchor) { $0.blocks(item.blocks) }
        }
      case .definitionList(let list):
        for (index, item) in list.items.enumerated() {
          if index > 0 { text("\n") }
          anchored(item.anchor) { writer in
            writer.text(item.term.plainText)
            writer.text("\n")
            writer.anchored(item.definitionAnchor) { $0.blocks(item.definition) }
          }
        }
      case .preformatted(let content):
        anchored(content.anchor) { $0.text(content.text) }
      case .figure(let figure):
        anchored(figure.anchor) { writer in
          if let title = figure.title {
            writer.text(title)
            writer.text("\n")
          }
          writer.blocks(figure.blocks)
        }
      case .table(let table):
        anchored(table.anchor) { writer in
          for (index, row) in (table.header + table.rows).enumerated() {
            if index > 0 { writer.text("\n") }
            writer.anchored(row.anchor) { writer in
              for (column, cell) in row.cells.enumerated() {
                if column > 0 { writer.text("\t") }
                writer.text(cell.plainText)
              }
            }
          }
        }
      case .blockQuote(let inner), .aside(let inner):
        blocks(inner)
      case .references:
        break
      case .index(let index):
        blocks(DocumentTextBuilder.plainBlocks(of: index))
      }
    }

    mutating func text(_ string: String) {
      units.append(contentsOf: string.utf16)
    }

    /// Writes `body` inside a span of `anchor`'s, or as it is when there is none.
    private mutating func anchored(
      _ anchor: String?, isSection: Bool = false, _ body: (inout Writer) -> Void
    ) {
      guard let anchor, !anchor.isEmpty else {
        body(&self)
        return
      }
      let start = units.count
      let index = spans.count
      spans.append(Span(anchor: anchor, range: start..<start, parent: open.last, isSection: isSection))
      open.append(index)
      body(&self)
      open.removeLast()
      spans[index] = Span(
        anchor: anchor, range: start..<units.count, parent: spans[index].parent,
        isSection: isSection)
    }
  }
}
