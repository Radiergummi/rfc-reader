import CoreText
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

    /// The width of `string` set as one line in `font`, via CoreText rather than
    /// `NSAttributedString.size()`. NSStringDrawing applies line-breaking and
    /// drawing-context layout semantics that are the wrong tool for measuring a
    /// single line, and under CPU load it has been observed to raise an uncaught
    /// `NSException`; a `CTLine`'s typographic bounds answer the same question
    /// directly, without going through a drawing context at all.
    func lineWidth(_ string: String, font: PlatformFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

extension DocumentTextBuilder {
    func appendDocument(_ document: RFCDocument) {
        appendAbstract(document.header.abstract)
        for section in document.sections {
            appendSection(section, depth: 1)
        }
    }

    /// The abstract is the first prose in the storage, and its heading belongs here
    /// with it: neither parser keeps "Abstract" as a block — both consume it into
    /// `DocumentHeader.abstract` — and the reader's header view stops above the
    /// status banner, so a label placed there would sit on the wrong side of it.
    /// No anchor: nothing links to the abstract, and it is not in the contents.
    private func appendAbstract(_ blocks: [Block]) {
        guard !blocks.isEmpty else { return }
        append("Abstract\n", [
            .font: style.headingFont(depth: 1),
            .foregroundColor: RFCColors.label,
            .paragraphStyle: paragraphStyle(spacingAfter: style.paragraphSpacing * 0.6),
        ])
        appendBlocks(blocks, indent: 0)
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
            case .table(let table):
                appendTable(table, indent: indent)
            case .figure(let figure):
                appendFigure(figure, indent: indent)
            case .blockQuote(let inner):
                appendDecorated(inner, decoration: .blockQuote, indent: indent)
            case .aside(let inner):
                appendDecorated(inner, decoration: .aside, indent: indent)
            case .references(let list):
                appendReferences(list, indent: indent)
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
