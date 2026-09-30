import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  func appendList(_ list: ListBlock, indent: CGFloat) {
    // Measured once for the list, as a grid table's columns are: every item then
    // hangs its marker in the same column, however wide the widest one is.
    let markerFont: [NSAttributedString.Key: Any] = [.font: style.bodyFont]
    let markerWidths = list.items.indices.map { index in
      NSAttributedString(string: Self.marker(for: list.style, at: index), attributes: markerFont)
        .size().width
    }
    let markerColumn =
      indent
      + Self.markerColumnWidth(
        markerWidths: markerWidths, gap: style.bodySize * 0.5, step: style.indentStep)
    // Every item of one list shares its indents and spacing, so both dictionaries
    // and the tab stop are built once for the list rather than once per item.
    let spacing = list.isCompact ? style.paragraphSpacing * 0.35 : style.paragraphSpacing
    let attributes: [NSAttributedString.Key: Any] = [
      .font: style.bodyFont,
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
      let marker = Self.marker(for: list.style, at: index)
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

  func appendDefinitionList(_ items: [DefinitionItem], indent: CGFloat) {
    let termAttributes: [NSAttributedString.Key: Any] = [
      .font: style.boldBodyFont,
      .foregroundColor: bodyColor,
      .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing * 0.3),
    ]
    for item in items {
      mark(item.anchor)
      output.append(inlineRuns(item.term, base: termAttributes))
      // A definition's own anchor goes where its text starts. An empty `<dd>`
      // has no text, and marking it after the term's newline would put it at the
      // next item's term, so a link to it would land one item late; the end of
      // its own term keeps it on the item it belongs to.
      if item.definition.isEmpty { mark(item.definitionAnchor) }
      append("\n", termAttributes)
      if !item.definition.isEmpty { mark(item.definitionAnchor) }
      appendBlocks(item.definition, indent: indent + style.indentStep)
    }
  }

  /// How wide a list's marker column is: its widest marker and `gap`, never less than
  /// `step`. One step was the column for every list, and a wider marker ran past its
  /// tab stop (#359): "(iii)" at 17 pt, and since the step is capped by the column
  /// (#331), even "1." at the accessibility sizes on an iPhone.
  static func markerColumnWidth(markerWidths: [CGFloat], gap: CGFloat, step: CGFloat) -> CGFloat {
    max(step, (markerWidths.max() ?? 0) + gap)
  }

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
