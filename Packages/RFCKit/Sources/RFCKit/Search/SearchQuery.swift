import Foundation

/// The search field's filter vocabulary, made visible (#21).
///
/// `IndexSearch.parseQuery` has always understood `wg:httpbis status:std
/// author:fielding year:2020-2022`; nothing said so. This is the other half of that
/// grammar: a parsed query written back out, so a saved collection or a token
/// removed from the field is exactly the query on screen, and completion for the
/// qualifier being typed.
public enum SearchQuery {
  // MARK: - The vocabulary

  /// A filter the search field understands. The one table of the grammar:
  /// `IndexSearch.parseQuery` reads a qualifier by any of its spellings, completion
  /// offers it by its name, and `format` writes it back by its name.
  enum Qualifier: CaseIterable, Sendable {
    case workingGroup, status, author, stream, year, after, before, published, has
    /// `is:`: the reader's own data, and, as an alias of `status:`, a status.
    case readerData
    /// `in:`: a document or a collection.
    case scope
    case sort

    /// The long spelling, written back and offered.
    var name: String {
      switch self {
      case .workingGroup: "wg"
      case .status: "status"
      case .author: "author"
      case .stream: "stream"
      case .year: "year"
      case .after: "after"
      case .before: "before"
      case .published: "published"
      case .has: "has"
      case .readerData: "is"
      case .scope: "in"
      case .sort: "sort"
      }
    }

    /// Every spelling it is read by: its name, then its aliases.
    var spellings: [String] {
      switch self {
      case .workingGroup: [name, "group"]
      case .author: [name, "by"]
      default: [name]
      }
    }

    /// Whether it is a union of values, so a comma separates them and each is a
    /// term of its own.
    var isUnion: Bool {
      switch self {
      case .workingGroup, .status, .stream, .readerData, .scope: true
      case .author, .year, .after, .before, .published, .has, .sort: false
      }
    }

    init?(spelling: some StringProtocol) {
      let spelling = spelling.lowercased()
      guard let qualifier = Self.allCases.first(where: { $0.spellings.contains(spelling) })
      else { return nil }
      self = qualifier
    }

    /// What completion offers for the word that begins it. `has:` has one value,
    /// so it is offered whole.
    var completion: String {
      self == .has ? "\(name):\(SearchQuery.xmlValue)" : "\(name):"
    }

    /// Whether its values are a closed vocabulary, so one outside it is a typo that
    /// `parseQuery` searches as text or drops. Working groups are not closed: any
    /// name filters.
    var isClosed: Bool {
      switch self {
      case .status, .stream, .has, .readerData, .sort: true
      case .workingGroup, .author, .year, .after, .before, .published, .scope: false
      }
    }
  }

  /// A `status:` value, with the long spellings it is also read by, and the statuses
  /// it stands for. `current` is not a status but the obsolete filter, and has none.
  struct StatusValue: Sendable {
    let name: String
    let longSpellings: [String]
    let statuses: Set<PublicationStatus>
    /// What its term is labeled.
    let label: String

    /// Every spelling it is read by: its name, then its long spellings.
    var spellings: [String] { [name] + longSpellings }

    /// Whether this is `current`, the obsolete filter.
    var excludesObsolete: Bool { statuses.isEmpty }

    static let all: [StatusValue] = [
      StatusValue(
        name: "std", longSpellings: ["standard", "standards"],
        statuses: [.internetStandard, .draftStandard, .proposedStandard],
        label: "Standards Track"),
      StatusValue(
        name: "internet-standard", longSpellings: ["full"], status: .internetStandard),
      StatusValue(name: "bcp", longSpellings: [], status: .bestCurrentPractice),
      StatusValue(name: "info", longSpellings: ["informational"], status: .informational),
      StatusValue(name: "exp", longSpellings: ["experimental"], status: .experimental),
      StatusValue(name: "historic", longSpellings: [], status: .historic),
      StatusValue(name: "current", longSpellings: [], statuses: [], label: "Not Obsoleted"),
    ]

    /// A value standing for one status, labeled with that status's name.
    init(name: String, longSpellings: [String], status: PublicationStatus) {
      self.init(
        name: name, longSpellings: longSpellings, statuses: [status], label: status.displayName)
    }

    init(name: String, longSpellings: [String], statuses: Set<PublicationStatus>, label: String) {
      self.name = name
      self.longSpellings = longSpellings
      self.statuses = statuses
      self.label = label
    }

    init?(spelling: some StringProtocol) {
      let spelling = spelling.lowercased()
      guard let value = Self.all.first(where: { $0.spellings.contains(spelling) }) else {
        return nil
      }
      self = value
    }
  }

  /// The `stream:` spelling of a stream.
  static func spelling(of stream: PublicationStream) -> String {
    stream.rawValue.lowercased()
  }

  /// The stream a `stream:` value names.
  static func stream(spelled spelling: some StringProtocol) -> PublicationStream? {
    let spelling = spelling.lowercased()
    return PublicationStream.allCases.first { Self.spelling(of: $0) == spelling }
  }

  /// The one value `has:` takes.
  static let xmlValue = "xml"

  /// An `after:` or `before:` value: `2023`, or `2023-06`.
  static func month(spelled spelling: String) -> PublicationDate? {
    let parts = spelling.split(separator: "-", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), parts[0].count == 4, let year = Int(parts[0]) else {
      return nil
    }
    guard parts.count == 2 else { return PublicationDate(year: year) }
    guard let month = Int(parts[1]), (1...12).contains(month) else { return nil }
    return PublicationDate(year: year, month: month)
  }

  /// How `after:` and `before:` write a year or a month.
  static func spelling(of month: PublicationDate) -> String {
    guard let number = month.month else { return "\(month.year)" }
    return "\(month.year)-" + (number < 10 ? "0\(number)" : "\(number)")
  }

  /// A `published:` value, `<90d`: within that many days.
  static func days(spelled spelling: String) -> Int? {
    guard spelling.hasPrefix("<"), spelling.hasSuffix("d"),
      let days = Int(spelling.dropFirst().dropLast()), days > 0
    else { return nil }
    return days
  }

  /// How `in:` writes a scope: a document by its file stem, `rfc9110` or `bcp14`, and
  /// a collection by its name.
  static func spelling(of scope: SearchFilters.Scope) -> String {
    switch scope {
    case .document(let id): id.fileStem
    case .collection(let name): written(name)
    }
  }

  /// A query as `IndexSearch.parseQuery` reads it: the filters its qualifiers name,
  /// the terms it could not read, and the free text left over.
  public struct Parsed: Sendable, Hashable {
    public var text: String
    public var filters: SearchFilters
    /// The words naming a qualifier or a value this version doesn't know, as written.
    public var unknown: [UnknownSearchTerm]

    public init(text: String, filters: SearchFilters, unknown: [UnknownSearchTerm] = []) {
      self.text = text
      self.filters = filters
      self.unknown = unknown
    }
  }

  /// The terms of `query` this version can't read, and then each word naming a
  /// working group `index` doesn't, as written: a group the index dropped since the
  /// query was saved.
  public static func unknownTerms(in query: String, index: RFCIndex) -> [UnknownSearchTerm] {
    let parsed = IndexSearch.parseQuery(query)
    // Every list asks, so the index is read only for a query that names a group.
    guard !parsed.filters.workingGroups.isEmpty else { return parsed.unknown }
    let known = knownWorkingGroups(in: index)
    // Folded, as `knownWorkingGroups(in:)` are.
    func namesKnown(_ filters: SearchFilters) -> Bool {
      Set(filters.workingGroups.map(SearchText.folded)).isSubset(of: known)
    }
    guard !namesKnown(parsed.filters) else { return parsed.unknown }
    let missing = words(in: query).filter { word in
      !namesKnown(IndexSearch.parseQuery(word).filters)
    }
    return parsed.unknown + missing.map { UnknownSearchTerm(word: $0, reason: .workingGroup) }
  }

  // MARK: - Writing a query back out

  /// The canonical form of a parsed query; see `format(text:filters:unknown:)`.
  public static func format(_ query: Parsed) -> String {
    format(text: query.text, filters: query.filters, unknown: query.unknown)
  }

  /// The canonical form of a parsed query: one qualifier per filter, long spellings,
  /// in a fixed order, then the unknown terms as they were written, then the free
  /// text. `parseQuery` reads it back to the same filters, unknown terms and text.
  public static func format(
    text: String, filters: SearchFilters, unknown: [UnknownSearchTerm] = []
  ) -> String {
    var words = terms(of: filters).map(\.word) + unknown.map(\.word)
    let text = text.trimmingCharacters(in: .whitespaces)
    if !text.isEmpty { words.append(text) }
    return words.joined(separator: " ")
  }

  // MARK: - Terms

  /// One active filter: a chip under the Mac's search field, a token in the iOS one.
  public struct Term: Sendable, Hashable, Identifiable {
    /// The filter as a word of the query, in the canonical form.
    public var word: String
    /// The filter named for a reader rather than in the query's syntax.
    public var label: String

    public var id: String { word }
  }

  /// The terms of `filters`: one per word of the canonical form, in its order.
  public static func terms(of filters: SearchFilters) -> [Term] {
    func term(_ qualifier: Qualifier, _ value: String, label: String) -> Term {
      Term(word: "\(qualifier.name):\(value)", label: label)
    }
    var terms: [Term] = filters.workingGroups.sorted().map { group in
      term(.workingGroup, written(group), label: "WG: \(group)")
    }
    // The `status:` values whose statuses together make up the filter's, in
    // `StatusValue.all` order: `parseQuery` only ever produces unions of them. One
    // whose statuses an earlier one wrote is not written again: Internet Standard is
    // on the standards track.
    var covered: Set<PublicationStatus> = []
    for value in StatusValue.all
    where !value.excludesObsolete && value.statuses.isSubset(of: filters.statuses)
      && !value.statuses.isSubset(of: covered)
    {
      covered.formUnion(value.statuses)
      terms.append(term(.status, value.name, label: value.label))
    }
    if filters.excludeObsolete, let current = StatusValue.all.first(where: \.excludesObsolete) {
      terms.append(term(.status, current.name, label: current.label))
    }
    if let author = filters.author {
      terms.append(term(.author, written(author), label: "Author: \(author)"))
    }
    terms += PublicationStream.allCases.filter(filters.streams.contains).map {
      term(.stream, spelling(of: $0), label: "Stream: \($0.displayName)")
    }
    if let years = filters.yearRange {
      terms.append(
        years.lowerBound == years.upperBound
          ? term(.year, "\(years.lowerBound)", label: "Year: \(years.lowerBound)")
          : term(
            .year, "\(years.lowerBound)-\(years.upperBound)",
            label: "Year: \(years.lowerBound)–\(years.upperBound)"))
    }
    if let after = filters.publishedAfter {
      terms.append(term(.after, spelling(of: after), label: "After: \(after.formatted)"))
    }
    if let before = filters.publishedBefore {
      terms.append(term(.before, spelling(of: before), label: "Before: \(before.formatted)"))
    }
    if let days = filters.publishedWithinDays {
      let span = days == 1 ? "Day" : "\(days) Days"
      terms.append(term(.published, "<\(days)d", label: "Published: Last \(span)"))
    }
    if filters.requiresXML { terms.append(term(.has, xmlValue, label: "Has XML")) }
    terms += SearchFilters.ReaderData.allCases.filter(filters.readerData.contains).map {
      term(.readerData, $0.rawValue, label: label(of: $0))
    }
    terms += filters.scopes.sorted(by: isOrdered).map { scope in
      term(.scope, spelling(of: scope), label: "In: \(label(of: scope))")
    }
    if let sort = filters.sort {
      terms.append(term(.sort, sort.rawValue, label: "Sort: \(label(of: sort))"))
    }
    return terms
  }

  private static func label(of data: SearchFilters.ReaderData) -> String {
    switch data {
    case .bookmarked: "Bookmarked"
    case .read: "Read"
    case .offline: "Available Offline"
    }
  }

  private static func label(of scope: SearchFilters.Scope) -> String {
    switch scope {
    case .document(let id): id.displayName
    case .collection(let name): name
    }
  }

  private static func label(of sort: SearchFilters.Sort) -> String {
    switch sort {
    case .newest: "Newest First"
    case .oldest: "Oldest First"
    case .lastRead: "Last Read"
    }
  }

  /// Documents first, in order, then collections by name.
  private static func isOrdered(_ lhs: SearchFilters.Scope, _ rhs: SearchFilters.Scope) -> Bool {
    switch (lhs, rhs) {
    case (.document(let lhs), .document(let rhs)): lhs < rhs
    case (.document, .collection): true
    case (.collection, .document): false
    case (.collection(let lhs), .collection(let rhs)): lhs < rhs
    }
  }

  /// `query` without `term`: a chip removed. The words that set its filter are taken
  /// out, and every other word is left as the reader typed it, a word `parseQuery`
  /// ignores included.
  ///
  /// An author, a date, `has:` and a sort hold one value, the last word's, so every
  /// word naming one goes, or an earlier one would take over. A working group, a
  /// status, a stream, the reader's data and `in:` are unions, so only the words
  /// naming this one go.
  public static func removing(_ term: Term, from query: String) -> String {
    let removed = qualifier(in: term.word).flatMap { Qualifier(spelling: $0.key) }
    let kept = words(in: query).flatMap { word -> [String] in
      let parsed = IndexSearch.parseQuery(word)
      guard parsed.text.isEmpty, let removed else { return [word] }
      // What the word sets, written as terms are: `is:bcp` sets `status:bcp`.
      let set = terms(of: parsed.filters)
      guard removed.isUnion else {
        return set.contains { qualifier(in: $0.word)?.key == removed.name[...] } ? [] : [word]
      }
      // A word naming several values of a union loses only this one: `wg:quic,tls`
      // without `wg:quic` is `wg:tls`.
      let left = set.filter { !removes(term, $0) }
      return left.count < set.count ? left.map(\.word) : [word]
    }
    // The space the reader typed last stays, so the next keystroke begins a word.
    let trailingSpace = wordBeingTyped(in: query) == nil && !kept.isEmpty ? " " : ""
    return kept.joined(separator: " ") + trailingSpace
  }

  // MARK: - Tokens

  /// A query as the iOS search field shows it: its finished filters as tokens, and
  /// the rest as the text being edited.
  public struct Tokenized: Sendable, Hashable {
    public var terms: [Term]
    public var text: String
  }

  /// `query` split into tokens and text.
  ///
  /// A filter becomes a token once the reader has finished typing it, so `wg:t` is
  /// not a token before `wg:tls` can be typed. The word at the end is still being
  /// typed until a space follows it; a word typed in front of the text is finished
  /// only by what it says, so a working group becomes a token only once it is one of
  /// `workingGroups`, as a status does only once it is a status. A word that filters
  /// nothing stays text, as `parseQuery` searches it as text. The space the reader
  /// has just typed stays in the text, or the field would take it back.
  ///
  /// - Parameter workingGroups: The working groups a token may name, folded, as
  ///   `knownWorkingGroups(in:)` gives them.
  public static func tokenized(_ query: String, workingGroups: Set<String>) -> Tokenized {
    let words = words(in: query)
    let typing = wordBeingTyped(in: query) != nil
    var filtering: [String] = []
    var text: [String] = []
    for (offset, word) in words.enumerated() {
      let parsed = IndexSearch.parseQuery(word)
      let isTyped = typing && offset == words.count - 1
      let namesKnownGroup = Set(parsed.filters.workingGroups.map(SearchText.folded))
        .isSubset(of: workingGroups)
      if !isTyped, parsed.text.isEmpty, !parsed.filters.isEmpty, namesKnownGroup {
        filtering.append(word)
      } else {
        text.append(word)
      }
    }
    let filters = IndexSearch.parseQuery(filtering.joined(separator: " ")).filters
    let trailingSpace = !typing && !text.isEmpty ? " " : ""
    return Tokenized(
      terms: terms(of: filters), text: text.joined(separator: " ") + trailingSpace)
  }

  /// `query` with the text the iOS field shows replaced by `text`, as typed, and its
  /// tokens kept.
  public static func replacingText(
    in query: String, with text: String, workingGroups: Set<String>
  ) -> String {
    joined(terms: tokenized(query, workingGroups: workingGroups).terms, text: text)
  }

  /// `query` with its tokens replaced by `terms`, a token removed, and its text kept.
  public static func replacingTerms(
    in query: String, with terms: [Term], workingGroups: Set<String>
  ) -> String {
    joined(terms: terms, text: tokenized(query, workingGroups: workingGroups).text)
  }

  /// Tokens and text put back together into the one search text: each token's word
  /// with a space after it, so it reads back as finished, then the text as typed.
  static func joined(terms: [Term], text: String) -> String {
    terms.map { "\($0.word) " }.joined() + text
  }

  // MARK: - Words

  /// The characters that open or close a quoted run: the straight quote, and the
  /// typographic ones Smart Punctuation, on by default on iOS, types for it: “ and ”,
  /// or „ and “ on a German keyboard; and the guillemets « » and ‹ › a French or
  /// Swiss keyboard quotes with.
  static let quotes: Set<Character> = [
    "\"", "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}", "\u{2039}", "\u{203A}",
  ]

  /// The words of `query`, split at whitespace outside quotes, each as typed: a tab or
  /// a line break, as a query pasted across a wrapped line has, separates words as a
  /// space does (#852). A quoted run is one word with its quotes and its whitespace
  /// (`author:"Roy Fielding"`, `"key words"`), and an unclosed one runs to the end of
  /// the query, which is still being typed (#177).
  ///
  /// A quote opens a run only at the start of a word or right after `key:`. Anywhere
  /// else it is a character of the word: in `3.5" floppy status:bcp` it is an inch
  /// mark, and `status:bcp` is still a filter.
  public static func words(in query: String) -> [String] {
    var words: [String] = []
    var word = ""
    var quoted = false
    for character in query {
      if character.isWhitespace, !quoted {
        if !word.isEmpty { words.append(word) }
        word = ""
        continue
      }
      // Any quote opens or closes, whatever its direction: Smart Punctuation picks
      // the direction from the character before it, so after a colon it types ”,
      // and “ closes a quote on a German keyboard.
      if quotes.contains(character), quoted || opensQuote(after: word) {
        quoted.toggle()
      }
      word.append(character)
    }
    if !word.isEmpty { words.append(word) }
    return words
  }

  /// The last word of `query` while the reader is still typing it, or nil once
  /// whitespace outside quotes follows it and a new word begins. It is the last word
  /// `words(in:)` finds, so an open quote keeps its spaces: in `by:"Roy s` it is the
  /// whole value, not `s`.
  static func wordBeingTyped(in query: String) -> String? {
    words(in: query).last.flatMap { query.hasSuffix($0) ? $0 : nil }
  }

  /// Whether a quote typed after `word`, the part of a word before it, opens a quoted
  /// run: at the start of the word, or right after its key's colon.
  private static func opensQuote(after word: String) -> Bool {
    word.isEmpty
      || (word.last == ":" && word.firstIndex(of: ":") == word.index(before: word.endIndex))
  }

  /// `word` read as a qualifier: the key before its first colon and the value after
  /// it, or nil when it has no colon, or its colon is inside a quoted phrase and so
  /// the phrase's.
  static func qualifier(in word: String) -> (key: Substring, value: Substring)? {
    guard let colon = word.firstIndex(of: ":") else { return nil }
    let key = word[..<colon]
    guard !key.contains(where: quotes.contains) else { return nil }
    return (key, word[word.index(after: colon)...])
  }

  /// `word` without the quotes of its quoted run: a quoted value's text, or a
  /// phrase's. The run's opening quote is the word's first character, and the next
  /// quote closes it; a quote anywhere else is the word's own, as `words(in:)` reads
  /// it. Each run of whitespace inside the quotes is one space, so a phrase or a
  /// name pasted across a wrapped line reads as it would typed on one (#852).
  static func unquoted(_ word: some StringProtocol) -> String {
    guard let first = word.first, quotes.contains(first) else { return String(word) }
    var text = String(word.dropFirst())
    if let closing = text.firstIndex(where: quotes.contains) {
      text.remove(at: closing)
    }
    return text.replacing(#/\s+/#, with: " ")
  }

  /// A qualifier's value as written back: in quotes when it has a space, or it would
  /// read back as a shorter value and a word of free text.
  /// A comma would split it into two values of a union, so a value with one is
  /// quoted too.
  private static func written(_ value: String) -> String {
    value.contains(" ") || value.contains(",") ? "\"\(value)\"" : value
  }

  /// Whether a word with a colon this version doesn't know as a qualifier reads as
  /// one from another version: a word of lowercase letters, as `format` writes every
  /// qualifier, then a value with no other colon and no slash after it.
  /// `urn:ietf:params`, `http://…`, `::1`, `10:30` and `Cache-Control:no-store` are
  /// text, and so is a word beginning with a URI scheme RFCs are full of, `mailto:…`.
  static func looksLikeQualifier(_ word: (key: Substring, value: Substring)) -> Bool {
    !word.key.isEmpty && word.key.allSatisfy { $0.isLowercase || $0 == "-" }
      && !uriSchemes.contains(word.key.lowercased())
      && !word.value.contains(":") && !word.value.contains("/")
  }

  /// The URI schemes whose words are searched for as text, never read as a qualifier
  /// of another version: no qualifier will ever be named like one.
  private static let uriSchemes: Set<String> = [
    "urn", "mailto", "sip", "sips", "tel", "data", "doi", "tag",
  ]

  /// Whether removing `removed` takes `term` with it: the same term, or a status the
  /// removed one's statuses include, which `terms(of:)` gave no chip of its own.
  /// Removing the standards track takes `status:internet-standard` with it.
  private static func removes(_ removed: Term, _ term: Term) -> Bool {
    guard removed != term else { return true }
    guard let removedStatus = statusValue(of: removed), let status = statusValue(of: term),
      !status.excludesObsolete
    else { return false }
    return status.statuses.isSubset(of: removedStatus.statuses)
  }

  /// The `status:` value a term names, or nil for another qualifier's.
  private static func statusValue(of term: Term) -> StatusValue? {
    guard let written = qualifier(in: term.word), written.key == Qualifier.status.name[...]
    else { return nil }
    return StatusValue(spelling: String(written.value))
  }

  // MARK: - Completion

  public struct Suggestion: Sendable, Hashable {
    /// The whole query with the word being typed completed.
    public var completion: String
    /// A qualifier `parseQuery` does not know: the word is searched for as text.
    public var isUnknown: Bool

    /// The word completed: what the suggestion list shows.
    public var word: String { SearchQuery.words(in: completion).last ?? "" }

    /// The field's text once the suggestion is taken. A completed filter ends with a
    /// space, so the next word begins, and on iOS the filter becomes a token; a
    /// qualifier waits for its value.
    public var accepted: String {
      isUnknown || word.hasSuffix(":") ? completion : completion + " "
    }
  }

  /// Completions for the last word of `query`, the one being typed.
  ///
  /// A plain word is offered the qualifiers it begins, by name or by alias (`by`
  /// offers `author:`); a qualifier is offered its values — working groups from
  /// `index`, statuses and streams from their vocabulary, `has:xml`. Authors and
  /// years are free-form, and get nothing.
  public static func suggestions(for query: String, in index: RFCIndex) -> [Suggestion] {
    let word = wordBeingTyped(in: query) ?? ""
    let head = String(query.dropLast(word.count))
    func offer(_ words: [String]) -> [Suggestion] {
      words.map { Suggestion(completion: head + $0, isUnknown: false) }
    }

    guard let parts = qualifier(in: word) else {
      let typed = word.lowercased()
      let begun = Qualifier.allCases.filter { qualifier in
        qualifier.spellings.contains { $0.hasPrefix(typed) }
      }
      return offer(begun.map(\.completion))
    }
    // Folded as the names are, so `wg:naiv` is offered a group the index spells
    // with an accent.
    let typed = SearchText.folded(unquoted(parts.value))
    guard let qualifier = Qualifier(spelling: parts.key) else {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    let matching: [String] =
      switch qualifier {
      case .workingGroup: workingGroups(in: index).filter { $0.hasPrefix(typed) }
      // A long spelling completes to the short value it means.
      case .status:
        StatusValue.all.filter { $0.spellings.contains { $0.hasPrefix(typed) } }.map(\.name)
      case .stream: PublicationStream.allCases.map(spelling(of:)).filter { $0.hasPrefix(typed) }
      case .has: [xmlValue].filter { $0.hasPrefix(typed) }
      // The reader's data, then the statuses `is:` is also an alias for.
      case .readerData:
        SearchFilters.ReaderData.allCases.map(\.rawValue).filter { $0.hasPrefix(typed) }
          + StatusValue.all.filter { $0.spellings.contains { $0.hasPrefix(typed) } }.map(\.name)
      case .sort: SearchFilters.Sort.allCases.map(\.rawValue).filter { $0.hasPrefix(typed) }
      case .author, .year, .after, .before, .published, .scope: []
      }
    if matching.isEmpty, !typed.isEmpty, qualifier.isClosed {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    return offer(
      matching.map { value in
        // A status is written as `status:`, whichever qualifier it was typed after.
        let name = StatusValue(spelling: value) != nil ? Qualifier.status.name : qualifier.name
        return "\(name):\(written(value))"
      })
  }

  /// The completions a search field shows as the reader types: `suggestions(for:in:)`,
  /// only once a word has been begun. A list over the results at every space, after
  /// every filter taken as a token, or on clearing the field would hide them while
  /// the reader types.
  public static func suggestionsWhileTyping(for query: String, in index: RFCIndex) -> [Suggestion] {
    guard wordBeingTyped(in: query) != nil else { return [] }
    return suggestions(for: query, in: index)
  }

  /// Every working group the index names, folded as the search matches them,
  /// most documents first. One with a space in its name is offered in quotes, as
  /// `written` writes it.
  ///
  /// "NON WORKING GROUP" comes last, whatever its count: it is where the index files
  /// individual submissions, not a group, and it has more documents than any group.
  private static func workingGroups(in index: RFCIndex) -> [String] {
    var counts: [String: Int] = [:]
    for rfc in index.rfcs {
      guard let group = rfc.workingGroup.map(SearchText.folded) else { continue }
      counts[group, default: 0] += 1
    }
    let groups = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
      .map(\.key)
    return groups.filter { $0 != individualSubmissions }
      + groups.filter { $0 == individualSubmissions }
  }

  /// Every working group the index names, folded as the search matches them:
  /// the ones a `wg:` token may name in `tokenized(_:workingGroups:)`.
  public static func knownWorkingGroups(in index: RFCIndex) -> Set<String> {
    Set(index.rfcs.compactMap { $0.workingGroup.map(SearchText.folded) })
  }

  /// The working group the index files individual submissions under.
  private static let individualSubmissions = "non working group"
}

extension SearchFilters {
  /// Whether these ask for what the index doesn't hold: the reader's data, or a
  /// collection to search in.
  public var asksReader: Bool {
    !readerData.isEmpty || !collectionNames.isEmpty
  }

  /// The documents `in:` names, in no order.
  public var documentScopes: [DocumentID] {
    scopes.compactMap { scope in
      guard case .document(let id) = scope else { return nil }
      return id
    }
  }

  /// The names of the collections `in:` names, in order.
  public var collectionNames: [String] {
    scopes.compactMap { scope in
      guard case .collection(let name) = scope else { return nil }
      return name
    }
    .sorted()
  }

  /// Adds what a `status:` value stands for: its statuses, or for `current` the
  /// obsolete filter.
  mutating func insert(_ status: SearchQuery.StatusValue) {
    if status.excludesObsolete {
      excludeObsolete = true
    } else {
      statuses.formUnion(status.statuses)
    }
  }
}

/// A word of a query that names something this version, or this index, or this
/// library doesn't know. It filters nothing and is searched for as nothing: the
/// query finds nothing and says why, and keeps the word, so a query from a newer
/// version works once this one learns it.
public struct UnknownSearchTerm: Sendable, Hashable {
  public enum Reason: Sendable, Hashable {
    /// A qualifier this version doesn't know: `released:2024`.
    case qualifier
    /// A value the qualifier doesn't take: `status:nonsense`, `after:June`.
    case value
    /// A working group the index doesn't name.
    case workingGroup
    /// A collection `in:` names that the library doesn't hold.
    case collection
  }

  /// The word as written in the query.
  public var word: String
  public var reason: Reason

  public init(word: String, reason: Reason) {
    self.word = word
    self.reason = reason
  }
}
