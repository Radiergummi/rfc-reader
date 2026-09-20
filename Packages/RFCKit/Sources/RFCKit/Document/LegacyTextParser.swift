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
        let rawLines = removingControlCharacters(text).replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
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

    /// Resolves nroff overstrikes (`T\bT` for bold, `_\bT` for underline) and drops the
    /// NUL padding and escape bytes found in a few dozen 1970s and 1980s RFCs.
    static func removingControlCharacters(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" && $0 != "\r" && $0 != "\u{0C}" }) else {
            return text
        }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(text.unicodeScalars.count)
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\u{08}" {
                guard let previous = result.popLast(), let next = iterator.next() else { continue }
                result.append(next == "_" ? previous : next)
            } else if scalar.value < 0x20, scalar != "\n", scalar != "\t", scalar != "\r", scalar != "\u{0C}" {
                continue
            } else {
                result.append(scalar)
            }
        }
        var output = ""
        output.unicodeScalars.append(contentsOf: result)
        return output
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
        let lines = Self.collapsingDoubleSpacing(Self.depaginate(text))
        let (frontLines, bodyStart) = Self.splitFrontMatter(lines)
        var header = Self.parseFrontMatter(frontLines)
        let bodyIsIndented = Self.bodyIsIndented(lines[bodyStart...])

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

        for index in lines.indices[bodyStart...] {
            switch lines[index] {
            case .pageBreak:
                if current.isEmpty, var last = sections[sections.count - 1].blocks.popLast() {
                    last.followedByPageBreak = true
                    sections[sections.count - 1].blocks.append(last)
                } else {
                    pendingBreak = true
                    flushBlock()
                }
            case .text(let string):
                if string.isBlank {
                    flushBlock()
                } else if let heading = Self.heading(at: index, in: lines, bodyIsIndented: bodyIsIndented, startsBlock: current.isEmpty) {
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

    /// Front matter is the header block (first run of lines), the title (second run, which
    /// may start at column 0 when it fills the line), and anything up to the next heading.
    private static func splitFrontMatter(_ lines: [Line]) -> (front: [String], bodyStart: Int) {
        var front: [String] = []
        var run = 0
        var previousWasBlank = true
        // A few dozen 1970s and 1980s RFCs indent their headings like the body (RFC 775,
        // RFC 1144), so no heading ever arrives. Ending the front matter after the title
        // keeps the prose; swallowing the whole file would leave an empty document.
        var afterTitle: (front: [String], bodyStart: Int)?
        for (offset, line) in lines.enumerated() {
            guard case .text(let string) = line else { continue }
            if string.isBlank {
                front.append("")
                previousWasBlank = true
                continue
            }
            if previousWasBlank { run += 1 }
            previousWasBlank = false
            if run > 2 {
                if afterTitle == nil { afterTitle = (front, offset) }
                // Deliberately laxer than the body's rule: the stand-alone test needs the
                // body's indent, which is not known until this scan has finished. Stopping
                // early only leaves a line in the body that turns out not to be a heading;
                // stopping late would swallow it into the front matter and lose it.
                if string.startsAtColumnZero, heading(from: string) != nil {
                    return (front, offset)
                }
            }
            front.append(string)
        }
        return afterTitle ?? (front, lines.count)
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

        // Title: the next run of non-blank lines, whatever their indentation.
        var titleLines: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.isEmpty {
                if !titleLines.isEmpty { break }
            } else {
                titleLines.append(line.trimmingCharacters(in: .whitespaces))
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

    /// True when the body sits at an indent and headings stand out at column 0, which is
    /// the layout `heading(from:)` assumes. A few hundred legacy RFCs (1142, 1305, 1247,
    /// 1034 and others) set their prose at column 0 as well; there the indent says nothing
    /// and every line would otherwise become an unnumbered heading.
    private static func bodyIsIndented(_ body: ArraySlice<Line>) -> Bool {
        var counts: [Int: Int] = [:]
        for case .text(let string) in body where !string.isBlank {
            // Spaces only: the handful of tab-indented documents set their body at column 0
            // anyway, and counting a tab as an indent would classify them the other way.
            counts[string.leadingSpaceCount, default: 0] += 1
        }
        // A tie keeps the classic layout, which is what the rest of the parser assumes.
        guard let mode = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return true
        }
        return mode > 0
    }

    /// Where a heading is allowed to sit. It starts at column 0, and in a document whose
    /// body starts there too — so that the indent says nothing — it also has to stand alone
    /// between blank lines. `heading(from:)` judges the text; this judges the position.
    private static func heading(at index: Int, in lines: [Line], bodyIsIndented: Bool, startsBlock: Bool) -> HeadingInfo? {
        guard case .text(let string) = lines[index], string.startsAtColumnZero else { return nil }
        guard bodyIsIndented || (startsBlock && isBlankOrEnd(lines, at: index + 1)) else { return nil }
        return heading(from: string)
    }

    private static func isBlankOrEnd(_ lines: [Line], at index: Int) -> Bool {
        guard lines.indices.contains(index) else { return true }
        switch lines[index] {
        case .pageBreak:
            return true
        case .text(let string):
            return string.isBlank
        }
    }

    /// A couple of dozen documents (RFC 817, 813, 888, 827) are typeset double spaced: a
    /// blank line sits between every pair of lines, so no paragraph ever forms and every
    /// line stands alone. Drop those single blanks and keep the wider gaps, which are the
    /// real paragraph breaks. The "as published" view goes through `stripPagination(_:)`
    /// and is not touched.
    private static func collapsingDoubleSpacing(_ lines: [Line]) -> [Line] {
        var content = 0
        var isolated = 0
        for (index, line) in lines.enumerated() {
            guard case .text(let string) = line, !string.isBlank else { continue }
            content += 1
            if isBlankOrEnd(lines, at: index - 1), isBlankOrEnd(lines, at: index + 1) { isolated += 1 }
        }
        guard content > 20, isolated * 5 >= content * 3 else { return lines }

        var result: [Line] = []
        for (index, line) in lines.enumerated() {
            if case .text(let string) = line, string.isBlank,
               !isBlankOrEnd(lines, at: index - 1), !isBlankOrEnd(lines, at: index + 1) {
                continue
            }
            result.append(line)
        }
        return result
    }

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
        // Most pre-1990 RFCs indent the first line of a paragraph and set the rest at the
        // margin (RFC 722, 891, 904), so the block's indent comes from the second line.
        let indent = (lines.count > 1 ? lines[1] : first).leadingSpaceCount
        let firstLineIndent = first.leadingSpaceCount - indent
        guard indent <= 6, (0...8).contains(firstLineIndent) else { return false }
        for (offset, line) in lines.enumerated() {
            if offset > 0, line.leadingSpaceCount != indent { return false }
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

    nonisolated(unsafe) private static let referenceStartPattern = #/^\s*\[(?<anchor>[^\]\s]+)\]\s*(?<text>.*)$/#

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
                    currentLines = match.text.isEmpty ? [] : [String(match.text)]
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
    var isBlank: Bool { allSatisfy(\.isWhitespace) }

    /// A tab indents as surely as a space does: RFC 1142's contents listing is tab-indented
    /// and every entry otherwise matched the numbered-heading pattern.
    var startsAtColumnZero: Bool { first?.isWhitespace == false }

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
