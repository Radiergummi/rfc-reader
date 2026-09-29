import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  func appendList(_ list: ListBlock, indent: CGFloat) {
    let markerColumn = indent + style.indentStep
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
        // Set on the marker's line rather than through `appendParagraph`, so its
        // anchor is marked here, where its text starts.
        mark(paragraph.anchor)
        output.append(inlineRuns(paragraph.inlines, base: attributes))
        append("\n", attributes)
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
