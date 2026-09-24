import Foundation

/// Writes an `RFCDocument` back out as RFCXML v3.
///
/// This exists for the corpus pipeline: legacy plain-text RFCs are parsed once, offline,
/// and published as XML so the app has a single runtime path. The output uses the same
/// conventions as the RFC Editor's prepped XML (`pn` part numbers, `anchor`s, `derivedContent`
/// omitted), so `RFCXMLParser` reads it back into an equivalent model. Cross references to
/// documents that have no entry in the References section become `<eref>`s pointing at
/// rfc-editor.org, which the parser resolves back into document references.
public struct RFCXMLSerializer: Sendable {
    public struct Options: Sendable {
        /// Written as a comment right after the XML declaration; say where the XML came from.
        public var generatorComment: String?
        /// Emitted as `<link rel="alternate">`, normally the original `.txt` URL.
        public var sourceURL: URL?

        public init(generatorComment: String? = nil, sourceURL: URL? = nil) {
            self.generatorComment = generatorComment
            self.sourceURL = sourceURL
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func serialize(_ document: RFCDocument) -> String {
        var writer = Writer()
        let referenceAnchors = Self.referenceAnchors(in: document)
        var context = Context(referenceAnchors: referenceAnchors)

        writer.raw("<?xml version='1.0' encoding='utf-8'?>")
        if let comment = options.generatorComment {
            writer.raw("<!-- \(comment.replacingOccurrences(of: "--", with: "- -")) -->")
        }

        var rfcAttributes: [(String, String)] = [("version", "3")]
        if let id = document.header.id, id.series == .rfc {
            rfcAttributes.append(("number", String(id.number)))
        }
        if let category = document.header.category, let code = Self.categoryCode(category) {
            rfcAttributes.append(("category", code))
        }
        if let draft = document.header.draftName { rfcAttributes.append(("docName", draft)) }
        if !document.header.obsoletes.isEmpty {
            rfcAttributes.append(("obsoletes", document.header.obsoletes.map { String($0.number) }.joined(separator: ", ")))
        }
        if !document.header.updates.isEmpty {
            rfcAttributes.append(("updates", document.header.updates.map { String($0.number) }.joined(separator: ", ")))
        }
        rfcAttributes.append(("xml:lang", "en"))

        writer.open("rfc", rfcAttributes)
        if let source = options.sourceURL {
            writer.empty("link", [("href", source.absoluteString), ("rel", "alternate")])
        }
        writeFront(document.header, writer: &writer, context: &context)

        // Everything up to the first references section or appendix is the middle.
        let backStart = document.sections.firstIndex { Self.isReferences($0) || $0.isAppendix } ?? document.sections.count
        writer.open("middle")
        for section in document.sections[..<backStart] {
            writeSection(section, writer: &writer, context: &context)
        }
        writer.close("middle")

        if backStart < document.sections.count {
            writer.open("back")
            for section in document.sections[backStart...] {
                if Self.isReferences(section) {
                    writeReferences(section, writer: &writer, context: &context)
                } else {
                    writeSection(section, writer: &writer, context: &context)
                }
            }
            writer.close("back")
        }
        writer.close("rfc")
        return writer.output
    }

    // MARK: - Front

    private func writeFront(_ header: DocumentHeader, writer: inout Writer, context: inout Context) {
        writer.open("front")
        var titleAttributes: [(String, String)] = []
        if let abbrev = header.abbreviatedTitle { titleAttributes.append(("abbrev", abbrev)) }
        writer.element("title", titleAttributes, text: header.title)
        if let id = header.id, id.series == .rfc {
            writer.empty("seriesInfo", [("name", "RFC"), ("value", String(id.number))])
        }
        for author in header.authors {
            var attributes: [(String, String)] = [("fullname", author.name)]
            if author.role?.lowercased().hasPrefix("ed") == true { attributes.append(("role", "editor")) }
            writer.empty("author", attributes)
        }
        if let date = header.date {
            var attributes: [(String, String)] = []
            if let month = date.monthName { attributes.append(("month", month)) }
            if let day = date.day { attributes.append(("day", String(day))) }
            attributes.append(("year", String(date.year)))
            writer.empty("date", attributes)
        }
        if let area = header.area { writer.element("area", text: area) }
        if let group = header.workingGroup { writer.element("workgroup", text: group) }
        for keyword in header.keywords { writer.element("keyword", text: keyword) }
        if !header.abstract.isEmpty {
            writer.open("abstract")
            for block in header.abstract { writeBlock(block, writer: &writer, context: &context) }
            writer.close("abstract")
        }
        writer.close("front")
    }

    // MARK: - Sections

    private func writeSection(_ section: Section, writer: inout Writer, context: inout Context) {
        var attributes: [(String, String)] = [("anchor", section.anchor)]
        if let number = section.number {
            attributes.append(("numbered", "true"))
            attributes.append(("pn", Self.partNumber(number, isAppendix: section.isAppendix)))
        } else {
            attributes.append(("numbered", "false"))
        }
        writer.open("section", attributes)
        writer.element("name", markup: inlineXML(section.title, context: &context))
        for block in section.blocks { writeBlock(block, writer: &writer, context: &context) }
        for subsection in section.subsections {
            if Self.isReferences(subsection) {
                writeReferences(subsection, writer: &writer, context: &context)
            } else {
                writeSection(subsection, writer: &writer, context: &context)
            }
        }
        writer.close("section")
    }

    private func writeReferences(_ section: Section, writer: inout Writer, context: inout Context) {
        var attributes: [(String, String)] = [("anchor", section.anchor)]
        if let number = section.number {
            attributes.append(("pn", Self.partNumber(number, isAppendix: section.isAppendix)))
        }
        writer.open("references", attributes)
        writer.element("name", markup: inlineXML(section.title, context: &context))
        for block in section.blocks {
            guard case .references(let list) = block else {
                context.warnings.append("dropped non-reference block in references section \(section.anchor)")
                continue
            }
            for reference in list.entries { writeReference(reference, writer: &writer) }
        }
        for subsection in section.subsections {
            writeReferences(subsection, writer: &writer, context: &context)
        }
        writer.close("references")
    }

    private func writeReference(_ reference: Reference, writer: inout Writer) {
        var attributes: [(String, String)] = [("anchor", reference.anchor)]
        if let url = reference.url { attributes.append(("target", url.absoluteString)) }
        writer.open("reference", attributes)
        writer.open("front")
        writer.element("title", text: reference.title.isEmpty ? (reference.rawText ?? reference.anchor) : reference.title)
        for author in reference.authors {
            let isEditor = author.hasSuffix(", Ed.")
            let name = isEditor ? String(author.dropLast(5)) : author
            var authorAttributes: [(String, String)] = [("fullname", name)]
            if isEditor { authorAttributes.append(("role", "editor")) }
            writer.empty("author", authorAttributes)
        }
        if let date = reference.date {
            var dateAttributes: [(String, String)] = []
            if let month = date.monthName { dateAttributes.append(("month", month)) }
            dateAttributes.append(("year", String(date.year)))
            writer.empty("date", dateAttributes)
        }
        writer.close("front")
        for info in reference.seriesInfo {
            writer.empty("seriesInfo", [("name", info.name), ("value", info.value)])
        }
        if let raw = reference.rawText, !reference.title.isEmpty {
            writer.element("refcontent", text: raw)
        }
        writer.close("reference")
    }

    // MARK: - Blocks

    private func writeBlock(_ block: Block, writer: inout Writer, context: inout Context) {
        switch block {
        case .paragraph(let paragraph):
            var attributes: [(String, String)] = []
            if let anchor = paragraph.anchor { attributes.append(("pn", anchor)) }
            writer.line("<t\(Writer.attributeString(attributes))>\(inlineXML(paragraph.inlines, context: &context))</t>")
        case .list(let list):
            var attributes: [(String, String)] = []
            let name: String
            switch list.style {
            case .bullet:
                name = "ul"
            case .bare:
                name = "ul"
                attributes.append(("empty", "true"))
            case .numbered(let format, let start):
                name = "ol"
                attributes.append(("type", format ?? "1"))
                attributes.append(("start", String(start)))
            }
            if list.isCompact { attributes.append(("spacing", "compact")) }
            writer.open(name, attributes)
            for item in list.items {
                var itemAttributes: [(String, String)] = []
                if let anchor = item.anchor { itemAttributes.append(("pn", anchor)) }
                writer.open("li", itemAttributes)
                for inner in item.blocks { writeBlock(inner, writer: &writer, context: &context) }
                writer.close("li")
            }
            writer.close(name)
        case .definitionList(let items):
            writer.open("dl")
            for item in items {
                var termAttributes: [(String, String)] = []
                if let anchor = item.anchor { termAttributes.append(("pn", anchor)) }
                writer.line("<dt\(Writer.attributeString(termAttributes))>\(inlineXML(item.term, context: &context))</dt>")
                writer.open("dd")
                for inner in item.definition { writeBlock(inner, writer: &writer, context: &context) }
                writer.close("dd")
            }
            writer.close("dl")
        case .preformatted(let preformatted):
            let name = preformatted.kind == .artwork ? "artwork" : "sourcecode"
            var attributes: [(String, String)] = []
            if let type = preformatted.type { attributes.append(("type", type)) }
            if let fileName = preformatted.name { attributes.append(("name", fileName)) }
            if let anchor = preformatted.anchor { attributes.append(("pn", anchor)) }
            writer.line("<\(name)\(Writer.attributeString(attributes))>")
            writer.raw(Writer.escape(preformatted.text))
            writer.raw("</\(name)>")
        case .figure(let figure):
            var attributes: [(String, String)] = []
            if let anchor = figure.anchor { attributes.append(("anchor", anchor)) }
            if let number = figure.number { attributes.append(("pn", "figure-\(number)")) }
            writer.open("figure", attributes)
            if let title = figure.title { writer.element("name", text: title) }
            for inner in figure.blocks { writeBlock(inner, writer: &writer, context: &context) }
            writer.close("figure")
        case .table(let table):
            var attributes: [(String, String)] = []
            if let anchor = table.anchor { attributes.append(("anchor", anchor)) }
            if let number = table.number { attributes.append(("pn", "table-\(number)")) }
            writer.open("table", attributes)
            if let title = table.title { writer.element("name", text: title) }
            if !table.header.isEmpty {
                writer.open("thead")
                for row in table.header {
                    writer.open("tr")
                    for cell in row { writer.line("<th>\(inlineXML(cell, context: &context))</th>") }
                    writer.close("tr")
                }
                writer.close("thead")
            }
            writer.open("tbody")
            for row in table.rows {
                writer.open("tr")
                for cell in row { writer.line("<td>\(inlineXML(cell, context: &context))</td>") }
                writer.close("tr")
            }
            writer.close("tbody")
            writer.close("table")
        case .blockQuote(let blocks):
            writer.open("blockquote")
            for inner in blocks { writeBlock(inner, writer: &writer, context: &context) }
            writer.close("blockquote")
        case .aside(let blocks):
            writer.open("aside")
            for inner in blocks { writeBlock(inner, writer: &writer, context: &context) }
            writer.close("aside")
        case .references(let list):
            // A reference list outside a references section: wrap it so it stays valid.
            writer.open("references", [("anchor", "refs-\(context.nextAutoAnchor())")])
            writer.element("name", text: list.title)
            for reference in list.entries { writeReference(reference, writer: &writer) }
            writer.close("references")
        }
    }

    // MARK: - Inlines

    private func inlineXML(_ inlines: [Inline], context: inout Context) -> String {
        var result = ""
        for inline in inlines {
            switch inline {
            case .text(let text):
                result += Writer.escape(text)
            case .emphasis(let inner):
                result += "<em>\(inlineXML(inner, context: &context))</em>"
            case .strong(let inner):
                result += "<strong>\(inlineXML(inner, context: &context))</strong>"
            case .code(let text):
                result += "<tt>\(Writer.escape(text))</tt>"
            case .superscript(let text):
                result += "<sup>\(Writer.escape(text))</sup>"
            case .subscript(let text):
                result += "<sub>\(Writer.escape(text))</sub>"
            case .link(let url, let inner):
                result += "<eref target=\"\(Writer.escapeAttribute(url.absoluteString))\">\(inlineXML(inner, context: &context))</eref>"
            case .crossReference(let xref):
                result += crossReferenceXML(xref, context: &context)
            case .lineBreak:
                result += "<br/>"
            }
        }
        return result
    }

    private func crossReferenceXML(_ xref: CrossReference, context: inout Context) -> String {
        let content = xref.text.map(Writer.escape) ?? ""
        switch xref.target {
        case .anchor(let anchor):
            let target = Writer.escapeAttribute(anchor)
            return content.isEmpty ? "<xref target=\"\(target)\"/>" : "<xref target=\"\(target)\">\(content)</xref>"
        case .document(let id, let section):
            if let anchor = context.referenceAnchors[id] {
                var attributes = " target=\"\(Writer.escapeAttribute(anchor))\""
                // The source's own wording, not a fixed "of": it decides how the label
                // reads on the way back in, and `bare` in particular means something
                // different enough that the reader declines to chip it.
                if let section {
                    attributes += " section=\"\(Writer.escapeAttribute(section))\""
                    attributes += " sectionFormat=\"\(xref.sectionFormat.rawValue)\""
                }
                return content.isEmpty ? "<xref\(attributes)/>" : "<xref\(attributes)>\(content)</xref>"
            }
            // No bibliography entry: an external link the parser maps back to a document reference.
            let url = RFCLink(id: id, section: section).webURL
            let label = content.isEmpty ? Writer.escape(id.displayName) : content
            return "<eref target=\"\(Writer.escapeAttribute(url.absoluteString))\">\(label)</eref>"
        }
    }

    // MARK: - Helpers

    private struct Context {
        var referenceAnchors: [DocumentID: String]
        var warnings: [String] = []
        private var autoAnchor = 0

        init(referenceAnchors: [DocumentID: String]) {
            self.referenceAnchors = referenceAnchors
        }

        mutating func nextAutoAnchor() -> Int {
            autoAnchor += 1
            return autoAnchor
        }
    }

    private static func referenceAnchors(in document: RFCDocument) -> [DocumentID: String] {
        var anchors: [DocumentID: String] = [:]
        func visit(_ blocks: [Block]) {
            for block in blocks {
                if case .references(let list) = block {
                    for reference in list.entries {
                        if let id = reference.documentID, anchors[id] == nil { anchors[id] = reference.anchor }
                    }
                }
            }
        }
        for section in document.allSections { visit(section.blocks) }
        return anchors
    }

    static func isReferences(_ section: Section) -> Bool {
        if section.blocks.contains(where: { if case .references = $0 { return true } else { return false } }) { return true }
        return !section.subsections.isEmpty && section.blocks.isEmpty && section.subsections.allSatisfy(isReferences)
    }

    /// `4.2` → `section-4.2`; appendix `A.1` → `section-appendix.a.1`.
    static func partNumber(_ number: String, isAppendix: Bool) -> String {
        guard isAppendix else { return "section-\(number)" }
        var parts = number.split(separator: ".").map(String.init)
        if let first = parts.first { parts[0] = first.lowercased() }
        return "section-appendix.\(parts.joined(separator: "."))"
    }

    static func categoryCode(_ category: String) -> String? {
        switch category.lowercased() {
        case "standards track", "std": "std"
        case "best current practice", "bcp": "bcp"
        case "informational", "info": "info"
        case "experimental", "exp": "exp"
        case "historic": "historic"
        default: nil
        }
    }

    private struct Writer {
        private(set) var output = ""
        private var depth = 0

        mutating func raw(_ string: String) {
            output += string
            output += "\n"
        }

        mutating func line(_ string: String) {
            output += String(repeating: "  ", count: depth)
            output += string
            output += "\n"
        }

        mutating func open(_ name: String, _ attributes: [(String, String)] = []) {
            line("<\(name)\(Self.attributeString(attributes))>")
            depth += 1
        }

        mutating func close(_ name: String) {
            depth -= 1
            line("</\(name)>")
        }

        mutating func empty(_ name: String, _ attributes: [(String, String)] = []) {
            line("<\(name)\(Self.attributeString(attributes))/>")
        }

        mutating func element(_ name: String, _ attributes: [(String, String)] = [], text: String) {
            line("<\(name)\(Self.attributeString(attributes))>\(Self.escape(text))</\(name)>")
        }

        /// The same, for content that is already XML -- a heading's inlines, which
        /// carry the `<xref>`s of the references cited in it.
        mutating func element(_ name: String, _ attributes: [(String, String)] = [], markup: String) {
            line("<\(name)\(Self.attributeString(attributes))>\(markup)</\(name)>")
        }

        static func attributeString(_ attributes: [(String, String)]) -> String {
            attributes.map { " \($0.0)=\"\(escapeAttribute($0.1))\"" }.joined()
        }

        static func escape(_ text: String) -> String {
            var result = ""
            result.reserveCapacity(text.count)
            for character in text {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                default:
                    // XML 1.0 forbids C0 control characters other than tab, newline and return.
                    if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                       scalar.value < 0x20, scalar != "\t", scalar != "\n", scalar != "\r" {
                        continue
                    }
                    result.append(character)
                }
            }
            return result
        }

        static func escapeAttribute(_ text: String) -> String {
            escape(text).replacingOccurrences(of: "\"", with: "&quot;")
        }
    }
}
