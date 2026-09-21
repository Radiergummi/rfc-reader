import Foundation

/// Where a parsed document came from. Drives which reading modes make sense.
public enum DocumentSource: String, Sendable, Codable {
    /// Semantic RFCXML v3 (RFC 7991). Everything is structured.
    case xml
    /// Legacy plain text; structure was recovered heuristically.
    case text
}

/// A parsed RFC, independent of the source format.
///
/// The renderer works exclusively against this model, so the same SwiftUI code
/// handles a 1990 text-only RFC and a 2026 RFCXML document.
public struct RFCDocument: Sendable {
    public var header: DocumentHeader
    /// Sections of the body (`<middle>` in RFCXML) and back matter (references, appendices).
    public var sections: [Section]
    public var source: DocumentSource

    public init(header: DocumentHeader, sections: [Section], source: DocumentSource) {
        self.header = header
        self.sections = sections
        self.source = source
    }

    /// Depth-first list of every section, for tables of contents and anchor lookup.
    public var allSections: [Section] {
        var result: [Section] = []
        func visit(_ section: Section) {
            result.append(section)
            section.subsections.forEach(visit)
        }
        sections.forEach(visit)
        return result
    }

    public func section(anchor: String) -> Section? {
        allSections.first { $0.anchor == anchor }
    }

    public func section(number: String) -> Section? {
        allSections.first { $0.number == number }
    }

    /// Every RFC referenced anywhere in the document, deduplicated and sorted.
    public var referencedDocuments: [DocumentID] {
        var seen: Set<DocumentID> = []
        func visitInlines(_ inlines: [Inline]) {
            for inline in inlines {
                switch inline {
                case .crossReference(let xref):
                    if case .document(let id, _) = xref.target { seen.insert(id) }
                case .emphasis(let inner), .strong(let inner), .link(_, let inner):
                    visitInlines(inner)
                default:
                    break
                }
            }
        }
        func visitBlocks(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .paragraph(let paragraph): visitInlines(paragraph.inlines)
                case .list(let list): list.items.forEach { visitBlocks($0.blocks) }
                case .definitionList(let items):
                    for item in items {
                        visitInlines(item.term)
                        visitBlocks(item.definition)
                    }
                case .figure(let figure): visitBlocks(figure.blocks)
                case .table(let table):
                    (table.header + table.rows).forEach { row in row.forEach { visitInlines($0) } }
                case .blockQuote(let inner), .aside(let inner): visitBlocks(inner)
                case .references(let list):
                    for reference in list.entries {
                        if let id = reference.documentID { seen.insert(id) }
                    }
                case .preformatted:
                    break
                }
            }
        }
        for section in allSections { visitBlocks(section.blocks) }
        return seen.sorted()
    }
}

public struct DocumentHeader: Sendable {
    public var id: DocumentID?
    public var title: String
    public var abbreviatedTitle: String?
    public var authors: [Author]
    public var date: PublicationDate?
    public var abstract: [Block]
    public var keywords: [String]
    public var workingGroup: String?
    public var area: String?
    public var obsoletes: [DocumentID]
    public var updates: [DocumentID]
    public var category: String?
    public var draftName: String?

    public init(
        id: DocumentID? = nil,
        title: String,
        abbreviatedTitle: String? = nil,
        authors: [Author] = [],
        date: PublicationDate? = nil,
        abstract: [Block] = [],
        keywords: [String] = [],
        workingGroup: String? = nil,
        area: String? = nil,
        obsoletes: [DocumentID] = [],
        updates: [DocumentID] = [],
        category: String? = nil,
        draftName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.abbreviatedTitle = abbreviatedTitle
        self.authors = authors
        self.date = date
        self.abstract = abstract
        self.keywords = keywords
        self.workingGroup = workingGroup
        self.area = area
        self.obsoletes = obsoletes
        self.updates = updates
        self.category = category
        self.draftName = draftName
    }
}

public struct Section: Sendable, Identifiable {
    /// Stable anchor, e.g. `section-4.2` or the author's own `anchor` attribute.
    public var anchor: String
    /// `1`, `4.2`, `A`, `B.1`; nil for unnumbered sections such as "Acknowledgements".
    public var number: String?
    public var title: String
    public var blocks: [Block]
    public var subsections: [Section]
    /// True for appendices; affects numbering display.
    public var isAppendix: Bool

    public var id: String { anchor }

    public init(
        anchor: String,
        number: String? = nil,
        title: String,
        blocks: [Block] = [],
        subsections: [Section] = [],
        isAppendix: Bool = false
    ) {
        self.anchor = anchor
        self.number = number
        self.title = title
        self.blocks = blocks
        self.subsections = subsections
        self.isAppendix = isAppendix
    }

    /// `4.2. Title` or `Appendix A. Title` or just the title.
    public var displayTitle: String {
        guard let number else { return title }
        return isAppendix ? "Appendix \(number). \(title)" : "\(number). \(title)"
    }

    public var depth: Int {
        guard let number else { return 1 }
        return number.split(separator: ".").count
    }
}

public indirect enum Block: Sendable {
    case paragraph(Paragraph)
    case list(ListBlock)
    case definitionList([DefinitionItem])
    case preformatted(Preformatted)
    case figure(Figure)
    case table(Table)
    case blockQuote([Block])
    case aside([Block])
    case references(ReferenceList)
}

public struct Paragraph: Sendable {
    public var inlines: [Inline]
    public var anchor: String?

    public init(_ inlines: [Inline], anchor: String? = nil) {
        self.inlines = inlines
        self.anchor = anchor
    }

    public init(text: String, anchor: String? = nil) {
        self.init([.text(text)], anchor: anchor)
    }

    public var plainText: String { inlines.plainText }
}

public struct ListBlock: Sendable {
    public enum Style: Sendable, Equatable {
        case bullet
        /// Numbered with the given format, e.g. `%d.` or `(%c)`; nil means plain decimal.
        case numbered(format: String?, start: Int)
        /// No marker; used for hanging indents and the RFCXML `empty` attribute.
        case bare
    }

    public var style: Style
    public var items: [ListItem]
    public var isCompact: Bool

    public init(style: Style, items: [ListItem], isCompact: Bool = false) {
        self.style = style
        self.items = items
        self.isCompact = isCompact
    }
}

public struct ListItem: Sendable {
    public var blocks: [Block]
    public var anchor: String?

    public init(blocks: [Block], anchor: String? = nil) {
        self.blocks = blocks
        self.anchor = anchor
    }

    public init(text: String) {
        self.init(blocks: [.paragraph(Paragraph(text: text))])
    }
}

public struct DefinitionItem: Sendable {
    public var term: [Inline]
    public var definition: [Block]
    public var anchor: String?

    public init(term: [Inline], definition: [Block], anchor: String? = nil) {
        self.term = term
        self.definition = definition
        self.anchor = anchor
    }
}

/// Verbatim monospaced content: ASCII art, packet diagrams, ABNF, code.
public struct Preformatted: Sendable {
    public enum Kind: Sendable, Equatable {
        case artwork
        case sourceCode
    }

    public var kind: Kind
    public var text: String
    /// Language hint from `<sourcecode type="abnf">`, or an artwork type such as `svg`.
    public var type: String?
    public var name: String?
    public var anchor: String?

    public init(kind: Kind, text: String, type: String? = nil, name: String? = nil, anchor: String? = nil) {
        self.kind = kind
        self.text = text
        self.type = type
        self.name = name
        self.anchor = anchor
    }
}

public struct Figure: Sendable {
    public var title: String?
    public var number: Int?
    public var blocks: [Block]
    public var anchor: String?

    public init(title: String?, number: Int? = nil, blocks: [Block], anchor: String? = nil) {
        self.title = title
        self.number = number
        self.blocks = blocks
        self.anchor = anchor
    }
}

public struct Table: Sendable {
    public var title: String?
    public var number: Int?
    public var header: [[[Inline]]]
    public var rows: [[[Inline]]]
    public var anchor: String?

    public init(title: String?, number: Int? = nil, header: [[[Inline]]], rows: [[[Inline]]], anchor: String? = nil) {
        self.title = title
        self.number = number
        self.header = header
        self.rows = rows
        self.anchor = anchor
    }
}

extension Reference {
    /// `BCP 14 · March 1997` — where a reference sits in the series and when it was
    /// published, as one short line. The DOI is dropped: it names the same document
    /// again, in the one form nobody reads. A short form of what `CitationFormatter`
    /// spells out in full.
    public var provenance: String {
        let series = seriesInfo.filter { $0.name != "DOI" }.map { "\($0.name) \($0.value)" }
        return (series + [date?.formatted].compactMap { $0 }).joined(separator: " · ")
    }
}

public struct ReferenceList: Sendable {
    public var title: String
    public var entries: [Reference]

    public init(title: String, entries: [Reference]) {
        self.title = title
        self.entries = entries
    }
}

/// One bibliographic entry, e.g. `[RFC7301]`.
public struct Reference: Sendable, Identifiable {
    public var anchor: String
    public var title: String
    public var authors: [String]
    public var date: PublicationDate?
    /// `RFC 7301`, `DOI 10.17487/RFC7301`, `STD 90`, ...
    public var seriesInfo: [(name: String, value: String)]
    public var url: URL?
    /// Free-form fallback when the reference came from legacy text and could not be structured.
    public var rawText: String?

    public var id: String { anchor }

    public init(
        anchor: String,
        title: String,
        authors: [String] = [],
        date: PublicationDate? = nil,
        seriesInfo: [(name: String, value: String)] = [],
        url: URL? = nil,
        rawText: String? = nil
    ) {
        self.anchor = anchor
        self.title = title
        self.authors = authors
        self.date = date
        self.seriesInfo = seriesInfo
        self.url = url
        self.rawText = rawText
    }

    /// The RFC/BCP/STD this reference points at, when it is one.
    public var documentID: DocumentID? {
        let ids = seriesInfo.compactMap { info -> DocumentID? in
            guard let series = DocumentID.Series(rawValue: info.name.uppercased()), let number = Int(info.value) else { return nil }
            return DocumentID(series: series, number: number)
        }
        // A BCP or STD reference usually also names its RFC; the RFC is the thing to open.
        return ids.first { $0.series == .rfc } ?? ids.first ?? DocumentID(parsing: anchor)
    }
}

public struct CrossReference: Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        /// Another place in the same document, by anchor.
        case anchor(String)
        /// Another RFC, optionally a specific section within it.
        case document(DocumentID, section: String?)
    }

    public var target: Target
    /// Text to display; nil means the renderer derives it (`Section 4.2`, `[RFC9110]`).
    public var text: String?
    /// True when this label is a canonical series id in brackets that a renderer may
    /// replace with a chip, without losing information.
    /// False for an author's own tag (`[QUIC-TRANSPORT]`), which is the name the
    /// document uses throughout and must survive verbatim.
    public var isCanonicalLabel: Bool

    public init(target: Target, text: String? = nil, isCanonicalLabel: Bool = false) {
        self.target = target
        self.text = text
        self.isCanonicalLabel = isCanonicalLabel
    }

    /// The label this reference shows: its own `text` when it has one, otherwise the
    /// one derived from the target. `[Inline].plainText` and the reader's renderer
    /// both go through this, so a copied selection and the rendered text cannot
    /// disagree.
    public var label: String {
        if let text { return text }
        switch target {
        case .anchor(let anchor):
            return anchor
        case .document(let id, let section):
            return section.map { "Section \($0) of \(id.displayName)" } ?? "[\(id.description)]"
        }
    }

    /// How a reader lays this reference out: the text it shows, and which part of
    /// that text — if any — may be drawn as a chip.
    ///
    /// One rule, in one place, because the screen and a copied selection have to
    /// agree. The renderer used to compose the section form itself while
    /// `plainText` kept the parser's phrasing, so copying `RFC 9110 § 4.2` off the
    /// screen yielded "Section 4.2 of [RFC 9110]".
    public struct Display: Sendable, Equatable {
        public let text: String
        /// The span of `text` a chip covers, or nil when the reference reads as
        /// ordinary link text.
        public let chip: Range<String.Index>?
    }

    public var display: Display {
        let label = self.label
        // `isCanonicalLabel` says the tag is the series' own spelling; the brackets
        // say the *parser* composed this label, rather than the author supplying
        // their own words for the link. Only then may a renderer restyle it.
        guard isCanonicalLabel,
              case .document(let id, let section) = target,
              let bracketed = Self.bracketedRange(in: label) else {
            return Display(text: label, chip: nil)
        }
        if let section {
            // One reference to one place, so it reads as one chip: the section is a
            // suffix of the document it is in, not a sentence with the document
            // buried in the middle of it.
            let text = "\(Self.nonBreakingLabel(id.displayName))\u{00A0}§\u{00A0}\(section)"
            return Display(text: text, chip: text.startIndex..<text.endIndex)
        }
        // The chip's tint replaces the brackets, so the brackets come out.
        let before = String(label[label.startIndex..<bracketed.lowerBound])
        let inner = String(label[label.index(after: bracketed.lowerBound)..<label.index(before: bracketed.upperBound)])
        let text = before + inner + String(label[bracketed.upperBound...])
        let start = text.index(text.startIndex, offsetBy: before.count)
        return Display(text: text, chip: start..<text.index(start, offsetBy: inner.count))
    }

    /// The text a reader shows for this reference — what `[Inline].plainText`
    /// flattens to, and what the reader draws.
    public var displayLabel: String { display.text }

    /// The `[...]` span in a label, brackets included, or nil if there is none.
    static func bracketedRange(in label: String) -> Range<String.Index>? {
        guard let open = label.firstIndex(of: "["), let close = label.lastIndex(of: "]"), open < close else { return nil }
        return open..<label.index(after: close)
    }

    /// A label should never break between its word and its number, so "RFC 9110"
    /// and "Section 4.2" are joined with U+00A0.
    nonisolated(unsafe) private static let labelNumberPattern = #/(\p{L})[ \t]+(\d)/#

    static func nonBreakingLabel(_ label: String) -> String {
        label.replacing(labelNumberPattern) { match in "\(match.1)\u{00A0}\(match.2)" }
    }

    /// True when `tag` is exactly how the series spells `id` — `[RFC9110]` — rather
    /// than a tag the author chose (`[QUIC-TRANSPORT]`), which is the name the
    /// document uses throughout and must survive verbatim. This is what licenses a
    /// renderer to replace the brackets with a chip.
    ///
    /// One predicate for both parsers on purpose: they each used to decide it, and
    /// they disagreed about case, so the same reference could draw as a chip from
    /// one source format and as plain text from the other.
    public static func isCanonicalTag(_ tag: String, for id: DocumentID) -> Bool {
        tag.caseInsensitiveCompare(id.description) == .orderedSame
    }
}

public indirect enum Inline: Sendable, Hashable {
    case text(String)
    case emphasis([Inline])
    case strong([Inline])
    case code(String)
    case superscript(String)
    case `subscript`(String)
    /// External link (`<eref>` or a bare URL in text).
    case link(URL, [Inline])
    case crossReference(CrossReference)
    case lineBreak
}

extension Array where Element == Inline {
    /// Flattened plain text, with derived text for cross references.
    public var plainText: String {
        map { inline -> String in
            switch inline {
            case .text(let text), .code(let text), .superscript(let text), .subscript(let text): text
            case .emphasis(let inner), .strong(let inner), .link(_, let inner): inner.plainText
            case .crossReference(let xref): xref.displayLabel
            case .lineBreak: "\n"
            }
        }.joined()
    }
}
