import Foundation

/// Parses RFCXML v3 (RFC 7991) as published by the RFC Editor into an `RFCDocument`.
///
/// The RFC Editor's "prepped" XML carries `pn` (part number) attributes and
/// `derivedContent` on cross references, which this parser leans on for stable
/// anchors and display text instead of re-implementing the numbering rules.
public struct RFCXMLParser: Sendable {
    public enum ParseError: Error, Sendable {
        case notAnRFC(rootElement: String)
        case malformed(String)
    }

    public init() {}

    public static func parse(_ data: Data) throws -> RFCDocument {
        try RFCXMLParser().parse(data)
    }

    public func parse(_ data: Data) throws -> RFCDocument {
        let root: XMLElement
        do {
            root = try XMLTreeBuilder.parse(data)
        } catch let error as XMLTreeError {
            switch error {
            case .malformed(let line, let column, let message):
                throw ParseError.malformed("line \(line), column \(column): \(message)")
            case .empty:
                throw ParseError.malformed("empty document")
            }
        }
        guard root.name == "rfc" else { throw ParseError.notAnRFC(rootElement: root.name) }

        var builder = Builder()
        // References first, so cross references in the body resolve to RFC numbers.
        let back = root.first("back")
        if let back {
            builder.indexReferences(in: back)
        }

        let header = builder.parseHeader(root)
        var sections: [Section] = []
        if let middle = root.first("middle") {
            sections += builder.parseSections(in: middle, appendix: false)
        }
        if let back {
            for element in back.elements {
                switch element.name {
                case "references":
                    sections.append(builder.parseReferencesSection(element))
                case "section":
                    sections.append(builder.parseSection(element, appendix: true))
                default:
                    break
                }
            }
        }
        return RFCDocument(header: header, sections: sections, source: .xml)
    }

    // MARK: - Builder

    private struct Builder {
        /// Reference anchor (e.g. `QUIC-TRANSPORT`) to the RFC it denotes.
        var referenceTargets: [String: DocumentID] = [:]

        mutating func indexReferences(in element: XMLElement) {
            for child in element.elements {
                switch child.name {
                case "reference":
                    if let anchor = child["anchor"], let id = parseReference(child).documentID {
                        referenceTargets[anchor] = id
                    }
                case "referencegroup":
                    if let anchor = child["anchor"], let id = DocumentID(parsing: anchor) {
                        referenceTargets[anchor] = id
                    }
                    indexReferences(in: child)
                case "references":
                    indexReferences(in: child)
                default:
                    break
                }
            }
        }

        // MARK: Header

        func parseHeader(_ rfc: XMLElement) -> DocumentHeader {
            let front = rfc.first("front")
            let titleElement = front?.first("title")
            var header = DocumentHeader(title: titleElement?.normalizedText ?? "")
            header.abbreviatedTitle = titleElement?["abbrev"]

            if let number = rfc["number"].flatMap(Int.init) {
                header.id = .rfc(number)
            } else if let series = front?.all("seriesInfo").first(where: { $0["name"] == "RFC" }),
                      let number = series["value"].flatMap(Int.init) {
                header.id = .rfc(number)
            }

            header.authors = (front?.all("author") ?? []).compactMap(parseAuthor)
            if let date = front?.first("date") {
                header.date = parseDate(date)
            }
            header.area = front?.first("area")?.normalizedText
            header.workingGroup = front?.first("workgroup")?.normalizedText
            header.keywords = (front?.all("keyword") ?? []).map(\.normalizedText).filter { !$0.isEmpty }
            if let abstract = front?.first("abstract") {
                header.abstract = parseBlocks(in: abstract)
            }
            header.obsoletes = parseDocumentList(rfc["obsoletes"])
            header.updates = parseDocumentList(rfc["updates"])
            header.category = rfc["category"].flatMap(categoryName)
            header.draftName = rfc["docName"]
            return header
        }

        private func categoryName(_ category: String) -> String {
            switch category {
            case "std": "Standards Track"
            case "bcp": "Best Current Practice"
            case "info": "Informational"
            case "exp": "Experimental"
            case "historic": "Historic"
            default: category
            }
        }

        private func parseDocumentList(_ value: String?) -> [DocumentID] {
            guard let value else { return [] }
            return value.split(whereSeparator: { $0 == "," || $0 == " " })
                .compactMap { Int($0) }
                .map { DocumentID.rfc($0) }
        }

        private func parseAuthor(_ element: XMLElement) -> Author? {
            var name = element["fullname"]
            if name == nil || name?.isEmpty == true {
                let parts = [element["initials"], element["surname"]].compactMap { $0 }.filter { !$0.isEmpty }
                name = parts.isEmpty ? nil : parts.joined(separator: " ")
            }
            if name == nil || name?.isEmpty == true {
                name = element.first("organization")?.normalizedText
            }
            guard let name, !name.isEmpty else { return nil }
            let role = element["role"] == "editor" ? "Editor" : nil
            return Author(name: name, role: role)
        }

        private func parseDate(_ element: XMLElement) -> PublicationDate? {
            guard let year = element["year"].flatMap(Int.init) else { return nil }
            let month = element["month"].flatMap(PublicationDate.month(from:))
            let day = element["day"].flatMap(Int.init)
            return PublicationDate(year: year, month: month, day: day)
        }

        // MARK: Sections

        func parseSections(in parent: XMLElement, appendix: Bool) -> [Section] {
            parent.all("section").map { parseSection($0, appendix: appendix) }
        }

        func parseSection(_ element: XMLElement, appendix: Bool) -> Section {
            let partNumber = element["pn"]
            let numbering = sectionNumber(fromPartNumber: partNumber)
            let isNumbered = element["numbered"] != "false"
            let anchor = element["anchor"] ?? partNumber ?? UUID().uuidString
            let title = element.first("name")?.normalizedText ?? ""
            let blocks = parseBlocks(in: element)
            let subsections = parseSections(in: element, appendix: appendix || numbering.isAppendix)
            return Section(
                anchor: anchor,
                number: isNumbered ? numbering.number : nil,
                title: title,
                blocks: blocks,
                subsections: subsections,
                // Unnumbered back matter (Acknowledgements, Authors' Addresses) is not an appendix.
                isAppendix: isNumbered && (appendix || numbering.isAppendix)
            )
        }

        /// `section-4.2` → `4.2`; `section-appendix.a.1` → `A.1`.
        private func sectionNumber(fromPartNumber partNumber: String?) -> (number: String?, isAppendix: Bool) {
            guard var value = partNumber, value.hasPrefix("section-") else { return (nil, false) }
            value.removeFirst("section-".count)
            if value.hasPrefix("appendix.") {
                value.removeFirst("appendix.".count)
                var parts = value.split(separator: ".").map(String.init)
                if let first = parts.first { parts[0] = first.uppercased() }
                return (parts.joined(separator: "."), true)
            }
            if value.first?.isNumber == true { return (value, false) }
            return (nil, false)
        }

        func parseReferencesSection(_ element: XMLElement) -> Section {
            let partNumber = element["pn"]
            let numbering = sectionNumber(fromPartNumber: partNumber)
            let title = element.first("name")?.normalizedText ?? "References"
            var entries: [Reference] = []
            var subsections: [Section] = []
            for child in element.elements {
                switch child.name {
                case "reference":
                    entries.append(parseReference(child))
                case "referencegroup":
                    entries.append(parseReferenceGroup(child))
                case "references":
                    subsections.append(parseReferencesSection(child))
                default:
                    break
                }
            }
            let blocks: [Block] = entries.isEmpty ? [] : [.references(ReferenceList(title: title, entries: entries))]
            return Section(
                anchor: element["anchor"] ?? partNumber ?? "references",
                number: numbering.number,
                title: title,
                blocks: blocks,
                subsections: subsections
            )
        }

        func parseReference(_ element: XMLElement) -> Reference {
            let front = element.first("front")
            let authors = (front?.all("author") ?? []).compactMap(parseAuthor).map { author in
                author.role == nil ? author.name : "\(author.name), Ed."
            }
            let seriesInfo: [(name: String, value: String)] = (element.all("seriesInfo") + (front?.all("seriesInfo") ?? [])).compactMap { info -> (name: String, value: String)? in
                guard let name = info["name"], let value = info["value"] else { return nil }
                return (name: name, value: value)
            }
            let refContent = element.first("refcontent")?.normalizedText
            return Reference(
                anchor: element["anchor"] ?? "",
                title: front?.first("title")?.normalizedText ?? "",
                authors: authors,
                date: front?.first("date").flatMap(parseDate),
                seriesInfo: seriesInfo,
                url: element["target"].flatMap(URL.init(string:)),
                rawText: refContent
            )
        }

        private func parseReferenceGroup(_ element: XMLElement) -> Reference {
            let anchor = element["anchor"] ?? ""
            let members = element.all("reference").map(parseReference)
            let memberNames = members.compactMap { $0.documentID?.displayName }
            var seriesInfo: [(name: String, value: String)] = []
            if let id = DocumentID(parsing: anchor) {
                seriesInfo.append((name: id.series.rawValue, value: String(id.number)))
            }
            return Reference(
                anchor: anchor,
                title: members.count == 1 ? members[0].title : "\(anchor) consists of \(memberNames.joined(separator: ", "))",
                authors: members.count == 1 ? members[0].authors : [],
                date: members.count == 1 ? members[0].date : nil,
                seriesInfo: seriesInfo,
                url: element["target"].flatMap(URL.init(string:))
            )
        }

        // MARK: Blocks

        private static let inlineElements: Set<String> = [
            "xref", "eref", "em", "strong", "tt", "sup", "sub", "bcp14", "br", "u",
            "spanx", "cref", "iref", "contact", "relref",
        ]

        /// Converts the children of a container element into blocks. Runs of loose text
        /// and inline elements (as found inside `<li>` or `<dd>`) become implicit paragraphs.
        func parseBlocks(in element: XMLElement) -> [Block] {
            var blocks: [Block] = []
            var pendingInline: [XMLNode] = []

            func flushInline() {
                guard !pendingInline.isEmpty else { return }
                let inlines = normalize(parseInlines(pendingInline))
                if !inlines.isEmpty {
                    blocks.append(.paragraph(Paragraph(inlines)))
                }
                pendingInline = []
            }

            for node in element.children {
                switch node {
                case .text:
                    pendingInline.append(node)
                case .element(let child):
                    if Self.inlineElements.contains(child.name) {
                        pendingInline.append(node)
                        continue
                    }
                    flushInline()
                    if let block = parseBlock(child) {
                        blocks.append(block)
                    }
                }
            }
            flushInline()
            return blocks
        }

        private func parseBlock(_ element: XMLElement) -> Block? {
            switch element.name {
            case "t":
                let inlines = normalize(parseInlines(element.children))
                guard !inlines.isEmpty else { return nil }
                return .paragraph(Paragraph(inlines, anchor: element["anchor"] ?? element["pn"]))
            case "ul":
                let style: ListBlock.Style = element["empty"] == "true" ? .bare : .bullet
                return .list(ListBlock(style: style, items: parseListItems(element), isCompact: element["spacing"] == "compact"))
            case "ol":
                let start = element["start"].flatMap(Int.init) ?? 1
                return .list(ListBlock(
                    style: .numbered(format: element["type"], start: start),
                    items: parseListItems(element),
                    isCompact: element["spacing"] == "compact"
                ))
            case "dl":
                return .definitionList(parseDefinitionItems(element))
            case "artwork":
                return .preformatted(parseArtwork(element, kind: .artwork))
            case "sourcecode":
                return .preformatted(parseArtwork(element, kind: .sourceCode))
            case "artset":
                // Prefer the ASCII alternative; SVG needs a dedicated renderer.
                let alternatives = element.all("artwork")
                let chosen = alternatives.first { $0["type"] == "ascii-art" } ?? alternatives.first
                return chosen.map { .preformatted(parseArtwork($0, kind: .artwork)) }
            case "figure":
                let number = element["pn"].flatMap { partNumber -> Int? in
                    guard partNumber.hasPrefix("figure-") else { return nil }
                    return Int(partNumber.dropFirst("figure-".count))
                }
                var inner = element
                inner.children.removeAll {
                    if case .element(let child) = $0 { return child.name == "name" || child.name == "preamble" || child.name == "postamble" }
                    return false
                }
                var blocks: [Block] = []
                if let preamble = element.first("preamble") {
                    blocks.append(.paragraph(Paragraph(normalize(parseInlines(preamble.children)))))
                }
                blocks += parseBlocks(in: inner)
                if let postamble = element.first("postamble") {
                    blocks.append(.paragraph(Paragraph(normalize(parseInlines(postamble.children)))))
                }
                return .figure(Figure(
                    title: element.first("name")?.normalizedText,
                    number: number,
                    blocks: blocks,
                    anchor: element["anchor"]
                ))
            case "table":
                return .table(parseTable(element))
            case "blockquote":
                return .blockQuote(parseBlocks(in: element))
            case "aside":
                return .aside(parseBlocks(in: element))
            case "name", "section", "toc", "boilerplate":
                return nil
            case "texttable", "list", "vspace", "preamble", "postamble", "ttcol", "c":
                // RFCXML v2 leftovers; the prepped RFC Editor output does not contain them.
                return nil
            default:
                // Unknown container: keep its content rather than dropping text.
                let blocks = parseBlocks(in: element)
                return blocks.count == 1 ? blocks[0] : (blocks.isEmpty ? nil : .aside(blocks))
            }
        }

        private func parseListItems(_ element: XMLElement) -> [ListItem] {
            element.all("li").map { item in
                ListItem(blocks: parseBlocks(in: item), anchor: item["anchor"] ?? item["pn"])
            }
        }

        private func parseDefinitionItems(_ element: XMLElement) -> [DefinitionItem] {
            var items: [DefinitionItem] = []
            var pendingTerm: [Inline]?
            var pendingAnchor: String?
            for child in element.elements {
                switch child.name {
                case "dt":
                    pendingTerm = normalize(parseInlines(child.children))
                    pendingAnchor = child["anchor"] ?? child["pn"]
                case "dd":
                    items.append(DefinitionItem(
                        term: pendingTerm ?? [],
                        definition: parseBlocks(in: child),
                        anchor: pendingAnchor
                    ))
                    pendingTerm = nil
                    pendingAnchor = nil
                default:
                    break
                }
            }
            if let pendingTerm {
                items.append(DefinitionItem(term: pendingTerm, definition: [], anchor: pendingAnchor))
            }
            return items
        }

        private func parseArtwork(_ element: XMLElement, kind: Preformatted.Kind) -> Preformatted {
            var text = element.text
            // The RFC Editor wraps artwork in newlines for readability of the XML itself.
            while text.hasPrefix("\n") { text.removeFirst() }
            while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
            let type = element["type"].flatMap { $0.isEmpty ? nil : $0 }
            let name = element["name"].flatMap { $0.isEmpty ? nil : $0 }
            return Preformatted(kind: kind, text: text, type: type, name: name, anchor: element["anchor"] ?? element["pn"])
        }

        private func parseTable(_ element: XMLElement) -> Table {
            func rows(in container: XMLElement?) -> [[[Inline]]] {
                (container?.all("tr") ?? []).map { row in
                    row.elements.filter { $0.name == "th" || $0.name == "td" }
                        .map { normalize(parseInlines($0.children)) }
                }
            }
            let number = element["pn"].flatMap { partNumber -> Int? in
                guard partNumber.hasPrefix("table-") else { return nil }
                return Int(partNumber.dropFirst("table-".count))
            }
            return Table(
                title: element.first("name")?.normalizedText,
                number: number,
                header: rows(in: element.first("thead")),
                rows: rows(in: element.first("tbody")) + rows(in: element.first("tfoot")),
                anchor: element["anchor"]
            )
        }

        // MARK: Inlines

        func parseInlines(_ nodes: [XMLNode]) -> [Inline] {
            var result: [Inline] = []
            for node in nodes {
                switch node {
                case .text(let text):
                    result.append(.text(text))
                case .element(let element):
                    result += parseInline(element)
                }
            }
            return result
        }

        private func parseInline(_ element: XMLElement) -> [Inline] {
            switch element.name {
            case "xref", "relref":
                return [.crossReference(parseCrossReference(element))]
            case "eref":
                let inner = parseInlines(element.children)
                guard let target = element["target"], let url = URL(string: target) else { return inner }
                // Links into the RFC series are document references, whichever site they point at.
                if let link = RFCLink(url: url), link.id.series == .rfc {
                    let text = inner.isEmpty ? nil : inner.plainText.collapsingWhitespace()
                    return [.crossReference(CrossReference(target: .document(link.id, section: link.section), text: text))]
                }
                return [.link(url, inner.isEmpty ? [.text(target)] : inner)]
            case "em":
                return [.emphasis(parseInlines(element.children))]
            case "strong", "bcp14":
                return [.strong(parseInlines(element.children))]
            case "tt":
                return [.code(element.text)]
            case "sup":
                return [.superscript(element.text)]
            case "sub":
                return [.subscript(element.text)]
            case "br":
                return [.lineBreak]
            case "spanx":
                switch element["style"] {
                case "verb": return [.code(element.text)]
                case "strong": return [.strong(parseInlines(element.children))]
                default: return [.emphasis(parseInlines(element.children))]
                }
            case "contact":
                return [.text(element["fullname"] ?? element.text)]
            case "cref", "iref":
                return []
            default:
                return parseInlines(element.children)
            }
        }

        private func parseCrossReference(_ element: XMLElement) -> CrossReference {
            let targetAnchor = element["target"] ?? ""
            let section = element["section"]
            let innerText = element.normalizedText
            let derived = element["derivedContent"].flatMap { $0.isEmpty ? nil : $0 }
            let format = element["format"] ?? "default"

            if let id = referenceTargets[targetAnchor] {
                let label = "[\(derived ?? targetAnchor)]"
                let text: String
                if !innerText.isEmpty {
                    text = innerText
                } else if let section {
                    switch element["sectionFormat"] {
                    case "comma": text = "\(label), Section \(section)"
                    case "parens": text = "\(label) (Section \(section))"
                    case "bare": text = section
                    default: text = "Section \(section) of \(label)"
                    }
                } else if format == "counter" || format == "title" {
                    text = derived ?? label
                } else {
                    text = label
                }
                return CrossReference(target: .document(id, section: section), text: text)
            }

            let text = innerText.isEmpty ? derived : innerText
            return CrossReference(target: .anchor(targetAnchor), text: text)
        }

        /// Collapses whitespace the way HTML rendering would: runs become one space,
        /// and the paragraph is trimmed at both ends. Code and verbatim spans are untouched.
        func normalize(_ inlines: [Inline]) -> [Inline] {
            var result: [Inline] = []
            for inline in inlines {
                switch inline {
                case .text(let text):
                    let hadLeading = text.first?.isWhitespace == true
                    let hadTrailing = text.last?.isWhitespace == true
                    var collapsed = text.collapsingWhitespace()
                    if collapsed.isEmpty {
                        collapsed = (hadLeading || hadTrailing) ? " " : ""
                    } else {
                        if hadLeading { collapsed = " " + collapsed }
                        if hadTrailing { collapsed += " " }
                    }
                    if collapsed.isEmpty { continue }
                    if collapsed == " ", case .text(let previous)? = result.last, previous.hasSuffix(" ") { continue }
                    if case .text(let previous)? = result.last {
                        result[result.count - 1] = .text(previous + collapsed)
                    } else {
                        result.append(.text(collapsed))
                    }
                case .emphasis(let inner):
                    result.append(.emphasis(normalize(inner)))
                case .strong(let inner):
                    result.append(.strong(normalize(inner)))
                case .link(let url, let inner):
                    result.append(.link(url, normalize(inner)))
                default:
                    result.append(inline)
                }
            }
            // Trim the paragraph ends.
            if case .text(let first)? = result.first {
                let trimmed = String(first.drop(while: \.isWhitespace))
                if trimmed.isEmpty { result.removeFirst() } else { result[0] = .text(trimmed) }
            }
            if case .text(let last)? = result.last {
                var trimmed = last
                while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
                if trimmed.isEmpty { result.removeLast() } else { result[result.count - 1] = .text(trimmed) }
            }
            return result
        }
    }
}
