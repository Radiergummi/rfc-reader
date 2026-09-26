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
    var number: SearchText
    var title: SearchText
    var titleWords: Set<SearchText>
    var keywords: [SearchText]
    var authors: [SearchText]
    var abstract: SearchText
    var group: SearchText
  }

  private let entries: [Entry]

  public init(index: RFCIndex) {
    self.index = index
    self.entries = index.rfcs.enumerated().map { offset, rfc in
      let title = rfc.title.lowercased()
      let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      return Entry(
        offset: offset,
        number: SearchText(String(rfc.number)),
        title: SearchText(title),
        titleWords: Set(words.map { SearchText(String($0)) }),
        keywords: rfc.keywords.map { SearchText($0.lowercased()) },
        authors: rfc.authors.map { SearchText($0.name.lowercased()) },
        abstract: SearchText(rfc.abstract?.lowercased() ?? ""),
        group: SearchText(rfc.workingGroup?.lowercased() ?? "")
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
        if let stream = Stream.allCases.first(where: {
          $0.rawValue.lowercased() == value.lowercased()
        }) {
          filters.streams.insert(stream)
        }
      case "status", "is":
        switch value.lowercased() {
        case "std", "standard", "standards":
          filters.statuses.formUnion([.internetStandard, .draftStandard, .proposedStandard])
        case "bcp": filters.statuses.insert(.bestCurrentPractice)
        case "info", "informational": filters.statuses.insert(.informational)
        case "exp", "experimental": filters.statuses.insert(.experimental)
        case "historic": filters.statuses.insert(.historic)
        case "current": filters.excludeObsolete = true
        default: words.append(String(token))
        }
      case "year":
        let bounds = value.split(separator: "-").compactMap { Int($0) }
        if bounds.count == 2 {
          filters.yearRange = min(bounds[0], bounds[1])...max(bounds[0], bounds[1])
        } else if bounds.count == 1 {
          filters.yearRange = bounds[0]...bounds[0]
        }
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
    if let id = DocumentID(parsing: trimmed), id.series == .rfc, let exact = index[id.number],
      filters.isEmpty
    {
      return [SearchHit(rfc: exact, score: Int.max)]
    }

    // Converted here rather than inside the loop: a needle allocated per entry
    // would cost 9,842 allocations per term and undo the point of the exercise.
    let needles = terms.map(SearchText.init)
    let lowered = SearchText(trimmed.lowercased())
    var hits: [SearchHit] = []
    for entry in entries {
      let rfc = index.rfcs[entry.offset]
      guard matches(rfc, filters: filters) else { continue }
      if terms.isEmpty {
        hits.append(SearchHit(rfc: rfc, score: rfc.number))
        continue
      }
      if let score = score(entry, rfc: rfc, terms: needles, loweredQuery: lowered) {
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
    if let author = filters.author,
      !rfc.authors.contains(where: { $0.name.lowercased().contains(author) })
    {
      return false
    }
    if let years = filters.yearRange, !years.contains(rfc.date.year) { return false }
    if filters.excludeObsolete, rfc.isObsolete { return false }
    if filters.requiresXML, !rfc.hasXMLSource { return false }
    return true
  }

  /// Every term must match somewhere; where it matches decides the weight.
  private func score(
    _ entry: Entry, rfc: RFCMetadata, terms: [SearchText], loweredQuery: SearchText
  ) -> Int? {
    var total = 0
    for term in terms {
      var best = 0
      if entry.number == term {
        best = max(best, 100)
      } else if entry.number.hasPrefix(term) {
        best = max(best, 40)
      }
      if entry.title == term {
        best = max(best, 90)
      } else if entry.titleWords.contains(term) {
        best = max(best, 60)
      } else if entry.title.contains(term) {
        best = max(best, 45)
      }
      if entry.keywords.contains(term) {
        best = max(best, 50)
      } else if entry.keywords.contains(where: { $0.contains(term) }) {
        best = max(best, 30)
      }
      if entry.group == term { best = max(best, 55) }
      if entry.authors.contains(where: { $0.contains(term) }) { best = max(best, 35) }
      if best == 0, entry.abstract.contains(term) { best = 15 }
      guard best > 0 else { return nil }
      total += best
    }
    if terms.count > 1, entry.title.contains(loweredQuery) { total += 50 }
    if rfc.isObsolete { total -= 10 }
    if rfc.currentStatus.isStandardsTrack || rfc.currentStatus == .bestCurrentPractice {
      total += 5
    }
    return total
  }
}

/// A lowercased field held as UTF-8, so searching it is a byte scan.
///
/// `String.range(of:)` was the whole cost of search. It is a Foundation call with
/// per-call setup and Unicode-correct matching, and the scoring loop makes roughly
/// five of them per entry — the title, each keyword, each author, and the abstract —
/// across all 9,842 entries. Measured against the real index in release, a one-word
/// query cost 96 ms, and a query matching *nothing* cost 93: the work was the
/// scanning, not the hits.
///
/// What this gives up is canonical equivalence: `e` + U+0301 no longer finds `é`
/// spelled as U+00E9. Case is unaffected — both sides are lowercased on the way in —
/// and UTF-8 is self-synchronizing, so since a needle never begins with a
/// continuation byte a match cannot start in the middle of a character.
struct SearchText: Hashable, Sendable {
  private let bytes: [UInt8]

  init(_ string: String) {
    bytes = Array(string.utf8)
  }

  func hasPrefix(_ other: SearchText) -> Bool {
    guard other.bytes.count <= bytes.count else { return false }
    return bytes.withUnsafeBufferPointer { haystack in
      other.bytes.withUnsafeBufferPointer { needle in
        for offset in 0..<needle.count where haystack[offset] != needle[offset] { return false }
        return true
      }
    }
  }

  /// Naive scan, skipping on the first byte. The needle is a search term — a
  /// handful of bytes — so the quadratic worst case needs a haystack that repeats
  /// almost all of the term over and over, which prose is not.
  func contains(_ other: SearchText) -> Bool {
    guard !other.bytes.isEmpty else { return true }
    guard other.bytes.count <= bytes.count else { return false }
    return bytes.withUnsafeBufferPointer { haystack in
      other.bytes.withUnsafeBufferPointer { needle in
        let first = needle[0]
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
          if haystack[start] == first {
            var offset = 1
            while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
            if offset == needle.count { return true }
          }
          start += 1
        }
        return false
      }
    }
  }
}
