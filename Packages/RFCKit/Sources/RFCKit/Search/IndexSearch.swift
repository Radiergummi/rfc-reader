import Foundation

/// Filters that can be combined with a free-text query.
public struct SearchFilters: Sendable, Hashable {
  public var statuses: Set<PublicationStatus> = []
  public var streams: Set<PublicationStream> = []
  /// Lowercased when set, and nil when set empty, as an empty value is no filter. It
  /// keeps its diacritics, as it is shown, and is folded where it is matched
  /// (`SearchText.folded`), as the fields it is matched against are.
  public var workingGroup: String? {
    didSet { workingGroup = Self.normalized(workingGroup) }
  }
  /// Lowercased when set, and nil when set empty, as `workingGroup` is.
  public var author: String? {
    didSet { author = Self.normalized(author) }
  }
  public var yearRange: ClosedRange<Int>?
  public var excludeObsolete = false
  public var requiresXML = false

  public init() {}

  public var isEmpty: Bool {
    statuses.isEmpty && streams.isEmpty && workingGroup == nil && author == nil
      && yearRange == nil && !excludeObsolete && !requiresXML
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value.lowercased()
  }
}

public struct SearchHit: Sendable, Identifiable {
  public var rfc: RFCMetadata
  public var score: Int
  public var id: DocumentID { rfc.id }
}

/// In-memory search over index metadata: number, title, keywords, authors, abstract.
///
/// A scan of every entry per query, with no index: the "Search" benchmarks of
/// `make benchmark` measure it over the real index. An index for the metadata waits
/// for full-text search over document bodies, which will hold both (#37, #605).
public struct IndexSearch: Sendable {
  public let index: RFCIndex

  /// Folded copies of the searchable fields (`SearchText.folded`), built once so
  /// type-ahead stays fast.
  private struct Entry: Sendable {
    var offset: Int
    var number: SearchText
    var title: SearchText
    var titleWords: Set<SearchText>
    var keywords: [SearchText]
    var authors: [SearchText]
    var authorNames: [AuthorName]
    var abstract: SearchText
    var group: SearchText
  }

  private let entries: [Entry]

  public init(index: RFCIndex) {
    self.index = index
    self.entries = index.rfcs.enumerated().map { offset, rfc in
      let title = SearchText.folded(rfc.title)
      let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      return Entry(
        offset: offset,
        number: SearchText(alreadyFolded: String(rfc.number)),
        title: SearchText(alreadyFolded: title),
        titleWords: Set(words.map { SearchText(alreadyFolded: String($0)) }),
        keywords: rfc.keywords.map { SearchText(folding: $0) },
        authors: rfc.authors.map { SearchText(folding: $0.name) },
        authorNames: rfc.authors.map { AuthorName($0.name) },
        abstract: SearchText(folding: rfc.abstract ?? ""),
        group: SearchText(folding: rfc.workingGroup ?? "")
      )
    }
  }

  /// Parses `wg:httpbis status:std author:fielding year:2020-2022 tls` into filters plus free text.
  ///
  /// A value with spaces is quoted, `author:"Roy Fielding"`, and loses its quotes. A
  /// quoted phrase of free text keeps them, so `search(text:filters:)` reads it as one
  /// term (#177).
  public static func parseQuery(_ query: String) -> SearchQuery.Parsed {
    var filters = SearchFilters()
    var words: [String] = []
    for token in SearchQuery.words(in: query) {
      guard let written = SearchQuery.qualifier(in: token) else {
        words.append(token)
        continue
      }
      let value = SearchQuery.unquoted(written.value).trimmingCharacters(in: .whitespaces)
      // `wg:"` is still being typed; like `wg:`, it is free text until it has a value.
      guard !value.isEmpty else {
        words.append(token)
        continue
      }
      guard let qualifier = SearchQuery.Qualifier(spelling: written.key) else {
        words.append(token)
        continue
      }
      switch qualifier {
      case .workingGroup:
        filters.workingGroup = value
      case .author:
        filters.author = value
      case .stream:
        if let stream = SearchQuery.stream(spelled: value) {
          filters.streams.insert(stream)
        }
      case .status:
        if let status = SearchQuery.StatusValue(spelling: value) {
          if status.excludesObsolete {
            filters.excludeObsolete = true
          } else {
            filters.statuses.formUnion(status.statuses)
          }
        } else {
          words.append(token)
        }
      case .year:
        let bounds = value.split(separator: "-").compactMap { Int($0) }
        if bounds.count == 2 {
          filters.yearRange = min(bounds[0], bounds[1])...max(bounds[0], bounds[1])
        } else if bounds.count == 1 {
          filters.yearRange = bounds[0]...bounds[0]
        }
      case .has:
        if value.lowercased() == SearchQuery.xmlValue {
          filters.requiresXML = true
        } else {
          words.append(token)
        }
      }
    }
    return SearchQuery.Parsed(text: words.joined(separator: " "), filters: filters)
  }

  public func search(_ query: String, limit: Int = 100) -> [SearchHit] {
    let parsed = Self.parseQuery(query)
    return search(text: parsed.text, filters: parsed.filters, limit: limit)
  }

  public func search(text: String, filters: SearchFilters, limit: Int = 100) -> [SearchHit] {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    // A quoted phrase is one term, so it has to match as it is written. Every term is
    // folded as the fields are, so `kuhlewind` finds "Kühlewind" (#425).
    let terms = SearchQuery.words(in: SearchText.folded(trimmed)).map(SearchQuery.unquoted)
      .filter { !$0.isEmpty }

    if filters.isEmpty, let number = Self.number(in: trimmed) {
      return numberHits(number, limit: limit)
    }

    // Converted here rather than inside the loop: a needle allocated per entry
    // would cost 9,842 allocations per term and undo the point of the exercise.
    let needles = terms.map(SearchText.init(alreadyFolded:))
    // The query as the title bonus compares it, without the quotes of its phrases.
    let foldedQuery = SearchText(alreadyFolded: terms.joined(separator: " "))
    let filter = PreparedFilters(filters)
    var hits: [SearchHit] = []
    for entry in entries {
      let rfc = index.rfcs[entry.offset]
      guard filter.matches(entry, rfc: rfc) else { continue }
      if terms.isEmpty {
        hits.append(SearchHit(rfc: rfc, score: rfc.number))
        continue
      }
      if let score = score(entry, rfc: rfc, terms: needles, foldedQuery: foldedQuery) {
        hits.append(SearchHit(rfc: rfc, score: score))
      }
    }
    hits.sort {
      if $0.score != $1.score { return $0.score > $1.score }
      return $0.rfc.number > $1.rfc.number
    }
    return Array(hits.prefix(limit))
  }

  /// The RFC number a query is, if it is nothing else: `991`, `RFC 991`. Such a
  /// query is a number, not words — the document it names, then every number it
  /// begins, newest first, since `991` is as often the start of 9910 as it is RFC 991.
  /// Public so the palette can drop an earlier number's hits on the keystroke,
  /// knowing without a search which of them still match.
  public static func number(in query: String) -> Int? {
    let parsed = parseQuery(query)
    let trimmed = parsed.text.trimmingCharacters(in: .whitespaces)
    guard parsed.filters.isEmpty, let id = DocumentID(parsing: trimmed), id.series == .rfc else {
      return nil
    }
    return id.number
  }

  /// Whether a number query matches the document: an RFC whose number begins with it.
  public static func matches(_ id: DocumentID, number: Int) -> Bool {
    id.series == .rfc && String(id.number).hasPrefix(String(number))
  }

  private func numberHits(_ number: Int, limit: Int) -> [SearchHit] {
    var hits = index[number].map { [SearchHit(rfc: $0, score: Int.max)] } ?? []
    let longer = index.rfcs
      .filter { $0.number != number && Self.matches($0.id, number: number) }
      .sorted { $0.number > $1.number }
    hits += longer.map { SearchHit(rfc: $0, score: $0.number) }
    return Array(hits.prefix(limit))
  }

  /// The filters with their text made into needles once per query, matched against
  /// an entry's prepared fields (#151). Lowercasing every author and working group
  /// on every query was the whole cost of an `author:` search: 6.6 ms in release
  /// over the full index, twice a free-text query's.
  private struct PreparedFilters {
    let filters: SearchFilters
    let group: SearchText?
    let author: AuthorQuery?

    init(_ filters: SearchFilters) {
      self.filters = filters
      group = filters.workingGroup.map { SearchText(folding: $0) }
      author = filters.author.map(AuthorQuery.init)
    }

    func matches(_ entry: Entry, rfc: RFCMetadata) -> Bool {
      if !filters.statuses.isEmpty, !filters.statuses.contains(rfc.currentStatus) { return false }
      if !filters.streams.isEmpty, !filters.streams.contains(rfc.stream) { return false }
      if let years = filters.yearRange, !years.contains(rfc.date.year) { return false }
      if filters.excludeObsolete, rfc.isObsolete { return false }
      if filters.requiresXML, !rfc.hasXMLSource { return false }
      // The text filters come last, so the cheap checks above spare them their scan.
      if let group, entry.group != group { return false }
      if let author, !entry.authorNames.contains(where: { $0.matches(author) }) { return false }
      return true
    }
  }

  /// Every term must match somewhere; where it matches decides the weight.
  private func score(
    _ entry: Entry, rfc: RFCMetadata, terms: [SearchText], foldedQuery: SearchText
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
    if terms.count > 1, entry.title.contains(foldedQuery) { total += 50 }
    if rfc.isObsolete { total -= 10 }
    if rfc.currentStatus.isStandardsTrack || rfc.currentStatus == .bestCurrentPractice {
      total += 5
    }
    return total
  }
}

/// A folded field held as UTF-8, so searching it is a byte scan.
///
/// `String.range(of:)` was the whole cost of search. It is a Foundation call with
/// per-call setup and Unicode-correct matching, and the scoring loop makes roughly
/// five of them per entry — the title, each keyword, each author, and the abstract —
/// across all 9,842 entries. Measured against the real index in release, a one-word
/// query cost 96 ms, and a query matching *nothing* cost 93: the work was the
/// scanning, not the hits.
///
/// What a byte scan gives up is canonical equivalence: `e` + U+0301 is not `é` spelled
/// as U+00E9. Both sides are folded on the way in (`SearchText.folded`), which
/// composes them first, so the two spellings of an accented letter end as the same
/// bytes. UTF-8 is self-synchronizing, so since a needle never begins with a
/// continuation byte a match cannot start in the middle of a character.
struct SearchText: Hashable, Sendable {
  private let bytes: [UInt8]

  /// `string` as it is: text already folded, such as a term split from a folded
  /// query, or digits.
  init(alreadyFolded string: String) {
    bytes = Array(string.utf8)
  }

  /// `text` folded (`folded`), as every field and needle a search compares is.
  init(folding text: String) {
    self.init(alreadyFolded: Self.folded(text))
  }

  func hasPrefix(_ other: SearchText) -> Bool {
    guard other.bytes.count <= bytes.count else { return false }
    let haystack = bytes.span
    let needle = other.bytes.span
    for offset in needle.indices where haystack[offset] != needle[offset] { return false }
    return true
  }

  /// Naive scan, skipping on the first byte. The needle is a search term — a
  /// handful of bytes — so the quadratic worst case needs a haystack that repeats
  /// almost all of the term over and over, which prose is not.
  func contains(_ other: SearchText) -> Bool {
    guard !other.bytes.isEmpty else { return true }
    guard other.bytes.count <= bytes.count else { return false }
    let haystack = bytes.span
    let needle = other.bytes.span
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

/// An author as the `author:` filter matches it: the initials and the surname of the
/// name the index holds, "R. Fielding", folded to lowercase without diacritics.
///
/// The index holds given names as initials, so a query's given name can only be
/// matched by its first letter: `Roy Fielding` finds "R. Fielding", and so does
/// `Rob Fielding`.
struct AuthorName: Sendable {
  let initials: Set<Character>
  let surname: SearchText

  /// The leading words that are initials, "J.K." or "SN", are the given names; the
  /// rest is the surname, "Le Faucheur" or "St. Johns". A name that is one word, or
  /// an organization's ("RFC Editor", "IAB and IESG"), is all surname.
  init(_ name: String) {
    let words = name.split(separator: " ")
    let given = words.dropLast().prefix(while: Self.isInitials)
    initials = Set(given.flatMap { word in SearchText.folded(String(word)).filter(\.isLetter) })
    surname = SearchText(folding: words.dropFirst(given.count).joined(separator: " "))
  }

  /// Initials are capitals, and either carry a dot ("R.", "J.K.", "L-E.", "JP.") or
  /// are at most two letters without one ("SN"). "St." has a small letter, and
  /// "RFC" or "IAB" is three capitals without a dot, so both are surname.
  private static func isInitials(_ word: Substring) -> Bool {
    let letters = word.filter(\.isLetter)
    guard !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return false }
    return word.contains(".") || letters.count <= 2
  }

  /// Each word of the query matches the surname, or is a given name or an initial
  /// that fits one of the author's initials and comes before the surname. The
  /// surname is matched in part, as the query is still being typed.
  func matches(_ query: AuthorQuery) -> Bool {
    query.surnames.indices.contains { split in
      surname.contains(query.surnames[split])
        && query.initials[..<split].allSatisfy(initials.contains)
    }
  }
}

/// An `author:` value prepared once per search for `AuthorName.matches`.
struct AuthorQuery: Sendable {
  /// The first letter of each word of the value, as a given name or an initial.
  let initials: [Character]
  /// For each word of the value, it and the words after it: the surname, if the
  /// words before it are given names.
  let surnames: [SearchText]

  init(_ value: String) {
    let words = SearchText.folded(value).split(separator: " ")
    initials = words.compactMap(\.first)
    surnames = words.indices.map { SearchText(alreadyFolded: words[$0...].joined(separator: " ")) }
  }
}

extension SearchText {
  /// `text` lowercased and without diacritics, so `kuhlewind` finds "Kühlewind"
  /// however its ü is spelled: what every field the search prepares, and every term
  /// and filter it matches against them, is compared as (#425), and what `wg:`
  /// completion and tokens compare names as. Composed first (NFC), so a letter and its
  /// marks typed apart, `u` and U+0308 or `か` and U+3099, are the one letter the other
  /// spelling is, then folded, which drops a mark Foundation counts as a diacritic. A
  /// letter that is not a base letter and a mark, `ß`, `ø`, `æ`, is left as it is.
  /// ASCII, most of the index, is only lowercased: there is nothing else to do to it.
  static func folded(_ text: String) -> String {
    if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
    return text.precomposedStringWithCanonicalMapping.lowercased()
      .folding(options: .diacriticInsensitive, locale: nil)
  }
}
