import Foundation

/// The search field's filter vocabulary, made visible (#21).
///
/// `IndexSearch.parseQuery` has always understood `wg:httpbis status:std
/// author:fielding year:2020-2022`; nothing said so. This is the other half of that
/// grammar: a parsed query written back out, so a saved collection or a token
/// removed from the field is exactly the query on screen, and completion for the
/// qualifier being typed.
public enum SearchQuery {
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
    var words: [String] = []
    if let group = filters.workingGroup { words.append("wg:\(written(group))") }
    words += statusWords(filters.statuses).map { "status:\($0)" }
    if filters.excludeObsolete { words.append("status:current") }
    if let author = filters.author { words.append("author:\(written(author))") }
    words += Stream.allCases.filter(filters.streams.contains).map {
      "stream:\($0.rawValue.lowercased())"
    }
    if let years = filters.yearRange {
      words.append(
        years.lowerBound == years.upperBound
          ? "year:\(years.lowerBound)" : "year:\(years.lowerBound)-\(years.upperBound)")
    }
    if filters.requiresXML { words.append("has:xml") }
    let text = text.trimmingCharacters(in: .whitespaces)
    if !text.isEmpty { words.append(text) }
    return words.joined(separator: " ")
  }

  /// The `status:` values, in `statusValues` order, whose statuses together make up
  /// `statuses`. `parseQuery` only ever produces unions of these groups.
  private static func statusWords(_ statuses: Set<PublicationStatus>) -> [String] {
    statusValues.compactMap { value, group in
      group.isEmpty || !group.isSubset(of: statuses) ? nil : value
    }
  }

  /// What each `status:` value stands for, as `parseQuery` reads it. `current` is not
  /// a status but the obsolete filter, and has no set.
  private static let statusValues: [(String, Set<PublicationStatus>)] = [
    ("std", [.internetStandard, .draftStandard, .proposedStandard]),
    ("bcp", [.bestCurrentPractice]),
    ("info", [.informational]),
    ("exp", [.experimental]),
    ("historic", [.historic]),
    ("current", []),
  ]

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
  }

  /// The qualifiers, in the order they are offered, with the aliases each is also
  /// typed as.
  private static let qualifiers: [(name: String, aliases: [String])] = [
    ("wg", ["group"]),
    ("status", ["is"]),
    ("author", ["by"]),
    ("stream", []),
    ("year", []),
    ("has", []),
  ]

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
      let begun = qualifiers.filter { qualifier in
        ([qualifier.name] + qualifier.aliases).contains { $0.hasPrefix(typed) }
      }
      return offer(begun.map { $0.name == "has" ? "has:xml" : "\($0.name):" })
    }
    let key = parts.key.lowercased()
    let typed = unquoted(parts.value).lowercased()
    guard let qualifier = qualifiers.first(where: { $0.name == key || $0.aliases.contains(key) })
    else {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    let values: [String] =
      switch qualifier.name {
      case "wg": workingGroups(in: index)
      case "status": statusValues.map(\.0)
      case "stream": Stream.allCases.map { $0.rawValue.lowercased() }
      case "has": ["xml"]
      default: []
      }
    var matching = values.filter { $0.hasPrefix(typed) }
    if qualifier.name == "status" {
      for (spelling, value) in statusSpellings
      where spelling.hasPrefix(typed) && !matching.contains(value) {
        matching.append(value)
      }
    }
    // A value outside a closed vocabulary is a typo `parseQuery` would search as
    // text, or drop. Working groups are not closed: any name filters.
    if matching.isEmpty, !typed.isEmpty, ["status", "stream", "has"].contains(qualifier.name) {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    return offer(matching.map { "\(qualifier.name):\(written($0))" })
  }

  /// The long `status:` spellings `parseQuery` also reads, and the value each means.
  private static let statusSpellings: [(String, String)] = [
    ("standard", "std"),
    ("standards", "std"),
    ("informational", "info"),
    ("experimental", "exp"),
  ]

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
