import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

enum TableShape {
  /// Columns fit the measure: tab stops, one paragraph per row.
  case grid
  /// They do not: one paragraph per cell, each led by its column header.
  case stacked
}

extension DocumentTextBuilder {
  static let columnGutter: CGFloat = 16

  /// RFC tables routinely carry one prose column of 87 to 92 characters beside two
  /// or three short ones, and tab stops do not wrap. So measure first: grid when
  /// the natural widths fit, stacked when they do not. The stacked shape is also
  /// what a phone measure needs for tables that fit comfortably on a Mac.
  func tableShape(widths: [CGFloat]) -> TableShape {
    guard !widths.isEmpty else { return .grid }
    let total = widths.reduce(0, +) + Self.columnGutter * CGFloat(widths.count - 1)
    return total <= style.measure ? .grid : .stacked
  }

  func naturalColumnWidths(_ table: RFCKit.Table) -> [CGFloat] {
    // Measure what appendGridTable renders: header rows in bold, data rows in
    // the regular weight, and each cell through the runs it is set in, so strong
    // text is measured bold in a data cell and heavy in a header (#360). Bold
    // glyphs are wider, and the header is frequently the widest content in its
    // column, so measuring less than is drawn lets a tab stop fall through to
    // defaultTabInterval.
    let (header, data) = gridRowAttributes(.default)
    let rows: [(cells: [[Inline]], base: [NSAttributedString.Key: Any])] =
      table.header.map { ($0.cells, header) } + table.rows.map { ($0.cells, data) }
    let columns = rows.map { $0.cells.count }.max() ?? 0
    guard columns > 0 else { return [] }
    return (0..<columns).map { column in
      rows.compactMap { row -> CGFloat? in
        guard row.cells.count > column else { return nil }
        return cellWidth(row.cells[column], base: row.base)
      }.max() ?? 0
    }
  }

  /// A cell's width as it is set. Plain text is measured as a string in the row's
  /// attributes, which is what nearly every cell is; only a cell with formatting has
  /// its runs built to be measured, so a registry of hundreds of rows is not built
  /// twice. Building runs numbers a chip, so measuring advances `nextChipID`; the
  /// numbers only have to differ between neighbors, so the gap is harmless.
  private func cellWidth(_ cell: [Inline], base: [NSAttributedString.Key: Any]) -> CGFloat {
    let isPlainText = cell.allSatisfy { inline in
      if case .text = inline { true } else { false }
    }
    if isPlainText {
      return lineWidth(NSAttributedString(string: cell.plainText, attributes: base))
    }
    return lineWidth(inlineRuns(cell, base: base))
  }

  /// A grid's header row and data row attributes in `paragraphStyle`: only the font
  /// differs, and the measuring and the setting share this so the two cannot drift.
  private func gridRowAttributes(_ paragraphStyle: NSParagraphStyle) -> (
    header: [NSAttributedString.Key: Any], data: [NSAttributedString.Key: Any]
  ) {
    let data = bodyAttributes(paragraphStyle)
    var header = data
    header[.font] = style.boldBodyFont
    return (header, data)
  }

  func appendTable(_ table: RFCKit.Table, indent: CGFloat) {
    mark(table.anchor)
    // Measured once: the shape decision and the grid's tab stops want the same
    // numbers, and every cell costs a `CTLine` to measure.
    let widths = naturalColumnWidths(table)
    let start = output.length
    switch tableShape(widths: widths) {
    case .grid: appendGridTable(table, widths: widths, indent: indent)
    case .stacked: appendStackedTable(table, indent: indent)
    }
    decorate(from: start, with: .table)
    appendCaption(Self.caption("Table", number: table.number, title: table.title), indent: indent)
  }

  private func appendGridTable(_ table: RFCKit.Table, widths: [CGFloat], indent: CGFloat) {
    var location = indent
    var stops: [NSTextTab] = []
    for width in widths.dropLast() {
      location += width + Self.columnGutter
      stops.append(NSTextTab(textAlignment: .left, location: location))
    }
    let rowStyle = paragraphStyle(indent: indent, spacingAfter: 0, tabStops: stops, wraps: false)
    // Only the font differs between a header row and a data row, and nothing in
    // either varies down the table, so both are built once here rather than per
    // row.
    let (headerAttributes, dataAttributes) = gridRowAttributes(rowStyle)

    for (index, row) in (table.header + table.rows).enumerated() {
      let attributes = index < table.header.count ? headerAttributes : dataAttributes
      mark(row.anchor)
      for (column, cell) in row.cells.enumerated() {
        if column > 0 { append("\t", attributes) }
        output.append(inlineRuns(cell, base: attributes))
      }
      append("\n", attributes)
    }
  }

  private func appendStackedTable(_ table: RFCKit.Table, indent: CGFloat) {
    let headers = table.header.first?.cells ?? []
    // Nothing here varies by row or cell, so the three dictionaries are built
    // once for the whole table rather than once per cell.
    let cellIndent = indent + style.indentStep
    let attributes = bodyAttributes(
      paragraphStyle(indent: cellIndent, spacingAfter: style.paragraphSpacing * 0.25))
    var labelAttributes = attributes
    labelAttributes[.font] = style.boldBodyFont
    labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
    let separatorAttributes = bodyAttributes(indent: indent)

    // The header has no row of its own here: it labels every cell instead. A link
    // to a header row lands at the top of the table, where the first label is.
    for row in table.header { mark(row.anchor) }
    for row in table.rows {
      mark(row.anchor)
      for (column, cell) in row.cells.enumerated() {
        if column < headers.count {
          output.append(inlineRuns(headers[column], base: labelAttributes))
          append("  ", attributes)
        }
        output.append(inlineRuns(cell, base: attributes))
        append("\n", attributes)
      }
      // A blank line separates one row's cells from the next row's. It needs no
      // decoration of its own: `appendTable` decorates the whole emitted range.
      append("\n", separatorAttributes)
    }
  }

  /// `Figure 3: Packet layout`; `Figure 3` when the block has no title, as xml2rfc's
  /// text and HTML writers caption every numbered figure and table, so the prose's
  /// "see Figure 3" has something to find; just the title when it is unnumbered.
  static func caption(_ kind: String, number: Int?, title: String?) -> String? {
    guard let number else { return title }
    return title.map { "\(kind) \(number): \($0)" } ?? "\(kind) \(number)"
  }

  func appendCaption(_ caption: String?, indent: CGFloat) {
    guard let caption, !caption.isEmpty else { return }
    append(
      caption + "\n",
      captionAttributes(
        paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing, alignment: .center)))
  }
}
