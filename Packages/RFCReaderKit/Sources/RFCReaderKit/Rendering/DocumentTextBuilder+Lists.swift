import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  func appendList(_ list: ListBlock, indent: CGFloat) {
    // Measured once for the list, as a grid table's columns are, and each distinct
    // marker once: every item then hangs its marker in the same column.
    let markers = list.items.indices.map { Self.marker(for: list.style, at: $0) }
    let markerFont = style.bodyFont
    let markerWidths = Set(markers).map { lineWidth($0, font: markerFont) }
    let markerColumn =
      indent
      + Self.markerColumnWidth(
        markerWidths: markerWidths, gap: style.bodySize * Self.markerGapShare,
        step: style.indentStep, limit: (style.measure - indent) * Self.markerColumnShare)
    // Every item of one list shares its indents and spacing, so both dictionaries
    // and the tab stop are built once for the list rather than once per item.
    let spacing = itemSpacing(isCompact: list.isCompact)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: markerFont,
      .foregroundColor: bodyColor,
      .paragraphStyle: paragraphStyle(
        indent: markerColumn,
        firstLineIndent: indent,
        spacingAfter: spacing,
        tabStops: [NSTextTab(textAlignment: .left, location: markerColumn)]
      ),
    ]
    // The marker is drawn at the outer indent, left of the tab stop at
    // markerColumn, so the tab advances to it and a wrapped item lines up
    // under its own text rather than under the bullet.
    var markerAttributes = attributes
    markerAttributes[.foregroundColor] = RFCColors.secondaryLabel

    for (index, item) in list.items.enumerated() {
      mark(item.anchor)
      let marker = markers[index]
      let firstLine = NSMutableAttributedString(string: marker + "\t", attributes: markerAttributes)

      guard let first = item.blocks.first else {
        output.append(firstLine)
        append("\n", attributes)
        continue
      }
      output.append(firstLine)
      if case .paragraph(let paragraph) = first {
        // On the marker's line, in the list's attributes rather than its own indent.
        appendParagraph(paragraph, attributes: attributes)
        appendBlocks(Array(item.blocks.dropFirst()), indent: markerColumn)
      } else {
        append("\n", attributes)
        appendBlocks(item.blocks, indent: markerColumn)
      }
    }
  }

  func appendDefinitionList(_ list: DefinitionList, indent: CGFloat) {
    let spacing = itemSpacing(isCompact: list.isCompact)
    let termAttributes: [NSAttributedString.Key: Any] = [
      .font: style.boldBodyFont,
      .foregroundColor: bodyColor,
      .paragraphStyle: paragraphStyle(
        indent: indent, spacingAfter: list.isCompact ? 0 : style.paragraphSpacing * 0.3),
    ]
    let hanging =
      list.hangsTerms
      ? hangingTerms(list, indent: indent, spacing: spacing, base: termAttributes) : nil
    // A term that does not hang sets its definition under it, one step in; in a list
    // whose other terms hang, at their gutter, so the definitions share one edge.
    let definitionIndent = hanging?.gutter ?? indent + style.indentStep
    let compactAttributes = bodyAttributes(
      paragraphStyle(indent: definitionIndent, spacingAfter: spacing))

    for (index, item) in list.items.enumerated() {
      mark(item.anchor)
      // The term beside its definition's first paragraph, in one paragraph, when it
      // fits the gutter; otherwise on a line of its own, so one long term does not
      // push every definition in the list across (#352).
      if let hanging, hanging.fits[index], case .paragraph(let first)? = item.definition.first {
        output.append(inlineRuns(item.term, base: hanging.termAttributes))
        append("\t", hanging.termAttributes)
        mark(item.definitionAnchor)
        appendParagraph(first, attributes: hanging.attributes)
        appendBlocks(Array(item.definition.dropFirst()), indent: hanging.gutter)
        continue
      }
      output.append(inlineRuns(item.term, base: termAttributes))
      // A definition's own anchor goes where its text starts. An empty `<dd>`
      // has no text, and marking it after the term's newline would put it at the
      // next item's term, so a link to it would land one item late; the end of
      // its own term keeps it on the item it belongs to.
      if item.definition.isEmpty { mark(item.definitionAnchor) }
      append("\n", termAttributes)
      if !item.definition.isEmpty { mark(item.definitionAnchor) }
      if list.isCompact, case .paragraph(let first)? = item.definition.first, first.indent == 0 {
        // A compact list's spacing, as a compact list item's first paragraph takes it.
        // An author's indent keeps the ordinary paragraph's, which sets it.
        appendParagraph(first, attributes: compactAttributes)
        appendBlocks(Array(item.definition.dropFirst()), indent: definitionIndent)
      } else {
        appendBlocks(item.definition, indent: definitionIndent)
      }
    }
  }

  /// The space after a list's item, or a definition list's: a paragraph's, or in a
  /// compact list (RFCXML's `spacing="compact"`) about a third of it.
  func itemSpacing(isCompact: Bool) -> CGFloat {
    isCompact ? style.paragraphSpacing * 0.35 : style.paragraphSpacing
  }

  /// A hanging list's gutter, which of its terms hang there, and the attributes those
  /// items are set in, all worked out once for the list as a list's marker column is.
  private struct HangingTerms {
    let gutter: CGFloat
    let fits: [Bool]
    let termAttributes: [NSAttributedString.Key: Any]
    let attributes: [NSAttributedString.Key: Any]
  }

  /// Each term is measured as it is drawn, as a table cell is, chips and code included.
  private func hangingTerms(
    _ list: DefinitionList, indent: CGFloat, spacing: CGFloat,
    base termAttributes: [NSAttributedString.Key: Any]
  ) -> HangingTerms {
    let gap = style.bodySize * Self.markerGapShare
    let termWidths = list.items.map { cellWidth($0.term, base: termAttributes) }
    let gutterWidth = Self.termGutterWidth(
      termWidths: termWidths, gap: gap, step: style.indentStep,
      limit: (style.measure - indent) * Self.termGutterShare)
    let gutter = indent + gutterWidth
    let paragraph = paragraphStyle(
      indent: gutter, firstLineIndent: indent, spacingAfter: spacing,
      tabStops: [NSTextTab(textAlignment: .left, location: gutter)])
    var hangingTermAttributes = termAttributes
    hangingTermAttributes[.paragraphStyle] = paragraph
    return HangingTerms(
      gutter: gutter, fits: termWidths.map { $0 + gap <= gutterWidth },
      termAttributes: hangingTermAttributes, attributes: bodyAttributes(paragraph))
  }

  /// How wide a hanging definition list's term gutter is: the widest term that fits
  /// within `limit` and `gap`, never less than `step`. A term wider than that is set on
  /// a line of its own, so it is left out of the measure rather than widening the
  /// gutter for every other term; with none that fits, the gutter is one step and no
  /// term hangs.
  static func termGutterWidth(
    termWidths: [CGFloat], gap: CGFloat, step: CGFloat, limit: CGFloat
  ) -> CGFloat {
    let fitting = termWidths.map { $0 + gap }.filter { $0 <= max(step, limit) }
    return max(step, fitting.max() ?? 0)
  }

  /// The most of the width left after a definition list's indent that its terms may
  /// take; see `termGutterWidth`. A third of an iPhone's column is about 110 pt.
  static let termGutterShare: CGFloat = 1.0 / 3.0

  /// How wide a list's marker column is: its widest marker and `gap`, never less than
  /// `step` and never more than `limit`. One step was the column for every list, and
  /// a wider marker ran past its tab stop (#359): "(iii)" at 17 pt, and since the step
  /// is capped by the column (#331), even "1." at the accessibility sizes on an
  /// iPhone. The limit keeps what #331 capped the step for: a nested list's indent
  /// is its parent's column, and a column without one gave a sliver of text to a list
  /// of `Requirement 1:` markers three levels down at those sizes. The limit is a share
  /// of the width left after the list's indent, not of the whole column, so each level
  /// takes less than the one outside it and no depth of nesting takes all of it (#153).
  /// A marker wider than the limit runs past its stop, as every wide marker did before.
  static func markerColumnWidth(
    markerWidths: [CGFloat], gap: CGFloat, step: CGFloat, limit: CGFloat
  ) -> CGFloat {
    min(max(step, (markerWidths.max() ?? 0) + gap), max(step, limit))
  }

  /// The space after a list's widest marker, in ems: the gap a tab leaves before the
  /// item's text. It grows with the text, unlike a table's fixed `columnGutter`.
  static let markerGapShare: CGFloat = 0.5

  /// The most of the width left after a list's indent that its markers may take;
  /// see `markerColumnWidth`.
  static let markerColumnShare: CGFloat = 0.2

  /// The marker the item at `index` is drawn with. A numbered list's is its
  /// `ListNumbering`'s, which the parsers read once from either source.
  static func marker(for style: ListBlock.Style, at index: Int) -> String {
    switch style {
    case .bullet: "•"
    case .bare: ""
    case .numbered(let numbering): numbering.marker(at: index)
    }
  }
}
