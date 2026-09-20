import Foundation

/// Recovers document structure from the classic 72-column plain-text RFC format
/// used for everything before RFC 8650 (and still published for every RFC).
///
/// This is deliberately heuristic. It removes page furniture, detects headings,
/// distinguishes prose from ASCII art, re-joins paragraphs split across pages and
/// links `[RFC2119]`, `RFC 2119`, `Section 4.2` and URLs. The original text is always
/// kept available through `stripPagination(_:)` for an "as published" view.
public struct LegacyTextParser: Sendable {
    public init() {}

    public static func parse(_ text: String) -> RFCDocument {
        LegacyTextParser().parse(text)
    }

    public static func parse(_ data: Data) -> RFCDocument {
        parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Pagination

    private enum Line: Sendable {
        case text(String)
        case pageBreak
    }

    nonisolated(unsafe) private static let footerPattern = #/\[Page \d+\]\s*$/#
    nonisolated(unsafe) private static let runningHeaderPattern = #/^(RFC|Request for Comments:?)\s*\d+\b.*\b\d{4}\s*$/#

    /// Removes form feeds, running headers and page footers, keeping everything else verbatim.
    public static func stripPagination(_ text: String) -> String {
        var output: [String] = []
        var pendingBlank = 0
        var breakOccurred = false
        for line in depaginate(text) {
            switch line {
            case .pageBreak:
                breakOccurred = true
            case .text(let string):
                if string.trimmingCharacters(in: .whitespaces).isEmpty {
                    pendingBlank += 1
                } else {
                    if !output.isEmpty {
                        output += Array(repeating: "", count: breakOccurred ? min(pendingBlank, 1) : pendingBlank)
                    }
                    pendingBlank = 0
                    breakOccurred = false
                    output.append(string)
                }
            }
        }
        return output.joined(separator: "\n")
    }

    private static func depaginate(_ text: String) -> [Line] {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [Line] = []
        var expectingHeader = false
        var firstContentSeen = false

        for rawLine in rawLines {
            var line = String(rawLine)
            var sawFormFeed = false
            if line.contains("\u{0C}") {
                line = line.replacingOccurrences(of: "\u{0C}", with: "")
                sawFormFeed = true
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if firstContentSeen, trimmed.contains(footerPattern) {
                lines.append(.pageBreak)
                expectingHeader = true
                continue
            }
            if sawFormFeed {
                if case .pageBreak? = lines.last {} else { lines.append(.pageBreak) }
                expectingHeader = true
                if trimmed.isEmpty { continue }
            }
            if expectingHeader {
                if trimmed.isEmpty { continue }
                expectingHeader = false
                if trimmed.contains(runningHeaderPattern) { continue }
            }
            if !trimmed.isEmpty { firstContentSeen = true }
            lines.append(.text(line.trimmingTrailingWhitespace()))
        }
        return lines
    }

    // MARK: - Parsing

    private struct RawBlock {
        var lines: [String]
        var followedByPageBreak = false

        var indent: Int { lines.map(\.leadingSpaceCount).min() ?? 0 }
        var firstLine: String { lines.first ?? "" }
    }

    private struct HeadingInfo {
        var number: String?
        var title: String
        var isAppendix: Bool
        var anchor: String
        var depth: Int
    }

    private struct RawSection {
        var heading: HeadingInfo?
        var blocks: [RawBlock] = []
    }

    nonisolated(unsafe) private static let numberedHeadingPattern = #/^(?<number>\d+(?:\.\d+)*)\.?\s+(?<title>\S.*)$/#
    nonisolated(unsafe) private static let appendixHeadingPattern = #/^(?:Appendix\s+)?(?<number>[A-Z](?:\.\d+)*)\.?\s+(?<title>[A-Z].*)$/#

    public func parse(_ text: String) -> RFCDocument {
        let lines = Self.depaginate(text)
        let (frontLines, bodyStart) = Self.splitFrontMatter(lines)
        var header = Self.parseFrontMatter(frontLines)

        // Split the body into raw sections at column-0 headings.
        var sections: [RawSection] = [RawSection(heading: nil)]
        var current: [String] = []
        var pendingBreak = false

        func flushBlock() {
            if !current.isEmpty {
                sections[sections.count - 1].blocks.append(RawBlock(lines: current, followedByPageBreak: pendingBreak))
                current = []
            }
            pendingBreak = false
        }

        for line in lines[bodyStart...] {
            switch line {
            case .pageBreak:
                if current.isEmpty, var last = sections[sections.count - 1].blocks.popLast() {
                    last.followedByPageBreak = true
                    sections[sections.count - 1].blocks.append(last)
                } else {
                    pendingBreak = true
                    flushBlock()
                }
            case .text(let string):
                if string.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushBlock()
                } else if string.first != " ", let heading = Self.heading(from: string) {
                    flushBlock()
                    sections.append(RawSection(heading: heading))
                } else {
                    current.append(string)
                }
            }
        }
        flushBlock()

        // Collect known section numbers and reference anchors for link resolution.
        let sectionNumbers = Set(sections.compactMap { $0.heading?.number })
        var referenceTargets: [String: CrossReference.Target] = [:]
        for section in sections where section.heading.map(Self.isReferencesHeading) == true {
            for reference in Self.parseReferences(section.blocks) {
                if let id = reference.documentID {
                    referenceTargets[reference.anchor] = .document(id, section: nil)
                } else {
                    referenceTargets[reference.anchor] = .anchor("ref-\(reference.anchor)")
                }
            }
        }
        let linker = InlineLinker(sectionNumbers: sectionNumbers, referenceTargets: referenceTargets)

        // Convert raw sections into structured ones.
        var flat: [Section] = []
        for raw in sections {
            guard let heading = raw.heading else {
                // Text before the first heading that is not front matter: keep as an unnumbered lead-in.
                let blocks = Self.blocks(from: raw.blocks, linker: linker)
                if !blocks.isEmpty {
                    flat.append(Section(anchor: "preamble", title: "", blocks: blocks))
                }
                continue
            }
            let lowered = heading.title.lowercased()
            if heading.number == nil {
                if lowered == "abstract" {
                    header.abstract = Self.blocks(from: raw.blocks, linker: linker)
                    continue
                }
                // Boilerplate that the RFCXML path also omits; the original text view still has it.
                let boilerplate = ["table of contents", "status of this memo", "status of memo", "copyright notice",
                                   "full copyright statement", "intellectual property", "disclaimer of validity"]
                if boilerplate.contains(where: { lowered.hasPrefix($0) }) {
                    continue
                }
            }
            var section = Section(
                anchor: heading.anchor,
                number: heading.number,
                title: heading.title,
                isAppendix: heading.isAppendix
            )
            if Self.isReferencesHeading(heading) {
                let references = Self.parseReferences(raw.blocks)
                if !references.isEmpty {
                    section.blocks = [.references(ReferenceList(title: heading.title, entries: references))]
                } else {
                    section.blocks = Self.blocks(from: raw.blocks, linker: linker)
                }
            } else {
                section.blocks = Self.blocks(from: raw.blocks, linker: linker)
            }
            flat.append(section)
        }

        return RFCDocument(header: header, sections: Self.nest(flat), source: .text)
    }

    // MARK: Front matter

    /// Front matter runs from the top of the file to the first column-0 heading.
    private static func splitFrontMatter(_ lines: [Line]) -> (front: [String], bodyStart: Int) {
        var front: [String] = []
        var seenTitleCandidate = false
        for (offset, line) in lines.enumerated() {
            guard case .text(let string) = line else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                front.append("")
                continue
            }
            let isHeaderBlockLine = !seenTitleCandidate && string.first != " "
            if string.first != " ", !isHeaderBlockLine, heading(from: string) != nil {
                return (front, offset)
            }
            if string.first == " " { seenTitleCandidate = true }
            front.append(string)
        }
        return (front, lines.count)
    }

    nonisolated(unsafe) private static let monthYearPattern = #/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/#
    nonisolated(unsafe) private static let authorPattern = #/^(?:[A-Z]\.\s?)+\s*[A-Z][\w'\-]+(?:,\s*Ed(?:itor)?\.?)?$/#

    private static func parseFrontMatter(_ lines: [String]) -> DocumentHeader {
        var header = DocumentHeader(title: "")
        var index = 0
        while index < lines.count, lines[index].isEmpty { index += 1 }

        // Header block: two-column lines up to the first blank line.
        while index < lines.count, !lines[index].isEmpty {
            let line = lines[index]
            index += 1
            let columns = line.components(separatedBy: "   ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let left = columns.first else { continue }
            let right = columns.count > 1 ? columns.last! : nil

            if left.hasPrefix("Request for Comments:"), let number = Int(left.dropFirst("Request for Comments:".count).trimmingCharacters(in: .whitespaces)) {
                header.id = .rfc(number)
            } else if left.hasPrefix("Obsoletes:") {
                header.obsoletes = documentIDs(in: left)
            } else if left.hasPrefix("Updates:") {
                header.updates = documentIDs(in: left)
            } else if left.hasPrefix("Category:") {
                header.category = left.dropFirst("Category:".count).trimmingCharacters(in: .whitespaces)
            }

            for candidate in [left, right].compactMap({ $0 }) {
                if let match = candidate.firstMatch(of: monthYearPattern) {
                    header.date = PublicationDate(year: Int(match.2) ?? 0, month: PublicationDate.month(from: String(match.1)))
                } else if candidate == right, candidate.contains(authorPattern) {
                    header.authors.append(Author(name: candidate.replacingOccurrences(of: ", Ed.", with: ""), role: candidate.contains(", Ed") ? "Editor" : nil))
                }
            }
        }

        // Title: the next non-blank, indented lines.
        var titleLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.isEmpty {
                if !titleLines.isEmpty { break }
            } else if line.first == " " {
                titleLines.append(line.trimmingCharacters(in: .whitespaces))
            } else {
                break
            }
            index += 1
        }
        header.title = titleLines.joined(separator: " ")
        return header
    }

    private static func documentIDs(in text: String) -> [DocumentID] {
        text.matches(of: #/\d+/#).compactMap { Int($0.output) }.map { DocumentID.rfc($0) }
    }

    // MARK: Headings

    private static let nonHeadingWords: Set<String> = ["rfc", "request", "network", "internet", "obsoletes", "updates", "category", "issn"]

    private static func heading(from line: String) -> HeadingInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count < 120 else { return nil }
        if let match = trimmed.firstMatch(of: numberedHeadingPattern) {
            let number = String(match.number)
            let title = String(match.title).trimmingTrailingDots().collapsingWhitespace()
            return HeadingInfo(number: number, title: title, isAppendix: false, anchor: "section-\(number)", depth: number.split(separator: ".").count)
        }
        if let match = trimmed.firstMatch(of: appendixHeadingPattern) {
            let number = String(match.number)
            let title = String(match.title).trimmingTrailingDots().collapsingWhitespace()
            return HeadingInfo(number: number, title: title, isAppendix: true, anchor: "appendix-\(number)", depth: number.split(separator: ".").count)
        }
        // Unnumbered heading: "Abstract", "Security Considerations", "Author's Address".
        let firstWord = trimmed.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        guard !nonHeadingWords.contains(firstWord), trimmed.first?.isLetter == true else { return nil }
        return HeadingInfo(number: nil, title: trimmed, isAppendix: false, anchor: "name-\(trimmed.slugified())", depth: 1)
    }

    private static func isReferencesHeading(_ heading: HeadingInfo) -> Bool {
        heading.title.lowercased().contains("references")
    }

    private static func nest(_ flat: [Section]) -> [Section] {
        var roots: [Section] = []
        var stack: [(depth: Int, section: Section)] = []

        func attach(_ finished: Section) {
            if let parentIndex = stack.indices.last {
                stack[parentIndex].section.subsections.append(finished)
            } else {
                roots.append(finished)
            }
        }

        for section in flat {
            let depth = section.number == nil ? 1 : section.depth
            while let top = stack.last, top.depth >= depth {
                stack.removeLast()
                attach(top.section)
            }
            stack.append((depth, section))
        }
        while let top = stack.popLast() {
            attach(top.section)
        }
        return roots
    }

    // MARK: Blocks

    nonisolated(unsafe) private static let bulletPattern = #/^(?<indent>\s*)(?<marker>[o\-\*\u{2022}])\s+(?<text>\S.*)$/#
    nonisolated(unsafe) private static let numberedItemPattern = #/^(?<indent>\s*)(?<marker>\(?(?:\d+|[a-z]|[ivx]+)[\.\)])\s+(?<text>\S.*)$/#
    nonisolated(unsafe) private static let artworkPattern = #/\+-|-\+|\|\s|\s\||[\/\\]_|_[\/\\]|\.\.\.\.|={3,}|-{3,}|<-|->|\d\s{2,}\d/#

    private static func blocks(from rawBlocks: [RawBlock], linker: InlineLinker) -> [Block] {
        // Re-join paragraphs that a page break cut in half.
        var merged: [RawBlock] = []
        var index = 0
        while index < rawBlocks.count {
            var block = rawBlocks[index]
            while block.followedByPageBreak, index + 1 < rawBlocks.count,
                  shouldJoinAcrossPage(block, rawBlocks[index + 1]) {
                block.lines += rawBlocks[index + 1].lines
                block.followedByPageBreak = rawBlocks[index + 1].followedByPageBreak
                index += 1
            }
            merged.append(block)
            index += 1
        }

        var result: [Block] = []
        for block in merged {
            for parsed in classify(block, linker: linker) {
                // Merge adjacent list blocks of the same style into one list.
                if case .list(let list) = parsed, case .list(var previous)? = result.last, previous.style == list.style {
                    previous.items += list.items
                    result[result.count - 1] = .list(previous)
                } else {
                    result.append(parsed)
                }
            }
        }
        return result
    }

    private static func shouldJoinAcrossPage(_ first: RawBlock, _ second: RawBlock) -> Bool {
        guard looksLikeProse(first.lines), looksLikeProse(second.lines) else { return false }
        guard first.indent == second.indent else { return false }
        let lastLine = first.lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
        let nextLine = second.lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        if nextLine.first?.isLowercase == true { return true }
        if let last = lastLine.last, ".:!?".contains(last) { return false }
        return true
    }

    private static func looksLikeProse(_ lines: [String]) -> Bool {
        guard let first = lines.first else { return false }
        let indent = first.leadingSpaceCount
        guard indent <= 6 else { return false }
        for line in lines {
            if line.leadingSpaceCount != indent { return false }
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.contains(artworkPattern) { return false }
            if content.contains(#/[^.?!:]\s{3,}\S/#) { return false }
        }
        return true
    }

    private static func classify(_ block: RawBlock, linker: InlineLinker) -> [Block] {
        let lines = block.lines
        guard !lines.isEmpty else { return [] }

        // Lists: the first line carries a marker and every further item shares its indent.
        if let list = parseList(lines, linker: linker) {
            return [.list(list)]
        }

        if looksLikeProse(lines) {
            let inlines = linker.link(Self.joinWrappedLines(lines))
            return inlines.isEmpty ? [] : [.paragraph(Paragraph(inlines))]
        }

        // Anything else is preserved verbatim, minus the common indentation.
        let indent = block.indent
        let text = lines.map { line in
            String(line.dropFirst(min(indent, line.leadingSpaceCount)))
        }.joined(separator: "\n")
        // "Figure 3: Title" captions directly under artwork are common; keep them attached.
        return [.preformatted(Preformatted(kind: .artwork, text: text))]
    }

    /// Joins wrapped lines with spaces, except after a trailing hyphen, which in the
    /// RFC text format always marks a compound word broken at the hyphen (`point-` / `to-point`).
    private static func joinWrappedLines(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            let trimmed = line.collapsingWhitespace()
            if result.isEmpty {
                result = trimmed
            } else if result.hasSuffix("-"), trimmed.first?.isLowercase == true {
                result += trimmed
            } else {
                result += " " + trimmed
            }
        }
        return result
    }

    private static func parseList(_ lines: [String], linker: InlineLinker) -> ListBlock? {
        guard let first = lines.first else { return nil }
        let style: ListBlock.Style
        let itemIndent: Int
        if let match = first.firstMatch(of: bulletPattern) {
            style = .bullet
            itemIndent = match.indent.count
        } else if let match = first.firstMatch(of: numberedItemPattern) {
            let marker = String(match.marker)
            style = .numbered(format: marker.first == "(" ? "(%d)" : (marker.first?.isLetter == true ? "%c." : "%d."), start: 1)
            itemIndent = match.indent.count
        } else {
            return nil
        }

        var items: [[String]] = []
        for line in lines {
            let isItemStart: Bool
            if line.leadingSpaceCount == itemIndent {
                switch style {
                case .bullet: isItemStart = line.contains(bulletPattern)
                default: isItemStart = line.contains(numberedItemPattern)
                }
            } else {
                isItemStart = false
            }
            if isItemStart {
                items.append([line])
            } else if !items.isEmpty, line.leadingSpaceCount > itemIndent {
                items[items.count - 1].append(line)
            } else {
                return nil
            }
        }
        guard !items.isEmpty else { return nil }

        let listItems = items.map { itemLines -> ListItem in
            var text = Self.joinWrappedLines(itemLines)
            if let match = text.firstMatch(of: bulletPattern) {
                text = String(match.text)
            } else if let match = text.firstMatch(of: numberedItemPattern) {
                text = String(match.text)
            }
            return ListItem(blocks: [.paragraph(Paragraph(linker.link(text)))])
        }
        return ListBlock(style: style, items: listItems)
    }

    // MARK: References

    nonisolated(unsafe) private static let referenceStartPattern = #/^\s*\[(?<anchor>[^\]\s]+)\]\s+(?<text>\S.*)$/#

    private static func parseReferences(_ rawBlocks: [RawBlock]) -> [Reference] {
        var references: [Reference] = []
        var currentAnchor: String?
        var currentLines: [String] = []

        func flush() {
            guard let anchor = currentAnchor else { return }
            let text = currentLines.joined(separator: " ").collapsingWhitespace()
            references.append(reference(anchor: anchor, text: text))
            currentAnchor = nil
            currentLines = []
        }

        for block in rawBlocks {
            for line in block.lines {
                if let match = line.firstMatch(of: referenceStartPattern) {
                    flush()
                    currentAnchor = String(match.anchor)
                    currentLines = [String(match.text)]
                } else if currentAnchor != nil {
                    currentLines.append(line.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        flush()
        return references
    }

    private static func reference(anchor: String, text: String) -> Reference {
        var seriesInfo: [(name: String, value: String)] = []
        if let match = text.firstMatch(of: #/\bRFC\s?(\d+)/#) {
            seriesInfo.append((name: "RFC", value: String(match.1)))
        } else if let id = DocumentID(parsing: anchor) {
            seriesInfo.append((name: id.series.rawValue, value: String(id.number)))
        }
        if let match = text.firstMatch(of: #/\bBCP\s?(\d+)/#) {
            seriesInfo.append((name: "BCP", value: String(match.1)))
        }
        if let match = text.firstMatch(of: #/\bSTD\s?(\d+)/#) {
            seriesInfo.append((name: "STD", value: String(match.1)))
        }
        let title = text.firstMatch(of: #/"([^"]+)"/#).map { String($0.1) } ?? ""
        let date = text.firstMatch(of: monthYearPattern).map {
            PublicationDate(year: Int($0.2) ?? 0, month: PublicationDate.month(from: String($0.1)))
        }
        let url = text.firstMatch(of: #/https?:\/\/[^\s>,]+/#).flatMap { URL(string: String($0.output).trimmingTrailingPunctuation()) }
        return Reference(anchor: anchor, title: title, date: date, seriesInfo: seriesInfo, url: url, rawText: text)
    }
}

// MARK: - Inline linking

/// Turns plain prose into inlines with cross references and links.
struct InlineLinker: Sendable {
    var sectionNumbers: Set<String>
    var referenceTargets: [String: CrossReference.Target]

    private struct Candidate {
        var range: Range<String.Index>
        var inline: Inline
    }

    nonisolated(unsafe) private static let sectionOfRFCPattern = #/\bSection\s+(?<section>\d+(?:\.\d+)*)\s+of\s+\[?RFC\s?(?<number>\d+)\]?/#
    nonisolated(unsafe) private static let bracketPattern = #/\[(?<anchor>[A-Za-z0-9][A-Za-z0-9.\-_]*)\]/#
    nonisolated(unsafe) private static let bareRFCPattern = #/(?<bracket>\[?)\bRFC\s?(?<number>\d+)\b/#
    nonisolated(unsafe) private static let sectionPattern = #/\bSections?\s+(?<section>\d+(?:\.\d+)*)\b/#
    nonisolated(unsafe) private static let urlPattern = #/https?:\/\/[^\s<>"]+/#

    func link(_ text: String) -> [Inline] {
        var candidates: [Candidate] = []

        for match in text.matches(of: Self.sectionOfRFCPattern) {
            guard let number = Int(match.number) else { continue }
            candidates.append(Candidate(range: match.range, inline: .crossReference(
                CrossReference(target: .document(.rfc(number), section: String(match.section)), text: String(text[match.range]))
            )))
        }
        for match in text.matches(of: Self.bracketPattern) {
            let anchor = String(match.anchor)
            let target: CrossReference.Target
            if let known = referenceTargets[anchor] {
                target = known
            } else if let id = DocumentID(parsing: anchor), id.series != .rfc || anchor.uppercased().hasPrefix("RFC") {
                target = .document(id, section: nil)
            } else {
                continue
            }
            candidates.append(Candidate(range: match.range, inline: .crossReference(
                CrossReference(target: target, text: String(text[match.range]))
            )))
        }
        for match in text.matches(of: Self.bareRFCPattern) {
            guard match.bracket.isEmpty, let number = Int(match.number) else { continue }
            candidates.append(Candidate(range: match.range, inline: .crossReference(
                CrossReference(target: .document(.rfc(number), section: nil), text: String(text[match.range]))
            )))
        }
        for match in text.matches(of: Self.sectionPattern) where sectionNumbers.contains(String(match.section)) {
            candidates.append(Candidate(range: match.range, inline: .crossReference(
                CrossReference(target: .anchor("section-\(match.section)"), text: String(text[match.range]))
            )))
        }
        for match in text.matches(of: Self.urlPattern) {
            let raw = String(match.output).trimmingTrailingPunctuation()
            guard let url = URL(string: raw) else { continue }
            let end = text.index(match.range.lowerBound, offsetBy: raw.count)
            candidates.append(Candidate(range: match.range.lowerBound..<end, inline: .link(url, [.text(raw)])))
        }

        // Earliest start wins; on ties the longer match wins. Overlaps are dropped.
        candidates.sort {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound > $1.range.upperBound
        }
        var inlines: [Inline] = []
        var cursor = text.startIndex
        for candidate in candidates where candidate.range.lowerBound >= cursor {
            if candidate.range.lowerBound > cursor {
                inlines.append(.text(String(text[cursor..<candidate.range.lowerBound])))
            }
            inlines.append(candidate.inline)
            cursor = candidate.range.upperBound
        }
        if cursor < text.endIndex {
            inlines.append(.text(String(text[cursor...])))
        }
        return inlines
    }
}

// MARK: - String helpers

extension String {
    var leadingSpaceCount: Int {
        var count = 0
        for character in self {
            if character == " " { count += 1 } else { break }
        }
        return count
    }

    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }

    func trimmingTrailingDots() -> String {
        var result = trimmingTrailingWhitespace()
        // Table-of-contents style "Title ....... 7" leaders.
        if let match = result.firstMatch(of: #/\s*\.{3,}\s*\d*$/#) {
            result.removeSubrange(match.range)
        }
        return result
    }

    func trimmingTrailingPunctuation() -> String {
        var result = self
        while let last = result.last, ".,;:)]>\"'".contains(last) { result.removeLast() }
        return result
    }

    func slugified() -> String {
        var result = ""
        var lastWasDash = false
        for scalar in lowercased().unicodeScalars {
            if scalar.properties.isAlphabetic || (scalar.value >= 48 && scalar.value <= 57) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }
}
