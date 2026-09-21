import Foundation
import RFCKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Turns an `RFCDocument` into one attributed string plus an anchor index.
///
/// Pure: no view, no state that outlives a build, no I/O. `@MainActor` because
/// `NSAttributedString` is not `Sendable` and the result goes straight into a text
/// view; nothing here needs to run anywhere else.
@MainActor
public final class DocumentTextBuilder {
    /// The private URL scheme an in-document anchor link uses. Moved here from
    /// `InlineText`, which this replaces.
    public static let anchorScheme = "rfc-anchor"

    let style: ReadingStyle
    let output = NSMutableAttributedString()
    var entries: [AnchorIndex.Entry] = []

    init(style: ReadingStyle) {
        self.style = style
    }

    public static func build(_ document: RFCDocument, style: ReadingStyle) -> BuiltDocument {
        let builder = DocumentTextBuilder(style: style)
        builder.appendDocument(document)
        return BuiltDocument(text: builder.output, anchors: AnchorIndex(builder.entries))
    }

    /// Records where an anchor lands. Called immediately before the run it names.
    func mark(_ anchor: String?) {
        guard let anchor, !anchor.isEmpty else { return }
        entries.append(AnchorIndex.Entry(anchor: anchor, offset: output.length))
    }

    func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
        output.append(NSAttributedString(string: string, attributes: attributes))
    }
}

extension DocumentTextBuilder {
    func appendDocument(_ document: RFCDocument) {
        appendBlocks(document.header.abstract, indent: 0)
        for section in document.sections {
            appendSection(section, depth: 1)
        }
    }

    private func appendSection(_ section: Section, depth: Int) {
        mark(section.anchor)
        append(section.displayTitle + "\n", [
            .font: style.headingFont(depth: depth),
            .foregroundColor: RFCColors.label,
            .rfcAnchor: section.anchor,
            .paragraphStyle: paragraphStyle(spacingBefore: style.paragraphSpacing * 1.6, spacingAfter: style.paragraphSpacing * 0.6),
        ])
        appendBlocks(section.blocks, indent: 0)
        for subsection in section.subsections {
            appendSection(subsection, depth: depth + 1)
        }
    }

    func appendBlocks(_ blocks: [Block], indent: CGFloat) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                appendParagraph(paragraph, indent: indent)
            case .list(let list):
                appendList(list, indent: indent)
            case .definitionList(let items):
                appendDefinitionList(items, indent: indent)
            case .preformatted(let content):
                appendVerbatim(content, indent: indent)
            default:
                // Lists, verbatim, tables, figures, quotes and references arrive in
                // Tasks 5 to 8; until then they emit nothing.
                break
            }
        }
    }

    func appendParagraph(_ paragraph: Paragraph, indent: CGFloat) {
        mark(paragraph.anchor)
        let runs = Self.inlineRuns(paragraph.inlines, style: style, base: bodyAttributes(indent: indent))
        output.append(runs)
        append("\n", bodyAttributes(indent: indent))
    }

    func bodyAttributes(indent: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: RFCColors.label,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing),
        ]
    }

    func paragraphStyle(
        indent: CGFloat = 0,
        firstLineIndent: CGFloat? = nil,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat,
        tabStops: [NSTextTab]? = nil,
        wraps: Bool = true
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = firstLineIndent ?? indent
        paragraph.headIndent = indent
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        if let tabStops {
            paragraph.tabStops = tabStops
            paragraph.defaultTabInterval = style.indentStep
        }
        return paragraph
    }
}
