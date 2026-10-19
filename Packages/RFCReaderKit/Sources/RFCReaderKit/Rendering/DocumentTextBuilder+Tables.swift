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
  ///
  /// Against the measure less `indent`: a grid starts at its indent and does not
  /// wrap, so one inside a list, a quotation or an aside that fit the column but not
  /// what its indent leaves of it lost the end of its last column (#765).
  func tableShape(widths: [CGFloat], indent: CGFloat) -> TableShape {
    guard !widths.isEmpty else { return .grid }
    let total = widths.reduce(0, +) + Self.columnGutter * CGFloat(widths.count - 1)
    return total <= style.measure - indent ? .grid : .stacked
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
  /// its runs built to be measured, so a registry's plain columns are not built
  /// twice. A reference column is: each of its chips is built to be measured and
  /// again to be set. Building runs numbers a chip, so measuring advances
  /// `nextChipID`; the numbers only have to differ between neighbors, so the gap is
  /// harmless. A hanging definition list measures its terms with it too.
  func cellWidth(_ cell: [Inline], base: [NSAttributedString.Key: Any]) -> CGFloat {
    let isPlainText = cell.allSatisfy { inline in
      if case .text = inline { true } else { false }
    }
    if isPlainText {
      return lineWidth(NSAttributedString(string: cell.plainText, attributes: base))
    }
    // Kerned as `build` kerns the whole text, so the cell is measured with its
    // chips' padding. A cell's own runs are the context that needs: the character
    // before a chip that opens a cell is the row's newline or its tab, which the
    // pass skips.
    let runs = NSMutableAttributedString(attributedString: inlineRuns(cell, base: base))
    Self.reserveChipPadding(in: runs)
    // As wide as its widest line: a line break sets the rest of the cell under it.
    return Self.lines(of: runs).map { lineWidth($0) + chipSymbolWidth(in: $0) }.max() ?? 0
  }

  /// What a cell's line break (RFCXML's `<br/>`) is set as in a table: a line
  /// separator, which breaks the line without ending the paragraph, so a grid's row
  /// and a stacked cell each stay one (#506).
  static let cellLineSeparator = "\u{2028}"

  /// `runs` split where a line break made a newline of it, the newlines dropped.
  static func lines(of runs: NSAttributedString) -> [NSAttributedString] {
    let string = runs.string as NSString
    var lines: [NSAttributedString] = []
    var start = 0
    while true {
      let rest = NSRange(location: start, length: string.length - start)
      let newline = string.range(of: "\n", range: rest)
      guard newline.location != NSNotFound else {
        lines.append(runs.attributedSubstring(from: rest))
        return lines
      }
      lines.append(
        runs.attributedSubstring(from: NSRange(location: start, length: newline.location - start)))
      start = NSMaxRange(newline)
    }
  }

  /// The width of the chips' symbols in `runs`: an attachment, which `lineWidth(_:)`
  /// measures as nothing, drawn as wide as the bounds `chipSymbolRun` gives it. A
  /// chip's symbol is the only attachment inline runs make.
  private func chipSymbolWidth(in runs: NSAttributedString) -> CGFloat {
    var width: CGFloat = 0
    runs.enumerateAttribute(.attachment, in: NSRange(location: 0, length: runs.length)) {
      value, _, _ in
      if let attachment = value as? NSTextAttachment { width += attachment.bounds.width }
    }
    return width
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
    let layout = TableModelLayout(table, from: positions?.cursor ?? 0)
    let firstRun = positions?.runCount ?? 0
    switch tableShape(widths: widths, indent: indent) {
    case .grid: appendGridTable(table, widths: widths, indent: indent, layout: layout)
    case .stacked: appendStackedTable(table, indent: indent, layout: layout)
    }
    // A cell's lines and the joins between cells fall where the shape sets them, so
    // they were mapped where they fell; whatever the shape left out is hidden here.
    positions?.hideUnmapped(in: layout.start..<layout.end, since: firstRun)
    positions?.cursor = layout.end
    decorate(from: start, with: .table)
    appendCaption(
      Self.caption(labels.table, number: table.number, title: table.title), indent: indent,
      blockStart: start)
  }

  private func appendGridTable(
    _ table: RFCKit.Table, widths: [CGFloat], indent: CGFloat, layout: TableModelLayout
  ) {
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

    let rows = table.header + table.rows
    for (index, row) in rows.enumerated() {
      let attributes = index < table.header.count ? headerAttributes : dataAttributes
      mark(row.anchor)
      // A row is as many lines as its tallest cell has, each holding every cell's
      // line of that number at its stop, and set apart by line separators, so the
      // row is still one paragraph and keeps its tab stops (#506).
      let cells = row.cells.map { Self.lines(of: inlineRuns($0, base: attributes)) }
      let height = cells.map(\.count).max() ?? 1
      for line in 0..<height {
        if line > 0 { append(Self.cellLineSeparator, attributes) }
        // A line ends at its last cell with something on it, not in trailing tabs.
        let last = cells.lastIndex { $0.count > line } ?? 0
        for (column, cell) in cells.enumerated().prefix(last + 1) {
          if column > 0 {
            append("\t", attributes)
            // The first line's tab is the join between the two cells.
            if line == 0 { mapTableJoin(at: layout.cells[index][column] - 1) }
          }
          if line < cell.count {
            appendCellLine(cell[line], model: layout.line(line, ofCell: column, inRow: index))
          }
        }
      }
      append("\n", attributes)
      if index < rows.count - 1 { mapTableJoin(at: layout.rows[index + 1] - 1) }
    }
  }

  /// Maps the storage's last character, a tab or a newline just appended, to the
  /// model text's join at `model`.
  private func mapTableJoin(at model: Int) {
    positions?.map(storage: output.length - 1, model: model, length: 1)
  }

  /// Appends one line of a cell, whose model text starts at `model`.
  private func appendCellLine(_ line: NSAttributedString, model: Int?) {
    let start = output.length
    output.append(line)
    if let model {
      positions?.align(
        output.mutableString, range: NSRange(location: start, length: line.length), model: model)
    }
  }

  private func appendStackedTable(
    _ table: RFCKit.Table, indent: CGFloat, layout: TableModelLayout
  ) {
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
    for (rowIndex, row) in table.rows.enumerated() {
      mark(row.anchor)
      let index = table.header.count + rowIndex
      for (column, cell) in row.cells.enumerated() {
        if column < headers.count {
          appendCell(headers[column], attributes: labelAttributes)
          append("  ", attributes)
        }
        appendCell(cell, attributes: attributes) { line in
          layout.line(line, ofCell: column, inRow: index)
        }
        append("\n", attributes)
      }
      // A blank line separates one row's cells from the next row's. It needs no
      // decoration of its own: `appendTable` decorates the whole emitted range.
      append("\n", separatorAttributes)
    }
  }

  /// A stacked cell, or its label, with its lines set apart by line separators, so
  /// the cell is one paragraph however many lines it has (#506).
  /// Each line's model text starts where `model` says, or it is a label, which the
  /// model has not.
  private func appendCell(
    _ cell: [Inline], attributes: [NSAttributedString.Key: Any],
    model: (Int) -> Int? = { _ in nil }
  ) {
    for (line, text) in Self.lines(of: inlineRuns(cell, base: attributes)).enumerated() {
      if line > 0 { append(Self.cellLineSeparator, attributes) }
      appendCellLine(text, model: model(line))
    }
  }

  /// `BlockCaption.text`, which the exports caption with too.
  static func caption(_ kind: String, number: Int?, title: String?) -> String? {
    BlockCaption.text(kind, number: number, title: title)
  }

  /// A figure's or a table's caption, under its block, which starts at `blockStart`.
  /// The block's last paragraph keeps with it (`BuiltDocument.keepsWithNext`), so a
  /// printed page never ends on the block and opens the next on its caption alone
  /// (#765). A stacked table ends on the blank line after its last row, which keeps
  /// too, back to the last paragraph with text. A block that emitted nothing has no
  /// paragraph to keep, and the one before it is not its.
  ///
  /// A figure's title is model text (`ModelText`), and `title` says where: the
  /// caption ends with it, and the newline after it is the join after it there.
  func appendCaption(
    _ caption: String?, indent: CGFloat, blockStart: Int, title: (model: Int, text: String)? = nil
  ) {
    if let title, caption?.isEmpty ?? true {
      // Nothing draws the title, nor the join after it.
      positions?.hide(title.model..<title.model + title.text.utf16.count + 1)
    }
    guard let caption, !caption.isEmpty else { return }
    var end = output.length
    while end > blockStart {
      let paragraph = output.mutableString.paragraphRange(
        for: NSRange(location: end - 1, length: 0))
      keepsWithNext.insert(paragraph.location)
      guard paragraph.length == 1 else { break }
      end = paragraph.location
    }
    append(
      caption + "\n",
      captionAttributes(
        paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing, alignment: .center)))
    if let title {
      let length = title.text.utf16.count + 1
      positions?.map(storage: output.length - length, model: title.model, length: length)
    }
  }
}

/// Where a table's rows, cells and cells' lines start in the model text (#522), which
/// sets the rows in order, the header's first, a row's cells joined by tabs and the
/// rows by newlines (`ModelText`), whatever shape the table is drawn in.
struct TableModelLayout {
  let start: Int
  let end: Int
  /// Where each row starts, the header's first.
  let rows: [Int]
  /// Where each cell of each row starts.
  let cells: [[Int]]
  /// Where each line of each cell starts, from the cell's start.
  private let lines: [[[Int]]]

  init(_ table: RFCKit.Table, from start: Int) {
    var offset = start
    var rows: [Int] = []
    var cells: [[Int]] = []
    var lines: [[[Int]]] = []
    for (index, row) in (table.header + table.rows).enumerated() {
      if index > 0 { offset += 1 }
      rows.append(offset)
      var rowCells: [Int] = []
      var rowLines: [[Int]] = []
      for (column, cell) in row.cells.enumerated() {
        if column > 0 { offset += 1 }
        rowCells.append(offset)
        var cellLines = [0]
        var length = 0
        for unit in cell.plainText.utf16 {
          length += 1
          if unit == 0x0A { cellLines.append(length) }
        }
        rowLines.append(cellLines)
        offset += length
      }
      cells.append(rowCells)
      lines.append(rowLines)
    }
    self.start = start
    end = offset
    self.rows = rows
    self.cells = cells
    self.lines = lines
  }

  /// Where line `line` of a cell starts in the model text.
  func line(_ line: Int, ofCell column: Int, inRow row: Int) -> Int? {
    guard row < lines.count, column < lines[row].count, line < lines[row][column].count else {
      return nil
    }
    return cells[row][column] + lines[row][column][line]
  }
}
