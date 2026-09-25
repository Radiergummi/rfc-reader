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
/// Pure: no view, no state that outlives a build, no I/O — string assembly, `CTLine`
/// measurement and paragraph styles. Deliberately not main-actor bound: a build costs
/// hundreds of milliseconds on the largest RFCs, and blocking the main thread for it
/// is what made the font-size slider feel dead. Handing the finished document to a
/// text view is the only part that needs the main actor, and `BuiltDocument` carries
/// the result across.
public final class DocumentTextBuilder {
    /// The private URL scheme an in-document anchor link uses. Moved here from
    /// `InlineText`, which this replaces.
    public static let anchorScheme = "rfc-anchor"

    /// The style the *current* region is emitted in. A `var` because a region can be
    /// set quieter than the body around it — see `emitting(in:colour:)`.
    private(set) var style: ReadingStyle
    /// The colour ordinary prose is emitted in, for the same reason.
    private(set) var bodyColour: PlatformColor = RFCColors.label
    let output = NSMutableAttributedString()
    var entries: [AnchorIndex.Entry] = []

    /// The advance of one unscaled monospaced character, per body size. It depends
    /// only on the style, and a document can hold hundreds of artwork blocks, each of
    /// which would otherwise build a font and a `CTLine` to ask the same question
    /// again. Keyed rather than computed once, because a region emitted in a quieter
    /// style must be measured in that style too.
    private var monospaceAdvances: [CGFloat: CGFloat] = [:]

    var monospaceAdvance: CGFloat {
        if let cached = monospaceAdvances[style.bodySize] { return cached }
        let advance = lineWidth("0", font: style.monospacedFont(scale: 1))
        monospaceAdvances[style.bodySize] = advance
        return advance
    }

    /// Serial number for the next chip, so no two chip runs carry the same value.
    /// See the chip case in `run(_:base:)`.
    var nextChipID = 0

    /// Rendering an SF Symbol is the expensive part and depends only on the point
    /// size, of which a build sees one or two — but there is a chip per cross
    /// reference, and RFCs are full of them.
    var chipSymbols: [CGFloat: PlatformImage] = [:]

    init(style: ReadingStyle) {
        self.style = style
    }

    public static func build(_ document: RFCDocument, style: ReadingStyle) -> BuiltDocument {
        let builder = DocumentTextBuilder(style: style)
        builder.appendDocument(document)
        // Copied, not handed over: `output` is an `NSMutableAttributedString`, and
        // `BuiltDocument`'s `@unchecked Sendable` rests on its text being genuinely
        // immutable. Typing the same instance as `NSAttributedString` would only
        // hide the mutable object, not retire it.
        return BuiltDocument(
            text: NSAttributedString(attributedString: builder.output),
            anchors: AnchorIndex(builder.entries)
        )
    }

    /// Records where an anchor lands. Called immediately before the run it names.
    ///
    /// `isSection` marks the anchors section tracking may report. The index covers
    /// every anchor — paragraphs, figures, tables, reference rows — because
    /// `scroll(to:)` has to reach all of them, but every consumer of the reader's
    /// visible anchor resolves it with `RFCDocument.section(anchor:)`, so reporting a
    /// paragraph anchor would silently break all of them. Only `appendSection` passes
    /// true, which is the one place that knows, and the heading with it.
    func mark(_ anchor: String?, isSection: Bool = false, heading: String? = nil) {
        guard let anchor, !anchor.isEmpty else { return }
        entries.append(AnchorIndex.Entry(anchor: anchor, offset: output.length, isSection: isSection, heading: heading))
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
    ///
    /// It is anchored and marked like every other heading. It is not a `Section`, so
    /// it is not a section entry in the index and section tracking will not report
    /// it — but the VoiceOver headings rotor and `rfc-anchor:abstract` reach it by
    /// the ordinary rule rather than needing an exception each.
    static let abstractAnchor = "abstract"

    private func appendAbstract(_ blocks: [Block]) {
        guard !blocks.isEmpty else { return }
        mark(Self.abstractAnchor, isSection: false)
        append("Abstract\n", [
            .font: style.headingFont(depth: 1),
            .foregroundColor: RFCColors.label,
            .rfcAnchor: Self.abstractAnchor,
            .paragraphStyle: paragraphStyle(spacingAfter: style.paragraphSpacing * 0.6),
        ])
        // Emitted quiet, rather than emitted and then quietened. A post-pass has to
        // guess which runs "count" — matching against a dynamic colour to find the
        // ones to step back — and anything the builder *measures* against the style
        // (artwork's `monospaceScale`, a table's column widths) would be measured at
        // full size and shrunk afterwards, which is a different answer.
        emitting(in: style.scaled(by: Self.abstractScale), colour: RFCColors.secondaryLabel) {
            appendBlocks(blocks, indent: 0)
        }
    }

    /// The abstract introduces the document rather than being part of it, so it is
    /// set a little smaller and in the secondary colour.
    static let abstractScale: CGFloat = 0.94

    /// Emits `body` in a different style and colour, restoring both afterwards.
    private func emitting(in style: ReadingStyle, colour: PlatformColor, _ body: () -> Void) {
        let outerStyle = self.style
        let outerColour = bodyColour
        self.style = style
        bodyColour = colour
        body()
        self.style = outerStyle
        bodyColour = outerColour
    }

    private func appendSection(_ section: Section, depth: Int) {
        // The bibliography is not part of the reading flow: every citation in the
        // prose already links straight to the document it names, so the section is
        // several screens of rows nobody reads in order. It lives in a panel
        // instead — see `ReferencesPanel` in the app — and is skipped here, heading
        // and all, rather than left behind as an empty "9. References".
        guard !Self.holdsOnlyReferences(section) else { return }
        mark(section.anchor, isSection: true, heading: section.displayTitle)
        // Through the same inline path as prose, because a heading cites documents
        // the same way -- "8. Changes from [RFC 3066]". Everything the heading needs
        // is in `base`, so the anchor, the font and the spacing carry across the
        // reference's own runs and the chip is set at heading size.
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: style.headingFont(depth: depth),
            .foregroundColor: RFCColors.label,
            .rfcAnchor: section.anchor,
            .paragraphStyle: paragraphStyle(spacingBefore: style.paragraphSpacing * 1.6, spacingAfter: style.paragraphSpacing * 0.6),
        ]
        output.append(inlineRuns(section.displayTitleInlines, base: headingAttributes))
        append("\n", headingAttributes)
        appendBlocks(section.blocks, indent: 0)
        for subsection in section.subsections {
            appendSection(subsection, depth: depth + 1)
        }
    }

    /// True when nothing in this section, or anything below it, is prose: only
    /// bibliography entries. A `References` section is usually empty itself and
    /// carries `Normative` and `Informative` subsections, so this has to recurse
    /// before it can say the whole tree is skippable.
    static func holdsOnlyReferences(_ section: Section) -> Bool {
        guard !section.blocks.isEmpty || !section.subsections.isEmpty else { return false }
        let blocksAreReferences = section.blocks.allSatisfy { block in
            if case .references = block { return true }
            return false
        }
        return blocksAreReferences && section.subsections.allSatisfy(holdsOnlyReferences)
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
            case .references:
                // Skipped: see `holdsOnlyReferences`. A `.references` block outside a
                // bibliography section would land here, and is still not body prose.
                continue
            }
        }
    }

    func appendParagraph(_ paragraph: Paragraph, indent: CGFloat) {
        mark(paragraph.anchor)
        let attributes = bodyAttributes(indent: indent)
        output.append(inlineRuns(paragraph.inlines, base: attributes))
        append("\n", attributes)
    }

    func bodyAttributes(indent: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: bodyColour,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing),
        ]
    }

    func paragraphStyle(
        indent: CGFloat = 0,
        firstLineIndent: CGFloat? = nil,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat,
        tabStops: [NSTextTab]? = nil,
        wraps: Bool = true,
        alignment: NSTextAlignment = .natural
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
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
