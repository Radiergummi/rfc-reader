import Foundation
import RFCKit

extension DocumentTextBuilder {
    func appendFigure(_ figure: Figure, indent: CGFloat) {
        mark(figure.anchor)
        appendBlocks(figure.blocks, indent: indent)
        let caption = figure.title.map { title in figure.number.map { number in "Figure \(number): \(title)" } ?? title }
        appendCaption(caption, indent: indent)
    }

    /// The rule and the background are drawn by `RFCTextLayoutFragment`; the builder
    /// only says which decoration applies and how far the text is indented.
    func appendDecorated(_ blocks: [Block], decoration: RFCDecoration, indent: CGFloat) {
        let start = output.length
        appendBlocks(blocks, indent: indent + style.indentStep)
        guard output.length > start else { return }
        output.addAttribute(.rfcDecoration, value: decoration, range: NSRange(location: start, length: output.length - start))
    }

    func appendReferences(_ list: ReferenceList, indent: CGFloat) {
        for entry in list.entries {
            mark("ref-\(entry.anchor)")
            var labelAttributes = bodyAttributes(indent: indent)
            labelAttributes[.font] = style.codeFont
            labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
            labelAttributes[.paragraphStyle] = paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing * 0.2)
            if let id = entry.documentID {
                labelAttributes[.link] = RFCLink(id: id, section: nil).appURL
                labelAttributes[.rfcReference] = ReferenceBox(CrossReference(target: .document(id, section: nil), text: "[\(entry.anchor)]"))
            }
            append("[\(entry.anchor)]\n", labelAttributes)

            let bodyIndent = indent + style.indentStep * 1.5
            var attributes = bodyAttributes(indent: bodyIndent)
            attributes[.paragraphStyle] = paragraphStyle(indent: bodyIndent, spacingAfter: style.paragraphSpacing)

            if let raw = entry.rawText, entry.title.isEmpty {
                append(raw + "\n", attributes)
                continue
            }

            var lines: [String] = []
            if !entry.authors.isEmpty { lines.append(entry.authors.joined(separator: ", ")) }
            lines.append("\u{201C}\(entry.title)\u{201D}")
            let series = entry.seriesInfo.filter { $0.name != "DOI" }.map { "\($0.name) \($0.value)" }
            let trailer = (series + [entry.date?.formatted].compactMap { $0 }).joined(separator: ", ")
            if !trailer.isEmpty { lines.append(trailer) }
            append(lines.joined(separator: "\n") + "\n", attributes)

            if let url = entry.url {
                var linkAttributes = attributes
                linkAttributes[.link] = url
                append((url.host() ?? url.absoluteString) + "\n", linkAttributes)
            }
        }
    }
}
