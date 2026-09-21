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
        for (index, item) in list.items.enumerated() {
            mark(item.anchor)
            let marker = Self.marker(for: list.style, at: index)
            let spacing = list.isCompact ? style.paragraphSpacing * 0.35 : style.paragraphSpacing
            var attributes: [NSAttributedString.Key: Any] = [.font: style.bodyFont, .foregroundColor: bodyColour]
            attributes[.paragraphStyle] = paragraphStyle(
                indent: markerColumn,
                firstLineIndent: indent,
                spacingAfter: spacing,
                tabStops: [NSTextTab(textAlignment: .left, location: markerColumn)]
            )
            // The marker is drawn at the outer indent, left of the tab stop at
            // markerColumn, so the tab advances to it and a wrapped item lines up
            // under its own text rather than under the bullet.
            var markerAttributes = attributes
            markerAttributes[.foregroundColor] = RFCColors.secondaryLabel
            let firstLine = NSMutableAttributedString(string: marker + "\t", attributes: markerAttributes)

            guard let first = item.blocks.first else {
                output.append(firstLine)
                append("\n", attributes)
                continue
            }
            output.append(firstLine)
            if case .paragraph(let paragraph) = first {
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
        for item in items {
            mark(item.anchor)
            var termAttributes = bodyAttributes(indent: indent)
            termAttributes[.font] = style.boldBodyFont
            termAttributes[.paragraphStyle] = paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing * 0.3)
            output.append(inlineRuns(item.term, base: termAttributes))
            append("\n", termAttributes)
            appendBlocks(item.definition, indent: indent + style.indentStep)
        }
    }

    /// The RFCXML list formats: "1", "a", "A", "i", "I", or a template such as
    /// "(%c)" or "%d.". Moved from `ListBlockView.marker(at:)` unchanged.
    static func marker(for style: ListBlock.Style, at index: Int) -> String {
        switch style {
        case .bullet:
            return "•"
        case .bare:
            return ""
        case .numbered(let format, let start):
            let value = start + index
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

    private static func letter(_ n: Int, upper: Bool) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let character = String(letters[letters.index(letters.startIndex, offsetBy: (n - 1) % 26)])
        return upper ? character.uppercased() : character
    }

    private static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var remaining = n
        var result = ""
        for (arabic, symbol) in table {
            while remaining >= arabic {
                result += symbol
                remaining -= arabic
            }
        }
        return result
    }
}
