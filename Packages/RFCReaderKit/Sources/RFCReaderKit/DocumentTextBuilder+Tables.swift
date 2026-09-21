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
    func tableShape(_ table: RFCKit.Table) -> TableShape {
        let widths = naturalColumnWidths(table)
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
                return NSAttributedString(string: row.cells[column].plainText, attributes: [.font: row.font]).size().width
            }.max() ?? 0
        }
    }

    func appendTable(_ table: RFCKit.Table, indent: CGFloat) {
        mark(table.anchor)
        switch tableShape(table) {
        case .grid: appendGridTable(table, indent: indent)
        case .stacked: appendStackedTable(table, indent: indent)
        }
        appendCaption(table.title.map { title in table.number.map { n in "Table \(n): \(title)" } ?? title }, indent: indent)
    }

    private func appendGridTable(_ table: RFCKit.Table, indent: CGFloat) {
        let widths = naturalColumnWidths(table)
        var location = indent
        var stops: [NSTextTab] = []
        for width in widths.dropLast() {
            location += width + Self.columnGutter
            stops.append(NSTextTab(textAlignment: .left, location: location))
        }
        let rowStyle = paragraphStyle(indent: indent, spacingAfter: 0, tabStops: stops, wraps: false)

        for (index, row) in (table.header + table.rows).enumerated() {
            let isHeader = index < table.header.count
            var attributes = bodyAttributes(indent: indent)
            attributes[.font] = isHeader ? style.boldBodyFont : style.bodyFont
            attributes[.paragraphStyle] = rowStyle
            attributes[.rfcDecoration] = RFCDecoration.table
            for (column, cell) in row.enumerated() {
                if column > 0 { append("\t", attributes) }
                output.append(Self.inlineRuns(cell, style: style, base: attributes))
            }
            append("\n", attributes)
        }
    }

    private func appendStackedTable(_ table: RFCKit.Table, indent: CGFloat) {
        let headers = table.header.first ?? []
        for row in table.rows {
            for (column, cell) in row.enumerated() {
                var attributes = bodyAttributes(indent: indent + style.indentStep)
                attributes[.paragraphStyle] = paragraphStyle(
                    indent: indent + style.indentStep,
                    spacingAfter: style.paragraphSpacing * 0.25
                )
                attributes[.rfcDecoration] = RFCDecoration.table
                if column < headers.count {
                    var labelAttributes = attributes
                    labelAttributes[.font] = style.boldBodyFont
                    labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
                    output.append(Self.inlineRuns(headers[column], style: style, base: labelAttributes))
                    append("  ", attributes)
                }
                output.append(Self.inlineRuns(cell, style: style, base: attributes))
                append("\n", attributes)
            }
            // A blank line separates one row's cells from the next row's.
            append("\n", bodyAttributes(indent: indent))
        }
    }

    func appendCaption(_ caption: String?, indent: CGFloat) {
        guard let caption, !caption.isEmpty else { return }
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.paragraphSpacing = style.paragraphSpacing
        centred.lineHeightMultiple = style.lineHeightMultiple
        append(caption + "\n", [
            .font: style.captionFont,
            .foregroundColor: RFCColors.secondaryLabel,
            .paragraphStyle: centred,
        ])
    }
}
