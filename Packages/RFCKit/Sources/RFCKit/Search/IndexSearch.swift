import Foundation

/// Filters that can be combined with a free-text query.
public struct SearchFilters: Sendable, Hashable {
    public var statuses: Set<PublicationStatus> = []
    public var streams: Set<Stream> = []
    public var workingGroup: String?
    public var author: String?
    public var yearRange: ClosedRange<Int>?
    public var excludeObsolete = false
    public var requiresXML = false

    public init() {}

    public var isEmpty: Bool {
        statuses.isEmpty && streams.isEmpty && workingGroup == nil && author == nil
            && yearRange == nil && !excludeObsolete && !requiresXML
    }
}

public struct SearchHit: Sendable, Identifiable {
    public var rfc: RFCMetadata
    public var score: Int
    public var id: DocumentID { rfc.id }
}

/// In-memory search over index metadata: number, title, keywords, authors, abstract.
///
/// Ten thousand entries scan in well under a frame, so there is no need for an index
/// until full-text search over document bodies arrives (that is SQLite FTS territory).
public struct IndexSearch: Sendable {
    public let index: RFCIndex

    /// Lowercased copies of the searchable fields, built once so type-ahead stays fast.
    private struct Entry: Sendable {
        var offset: Int
        var number: String
        var title: String
        var titleWords: Set<String>
        var keywords: [String]
        var authors: [String]
        var abstract: String
        var group: String
    }

    private let entries: [Entry]

    public init(index: RFCIndex) {
        self.index = index
        self.entries = index.rfcs.enumerated().map { offset, rfc in
            let title = rfc.title.lowercased()
            return Entry(
                offset: offset,
                number: String(rfc.number),
                title: title,
                titleWords: Set(title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)),
                keywords: rfc.keywords.map { $0.lowercased() },
                authors: rfc.authors.map { $0.name.lowercased() },
                abstract: rfc.abstract?.lowercased() ?? "",
                group: rfc.workingGroup?.lowercased() ?? ""
            )
        }
    }

    /// Parses `wg:httpbis status:std author:fielding year:2020-2022 tls` into filters plus free text.
    public static func parseQuery(_ query: String) -> (text: String, filters: SearchFilters) {
        var filters = SearchFilters()
        var words: [String] = []
        for token in query.split(separator: " ") {
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                words.append(String(token))
                continue
            }
            let key = parts[0].lowercased()
            let value = String(parts[1])
            switch key {
            case "wg", "group":
                filters.workingGroup = value.lowercased()
            case "author", "by":
                filters.author = value.lowercased()
            case "stream":
                if let stream = Stream.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
                    filters.streams.insert(stream)
                }
            case "status", "is":
                switch value.lowercased() {
                case "std", "standard", "standards": filters.statuses.formUnion([.internetStandard, .draftStandard, .proposedStandard])
                case "bcp": filters.statuses.insert(.bestCurrentPractice)
                case "info", "informational": filters.statuses.insert(.informational)
                case "exp", "experimental": filters.statuses.insert(.experimental)
                case "historic": filters.statuses.insert(.historic)
                case "current": filters.excludeObsolete = true
                default: words.append(String(token))
                }
            case "year":
                let bounds = value.split(separator: "-").compactMap { Int($0) }
                if bounds.count == 2 { filters.yearRange = min(bounds[0], bounds[1])...max(bounds[0], bounds[1]) }
                else if bounds.count == 1 { filters.yearRange = bounds[0]...bounds[0] }
            case "has" where value.lowercased() == "xml":
                filters.requiresXML = true
            default:
                words.append(String(token))
            }
        }
        return (words.joined(separator: " "), filters)
    }

    public func search(_ query: String, limit: Int = 100) -> [SearchHit] {
        let (text, filters) = Self.parseQuery(query)
        return search(text: text, filters: filters, limit: limit)
    }

    public func search(text: String, filters: SearchFilters, limit: Int = 100) -> [SearchHit] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let terms = trimmed.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }

        // A query that is just a document number goes straight there.
        if let id = DocumentID(parsing: trimmed), id.series == .rfc, let exact = index[id.number], filters.isEmpty {
            return [SearchHit(rfc: exact, score: Int.max)]
        }

        let lowered = trimmed.lowercased()
        var hits: [SearchHit] = []
        for entry in entries {
            let rfc = index.rfcs[entry.offset]
            guard matches(rfc, filters: filters) else { continue }
            if terms.isEmpty {
                hits.append(SearchHit(rfc: rfc, score: rfc.number))
                continue
            }
            if let score = score(entry, rfc: rfc, terms: terms, loweredQuery: lowered) {
                hits.append(SearchHit(rfc: rfc, score: score))
            }
        }
        hits.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.rfc.number > $1.rfc.number
        }
        return Array(hits.prefix(limit))
    }

    private func matches(_ rfc: RFCMetadata, filters: SearchFilters) -> Bool {
        if !filters.statuses.isEmpty, !filters.statuses.contains(rfc.currentStatus) { return false }
        if !filters.streams.isEmpty, !filters.streams.contains(rfc.stream) { return false }
        if let group = filters.workingGroup, rfc.workingGroup?.lowercased() != group { return false }
        if let author = filters.author, !rfc.authors.contains(where: { $0.name.lowercased().contains(author) }) { return false }
        if let years = filters.yearRange, !years.contains(rfc.date.year) { return false }
        if filters.excludeObsolete, rfc.isObsolete { return false }
        if filters.requiresXML, !rfc.hasXMLSource { return false }
        return true
    }

    /// Every term must match somewhere; where it matches decides the weight.
    private func score(_ entry: Entry, rfc: RFCMetadata, terms: [String], loweredQuery: String) -> Int? {
        var total = 0
        for term in terms {
            var best = 0
            if entry.number == term { best = max(best, 100) }
            else if entry.number.hasPrefix(term) { best = max(best, 40) }
            if entry.title == term { best = max(best, 90) }
            else if entry.titleWords.contains(term) { best = max(best, 60) }
            else if entry.title.fastContains(term) { best = max(best, 45) }
            if entry.keywords.contains(term) { best = max(best, 50) }
            else if entry.keywords.contains(where: { $0.fastContains(term) }) { best = max(best, 30) }
            if entry.group == term { best = max(best, 55) }
            if entry.authors.contains(where: { $0.fastContains(term) }) { best = max(best, 35) }
            if best == 0, entry.abstract.fastContains(term) { best = 15 }
            guard best > 0 else { return nil }
            total += best
        }
        if terms.count > 1, entry.title.fastContains(loweredQuery) { total += 50 }
        if rfc.isObsolete { total -= 10 }
        if rfc.currentStatus.isStandardsTrack || rfc.currentStatus == .bestCurrentPractice { total += 5 }
        return total
    }
}

private extension String {
    /// Substring search lives in one place so the strategy (currently Foundation's) can be
    /// swapped for a byte-level scan or an FTS index without touching the scoring code.
    func fastContains(_ other: String) -> Bool {
        range(of: other) != nil
    }
}
