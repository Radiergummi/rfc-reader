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
    case workingGroup, status, author, stream, year, has

    /// The long spelling, written back and offered.
    var name: String {
      switch self {
      case .workingGroup: "wg"
      case .status: "status"
      case .author: "author"
      case .stream: "stream"
      case .year: "year"
      case .has: "has"
      }
    }

    /// Every spelling it is read by: its name, then its aliases.
    var spellings: [String] {
      switch self {
      case .workingGroup: [name, "group"]
      case .status: [name, "is"]
      case .author: [name, "by"]
      case .stream, .year, .has: [name]
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
      case .status, .stream, .has: true
      case .workingGroup, .author, .year: false
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
      StatusValue(name: "bcp", longSpellings: [], statuses: [.bestCurrentPractice]),
      StatusValue(name: "info", longSpellings: ["informational"], statuses: [.informational]),
      StatusValue(name: "exp", longSpellings: ["experimental"], statuses: [.experimental]),
      StatusValue(name: "historic", longSpellings: [], statuses: [.historic]),
      StatusValue(name: "current", longSpellings: [], statuses: [], label: "Not Obsoleted"),
    ]

    /// A value standing for one status, labeled with that status's name.
    init(name: String, longSpellings: [String], statuses: Set<PublicationStatus>) {
      self.init(
        name: name, longSpellings: longSpellings, statuses: statuses,
        label: statuses.first?.displayName ?? name)
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

  /// A query as `IndexSearch.parseQuery` reads it: the filters its qualifiers name,
  /// and the free text left over.
  public struct Parsed: Sendable, Hashable {
    public var text: String
    public var filters: SearchFilters

    public init(text: String, filters: SearchFilters) {
      self.text = text
      self.filters = filters
    }
  }

  // MARK: - Writing a query back out

  /// The canonical form of a parsed query; see `format(text:filters:)`.
  public static func format(_ query: Parsed) -> String {
    format(text: query.text, filters: query.filters)
  }

  /// The canonical form of a parsed query: one qualifier per filter, long spellings,
  /// in a fixed order, then the free text. `parseQuery` reads it back to the same
  /// filters and text.
  public static func format(text: String, filters: SearchFilters) -> String {
    var words = terms(of: filters).map(\.word)
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
    var terms: [Term] = []
    if let group = filters.workingGroup {
      terms.append(term(.workingGroup, written(group), label: "WG: \(group)"))
    }
    // The `status:` values whose statuses together make up the filter's, in
    // `StatusValue.all` order: `parseQuery` only ever produces unions of them.
    terms += StatusValue.all.filter { value in
      !value.excludesObsolete && value.statuses.isSubset(of: filters.statuses)
    }
    .map { term(.status, $0.name, label: $0.label) }
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
    if filters.requiresXML { terms.append(term(.has, xmlValue, label: "Has XML")) }
    return terms
  }

  /// `query` without `term`, in the canonical form: a chip removed.
  public static func removing(_ term: Term, from query: String) -> String {
    let parsed = IndexSearch.parseQuery(query)
    let kept = terms(of: parsed.filters).filter { $0 != term }
    let filters = IndexSearch.parseQuery(kept.map(\.word).joined(separator: " ")).filters
    return format(text: parsed.text, filters: filters)
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
  /// not a token before `wg:tls` can be typed. A word that filters nothing stays
  /// text, as `parseQuery` searches it as text. The space the reader has just typed
  /// stays in the text, or the field would take it back.
  public static func tokenized(_ query: String) -> Tokenized {
    let words = words(in: query)
    // The last word is still being typed unless a space outside quotes follows it,
    // as `suggestions(for:in:)` reads it.
    let typing = words.last.map(query.hasSuffix) ?? false
    var filtering: [String] = []
    var text: [String] = []
    for (offset, word) in words.enumerated() {
      let parsed = IndexSearch.parseQuery(word)
      let isTyped = typing && offset == words.count - 1
      if !isTyped, parsed.text.isEmpty, !parsed.filters.isEmpty {
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

  /// Tokens and text put back together into the one search text: each token's word
  /// with a space after it, so it reads back as finished, then the text as typed.
  public static func joined(terms: [Term], text: String) -> String {
    terms.map { "\($0.word) " }.joined() + text
  }

  // MARK: - Words

  /// The characters that open or close a quoted run: the straight quote, and the
  /// typographic ones Smart Punctuation, on by default on iOS, types for it: “ and ”,
  /// or „ and “ on a German keyboard.
  static let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}"]

  /// The words of `query`, split at spaces outside quotes, each as typed. A quoted run
  /// is one word with its quotes (`author:"Roy Fielding"`, `"key words"`), and an
  /// unclosed one runs to the end of the query, which is still being typed (#177).
  ///
  /// A quote opens a run only at the start of a word or right after `key:`. Anywhere
  /// else it is a character of the word: in `3.5" floppy status:bcp` it is an inch
  /// mark, and `status:bcp` is still a filter.
  static func words(in query: String) -> [String] {
    var words: [String] = []
    var word = ""
    var quoted = false
    for character in query {
      if character == " ", !quoted {
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
  /// it.
  static func unquoted(_ word: some StringProtocol) -> String {
    guard let first = word.first, quotes.contains(first) else { return String(word) }
    var text = String(word.dropFirst())
    if let closing = text.firstIndex(where: quotes.contains) {
      text.remove(at: closing)
    }
    return text
  }

  /// A qualifier's value as written back: in quotes when it has a space, or it would
  /// read back as a shorter value and a word of free text.
  private static func written(_ value: String) -> String {
    value.contains(" ") ? "\"\(value)\"" : value
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
    // The word being typed is the last one `words(in:)` finds, so an open quote
    // keeps its spaces: in `by:"Roy s` it is the whole value, not `s`. A query that
    // does not end with it ends with a space outside quotes, and a new word begins.
    let last = words(in: query).last ?? ""
    let word = query.hasSuffix(last) ? last : ""
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
    let typed = unquoted(parts.value).lowercased()
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
      case .author, .year: []
      }
    if matching.isEmpty, !typed.isEmpty, qualifier.isClosed {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    return offer(matching.map { "\(qualifier.name):\(written($0))" })
  }

  /// The completions a search field shows as the reader types: `suggestions(for:in:)`,
  /// except for a word just begun after a space. A list over the results at every
  /// space would hide them while the reader types; an empty field is where the
  /// vocabulary is learned, and is offered all of it.
  public static func suggestionsWhileTyping(for query: String, in index: RFCIndex) -> [Suggestion]
  {
    // A space inside an open quote is the value's, and the word is still being typed.
    let typing = words(in: query).last.map(query.hasSuffix) ?? query.isEmpty
    guard typing else { return [] }
    return suggestions(for: query, in: index)
  }

  /// Every working group the index names, lowercased as `parseQuery` matches them,
  /// most documents first. One with a space in its name is offered in quotes, as
  /// `written` writes it.
  ///
  /// "NON WORKING GROUP" comes last, whatever its count: it is where the index files
  /// individual submissions, not a group, and it has more documents than any group.
  private static func workingGroups(in index: RFCIndex) -> [String] {
    var counts: [String: Int] = [:]
    for rfc in index.rfcs {
      guard let group = rfc.workingGroup?.lowercased() else { continue }
      counts[group, default: 0] += 1
    }
    let groups = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
      .map(\.key)
    return groups.filter { $0 != individualSubmissions }
      + groups.filter { $0 == individualSubmissions }
  }

  /// The working group the index files individual submissions under.
  private static let individualSubmissions = "non working group"
}
