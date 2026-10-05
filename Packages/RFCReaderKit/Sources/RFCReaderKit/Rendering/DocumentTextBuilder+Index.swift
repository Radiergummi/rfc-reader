import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  /// An index set as one (the design's part 3): each group's letter on a line of its
  /// own, small and tracked; each entry a line of its term and its locators, the
  /// primary first and semibold, wrapped lines hanging one step in; subentries one
  /// step deeper. The row of letter links prep writes is left out: the A–Z rail over
  /// the reader replaces it. Records where everything went, as `indexMap`.
  ///
  /// A document has one index; a second would set the same way, and the map keeps
  /// the first.
  func appendIndex(_ index: IndexBlock, indent: CGFloat) {
    let start = output.length
    mark(IndexBlock.anchor)
    var groups: [IndexMap.Group] = []
    var entries: [IndexMap.Entry] = []
    for (position, group) in index.groups.enumerated() {
      mark(group.anchor)
      let labelStart = output.length
      appendIndexLabel(group, indent: indent, isFirst: position == 0)
      groups.append(
        IndexMap.Group(
          label: group.label, anchor: group.anchor,
          labelRange: NSRange(location: labelStart, length: (group.label as NSString).length)))
      for entry in group.entries {
        let termRange = appendIndexEntry(entry, indent: indent)
        entries.append(
          IndexMap.Entry(key: IndexMap.key(entry.term.plainText), termRange: termRange))
      }
    }
    guard indexMap.isEmpty else { return }
    indexMap = IndexMap(
      range: NSRange(location: start, length: output.length - start), groups: groups,
      entries: entries)
  }

  /// A group's letter: small, tracked and secondary, as an aside's caption is, not
  /// heading chrome. It carries the group's anchor as a heading does, so the headings
  /// rotor steps through the letters.
  private func appendIndexLabel(_ group: IndexBlock.Group, indent: CGFloat, isFirst: Bool) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: style.captionFont,
      .foregroundColor: RFCColors.secondaryLabel,
      // Set solid: the body's line height would add leading above one short line.
      .paragraphStyle: paragraphStyle(
        indent: indent, spacingBefore: isFirst ? 0 : style.paragraphSpacing,
        spacingAfter: style.paragraphSpacing * 0.3, lineHeightMultiple: 1),
      .rfcAnchor: group.anchor,
    ].merging(Self.headingLevel(depth: 2)) { current, _ in current }
    var label = attributes
    label[.kern] = style.captionFont.pointSize * 0.08
    append(group.label, label)
    append("\n", attributes)
  }

  /// An entry's line and its subentries'; answers where its term is.
  @discardableResult
  private func appendIndexEntry(_ entry: IndexBlock.Entry, indent: CGFloat) -> NSRange {
    let attributes = bodyAttributes(
      paragraphStyle(indent: indent + style.indentStep, firstLineIndent: indent, spacingAfter: 0))
    let termStart = output.length
    output.append(inlineRuns(entry.term, base: attributes))
    let termRange = NSRange(location: termStart, length: output.length - termStart)
    let locators = entry.locators.filter(\.isPrimary) + entry.locators.filter { !$0.isPrimary }
    for (position, locator) in locators.enumerated() {
      // EM SPACE between the term and its places; a comma between places.
      append(position == 0 ? "\u{2003}" : ", ", attributes)
      var reference = locator.reference
      reference.text = IndexLocatorLabel.short(reference.label)
      var base = attributes
      if locator.isPrimary {
        base[.font] = PlatformFont.systemFont(ofSize: style.bodySize, weight: .semibold)
      }
      output.append(inlineRuns([.crossReference(reference)], base: base))
    }
    append("\n", attributes)
    for subentry in entry.subentries {
      appendIndexEntry(subentry, indent: indent + style.indentStep)
    }
    return termRange
  }
}
