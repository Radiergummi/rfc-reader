import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A redline (#729): the newer of two revisions, with what changed since the older
/// marked in the one text storage, as `RevisionDiff` says it. Inserted text is tinted
/// and underlined; deleted text is struck through, quieter, and `.rfcReaderOnly`, so a
/// copy gives the newer text. A section added, moved or removed says so under its
/// heading, in words that are the reader's, as a backlink caption's are.
extension DocumentTextBuilder {
  /// What a run of the redline is.
  enum RedlineMark {
    case inserted
    case deleted
  }

  /// A section's top-level blocks, each as `redline` says it changed, with the
  /// blocks that went before the ones they stood before.
  func appendRedline(_ blocks: [Block], of section: String, in redline: RevisionDiff) {
    for (index, block) in blocks.enumerated() {
      let key = RevisionDiff.BlockKey(section: section, index: index)
      appendRemoved(redline.removedBlocks[key] ?? [])
      switch redline.blocks[key] {
      case nil:
        appendBlocks([block], indent: 0)
      case .inserted:
        marking(.inserted) { appendBlocks([block], indent: 0) }
      case .reworded(let runs):
        guard case .paragraph(let paragraph) = block else {
          appendBlocks([block], indent: 0)
          continue
        }
        appendReworded(paragraph, runs: runs)
      case .replaced(let old):
        appendRemoved([old])
        marking(.inserted) { appendBlocks([block], indent: 0) }
      }
    }
    appendRemoved(
      redline.removedBlocks[RevisionDiff.BlockKey(section: section, index: blocks.count)] ?? [])
  }

  /// Blocks of the older revision, struck through, and with none of their anchors in
  /// the index: they are not in the newer document, whose anchors they may share.
  private func appendRemoved(_ blocks: [Block]) {
    guard !blocks.isEmpty else { return }
    asOlder { marking(.deleted) { appendBlocks(blocks, indent: 0) } }
  }

  /// Takes the links to places in the document out of `range`, which is the older
  /// revision's: they name its places, which the newer one, whose anchors are the
  /// index, may number otherwise, as a text draft's section anchors are numbers.
  private func unlinkPlaces(in range: NSRange) {
    output.enumerateAttribute(.link, in: range) { value, run, _ in
      guard let value, let url = ReaderLinkScheme.url(fromLink: value),
        ReaderLinkScheme.anchor(from: url) != nil
      else { return }
      output.removeAttribute(.link, range: run)
    }
  }

  /// Where the older revision's ordinals start, past any the newer one's reach: a
  /// choice made in a struck figure's menu is its own, not the newer figure's.
  static let olderOrdinalBase = 1 << 30

  /// Emits what `body` emits of the older revision, and leaves the builder's count of
  /// the newer one's as it was: its anchors out of the index, and the ordinals a
  /// block's presentation choice and an aside's opening are keyed by, the grammar
  /// rules defined and the abbreviations marked, which the newer blocks go by. Its
  /// own blocks number from `olderOrdinalBase`.
  private func asOlder(_ body: () -> Void) {
    let entriesBefore = entries.count
    let verbatimOrdinal = nextVerbatimOrdinal
    let asideOrdinal = nextAsideOrdinal
    let rules = definedRules
    let glossed = glossedInSection
    nextVerbatimOrdinal = Self.olderOrdinalBase + olderOrdinals.verbatim
    nextAsideOrdinal = Self.olderOrdinalBase + olderOrdinals.aside
    body()
    olderOrdinals = (
      nextVerbatimOrdinal - Self.olderOrdinalBase, nextAsideOrdinal - Self.olderOrdinalBase
    )
    entries.removeSubrange(entriesBefore...)
    nextVerbatimOrdinal = verbatimOrdinal
    nextAsideOrdinal = asideOrdinal
    definedRules = rules
    glossedInSection = glossed
  }

  /// A paragraph whose words changed, as its runs: its words only, since the runs
  /// are of its plain text, so a link or emphasis in it is set as text.
  private func appendReworded(_ paragraph: Paragraph, runs: [WordDiff.Run]) {
    let authoredSteps = CGFloat(Self.authoredIndentSteps(forCharacters: paragraph.indent))
    let attributes = bodyAttributes(indent: authoredSteps * style.indentStep)
    mark(paragraph.anchor)
    for (index, run) in runs.enumerated() {
      let start = output.length
      append(run.text, attributes)
      // A word struck through and its replacement would run together: a space
      // between them, the reader's, which a copy leaves out with the deletion.
      if case .deleted = run, index + 1 < runs.count, case .inserted = runs[index + 1],
        run.text.last?.isWhitespace == false
      {
        append(" ", attributes)
      }
      let range = NSRange(location: start, length: output.length - start)
      switch run {
      case .same: break
      case .inserted: mark(.inserted, range)
      case .deleted: mark(.deleted, range)
      }
    }
    append("\n", attributes)
  }

  /// Under a heading: "Added", or "Moved from section 4.2", where the redline says
  /// either of its section.
  func appendRedlineCaption(for section: String) {
    let change = redline?.sections[section]
    var parts: [String] = []
    switch change {
    case .added: parts.append("Added in this revision")
    case .moved(let number): parts.append(number.map { "Moved from section \($0)" } ?? "Moved")
    case nil: break
    }
    if let old = redline?.retitled[section] { parts.append("Retitled from \u{201C}\(old)\u{201D}") }
    guard !parts.isEmpty else { return }
    let caption = parts.joined(separator: ". ")
    let start = output.length
    append(
      caption + "\n",
      captionAttributes(paragraphStyle(spacingAfter: style.paragraphSpacing * 0.6))
        .merging([.rfcReaderOnly: ""]) { _, new in new })
    if case .added = change {
      output.addAttribute(
        .foregroundColor, value: RFCColors.inserted,
        range: NSRange(location: start, length: output.length - start))
    }
  }

  /// The sections of the older revision that went after the newer section `anchor`
  /// names, or before the first for nil, in the older revision's order.
  func removedSections(after anchor: String?) -> [Section] {
    redline?.removedSections.filter { $0.after == anchor }.map(\.section) ?? []
  }

  /// `sections` of the older revision that went: each its heading and its own blocks
  /// struck through, said removed. Not its subsections, which are listed for
  /// themselves.
  func appendRemovedSections(_ sections: some Sequence<Section>) {
    for section in sections {
      let start = output.length
      append(
        section.displayTitle + "\n",
        [
          .font: style.headingFont(depth: min(section.depth, 3)),
          .foregroundColor: labelColor,
          .paragraphStyle: paragraphStyle(
            spacingBefore: style.paragraphSpacing * 1.6, spacingAfter: style.paragraphSpacing * 0.15
          ),
        ])
      mark(.deleted, NSRange(location: start, length: output.length - start))
      append(
        "Removed in this revision\n",
        captionAttributes(paragraphStyle(spacingAfter: style.paragraphSpacing * 0.6))
          .merging([.rfcReaderOnly: ""]) { _, new in new })
      asOlder { marking(.deleted) { appendBlocks(section.blocks, indent: 0) } }
    }
  }

  /// Emits `body`, then marks what it emitted.
  private func marking(_ kind: RedlineMark, _ body: () -> Void) {
    let start = output.length
    body()
    mark(kind, NSRange(location: start, length: output.length - start))
  }

  /// Marks `range` as `kind`: underlined in the inserted color, or struck through in
  /// the secondary color and left out of a copy. A character a decorated block draws
  /// over keeps its own color, which hides it.
  private func mark(_ kind: RedlineMark, _ range: NSRange) {
    guard range.length > 0 else { return }
    let color: PlatformColor
    switch kind {
    case .inserted:
      color = RFCColors.inserted
      output.addAttributes(
        [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: color], range: range)
    case .deleted:
      color = secondaryLabelColor
      unlinkPlaces(in: range)
      output.addAttributes(
        [
          .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: color,
          .rfcReaderOnly: "",
        ], range: range)
    }
    output.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
      guard (value as? PlatformColor) != Self.hiddenColor else { return }
      output.addAttribute(.foregroundColor, value: color, range: run)
    }
  }
}
