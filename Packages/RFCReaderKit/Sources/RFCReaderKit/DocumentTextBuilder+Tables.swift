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
        // the regular weight. Bold glyphs are wider, and the header is frequently
        // the widest content in its column, so measuring both in the regular font
        // under-measures and lets a tab stop fall through to defaultTabInterval.
        let rows: [(cells: [[Inline]], font: PlatformFont)] =
            table.header.map { ($0, style.boldBodyFont) } + table.rows.map { ($0, style.bodyFont) }
        let columns = rows.map { $0.cells.count }.max() ?? 0
        guard columns > 0 else { return [] }
        return (0..<columns).map { column in
            rows.compactMap { row -> CGFloat? in
                guard row.cells.count > column else { return nil }
                return lineWidth(row.cells[column].plainText, font: row.font)
            }.max() ?? 0
        }
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
        let dataAttributes: [NSAttributedString.Key: Any] =
            [.font: style.bodyFont, .foregroundColor: bodyColour, .paragraphStyle: rowStyle]
        var headerAttributes = dataAttributes
        headerAttributes[.font] = style.boldBodyFont

        for (index, row) in (table.header + table.rows).enumerated() {
            let attributes = index < table.header.count ? headerAttributes : dataAttributes
            for (column, cell) in row.enumerated() {
                if column > 0 { append("\t", attributes) }
                output.append(inlineRuns(cell, base: attributes))
            }
            append("\n", attributes)
        }
    }

    private func appendStackedTable(_ table: RFCKit.Table, indent: CGFloat) {
        let headers = table.header.first ?? []
        // Nothing here varies by row or cell, so the three dictionaries are built
        // once for the whole table rather than once per cell.
        let cellIndent = indent + style.indentStep
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.bodyFont,
            .foregroundColor: bodyColour,
            .paragraphStyle: paragraphStyle(indent: cellIndent, spacingAfter: style.paragraphSpacing * 0.25),
        ]
        var labelAttributes = attributes
        labelAttributes[.font] = style.boldBodyFont
        labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
        let separatorAttributes = bodyAttributes(indent: indent)

        for row in table.rows {
            for (column, cell) in row.enumerated() {
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

    /// `Figure 3: Packet layout`, or just the title when the block is unnumbered.
    static func caption(_ kind: String, number: Int?, title: String?) -> String? {
        guard let title else { return nil }
        return number.map { "\(kind) \($0): \(title)" } ?? title
    }

    func appendCaption(_ caption: String?, indent: CGFloat) {
        guard let caption, !caption.isEmpty else { return }
        append(caption + "\n", [
            .font: style.captionFont,
            .foregroundColor: RFCColors.secondaryLabel,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing, alignment: .center),
        ])
    }
}
