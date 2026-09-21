import RFCKit
import SwiftUI

/// Renders one block of the document model. Recursive for lists, figures and quotes.
struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .paragraph(let paragraph):
            InlineText(paragraph.inlines)
        case .list(let list):
            ListBlockView(list: list)
        case .definitionList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        InlineText(item.term).fontWeight(.semibold)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(item.definition.enumerated()), id: \.offset) { _, block in
                                BlockView(block: block)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        case .preformatted(let preformatted):
            PreformattedView(content: preformatted)
        case .figure(let figure):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(figure.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
                if let title = figure.title {
                    Text(figure.number.map { "Figure \($0): \(title)" } ?? title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .id(figure.anchor ?? "")
        case .table(let table):
            TableBlockView(table: table)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        BlockView(block: block)
                    }
                }
            }
        case .aside(let blocks):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        case .references(let list):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(list.entries) { reference in
                    ReferenceRow(reference: reference)
                }
            }
        }
    }
}

struct ListBlockView: View {
    let list: ListBlock

    var body: some View {
        VStack(alignment: .leading, spacing: list.isCompact ? 4 : 10) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(at: index))
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                            BlockView(block: block)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    private func marker(at index: Int) -> String {
        switch list.style {
        case .bullet: return "•"
        case .bare: return ""
        case .numbered(let format, let start):
            let value = start + index
            let letters = "abcdefghijklmnopqrstuvwxyz"
            func letter(_ n: Int, upper: Bool) -> String {
                let character = String(letters[letters.index(letters.startIndex, offsetBy: (n - 1) % 26)])
                return upper ? character.uppercased() : character
            }
            func roman(_ n: Int) -> String {
                let table: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
                var remaining = n
                var result = ""
                for (arabic, symbol) in table {
                    while remaining >= arabic { result += symbol; remaining -= arabic }
                }
                return result
            }
            // RFCXML formats: "1", "a", "A", "i", "I", or a template such as "(%c)" / "%d.".
            switch format {
            case nil, "1": return "\(value)."
            case "a": return "\(letter(value, upper: false))."
            case "A": return "\(letter(value, upper: true))."
            case "i": return "\(roman(value))."
            case "I": return "\(roman(value).uppercased())."
            case let template?:
                return template
                    .replacingOccurrences(of: "%d", with: String(value))
                    .replacingOccurrences(of: "%c", with: letter(value, upper: false))
                    .replacingOccurrences(of: "%C", with: letter(value, upper: true))
                    .replacingOccurrences(of: "%i", with: roman(value))
                    .replacingOccurrences(of: "%I", with: roman(value).uppercased())
            }
        }
    }
}

struct TableBlockView: View {
    let table: RFCKit.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                InlineText(cell).fontWeight(.semibold)
                            }
                        }
                        Divider()
                    }
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                InlineText(cell)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            if let title = table.title {
                Text(table.number.map { "Table \($0): \(title)" } ?? title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .id(table.anchor ?? "")
    }
}

struct ReferenceRow: View {
    @Environment(LibraryModel.self) private var library
    let reference: Reference

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("[\(reference.anchor)]")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let raw = reference.rawText, reference.title.isEmpty {
                    Text(raw)
                } else {
                    if !reference.authors.isEmpty {
                        Text(reference.authors.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                    Text("“\(reference.title)”")
                    let series = reference.seriesInfo.filter { $0.name != "DOI" }.map { "\($0.name) \($0.value)" }
                    if !series.isEmpty || reference.date != nil {
                        Text((series + [reference.date?.formatted].compactMap { $0 }).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    if let id = reference.documentID {
                        Button("Open \(id.displayName)") { library.open(id) }
                    }
                    if let url = reference.url {
                        Link(url.host() ?? "Link", destination: url)
                    }
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .id("ref-\(reference.anchor)")
        .font(.callout)
    }
}
