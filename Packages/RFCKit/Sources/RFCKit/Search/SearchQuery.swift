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
    if let group = filters.workingGroup { words.append("wg:\(group)") }
    words += statusWords(filters.statuses).map { "status:\($0)" }
    if filters.excludeObsolete { words.append("status:current") }
    if let author = filters.author { words.append("author:\(author)") }
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
    let head: String
    let word: String
    if let space = query.lastIndex(of: " ") {
      head = String(query[...space])
      word = String(query[query.index(after: space)...])
    } else {
      head = ""
      word = query
    }
    func offer(_ words: [String]) -> [Suggestion] {
      words.map { Suggestion(completion: head + $0, isUnknown: false) }
    }

    guard let colon = word.firstIndex(of: ":") else {
      let typed = word.lowercased()
      let begun = qualifiers.filter { qualifier in
        ([qualifier.name] + qualifier.aliases).contains { $0.hasPrefix(typed) }
      }
      return offer(begun.map { $0.name == "has" ? "has:xml" : "\($0.name):" })
    }
    let key = word[..<colon].lowercased()
    let typed = word[word.index(after: colon)...].lowercased()
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
    return offer(matching.map { "\(qualifier.name):\($0)" })
  }

  /// The long `status:` spellings `parseQuery` also reads, and the value each means.
  private static let statusSpellings: [(String, String)] = [
    ("standard", "std"),
    ("standards", "std"),
    ("informational", "info"),
    ("experimental", "exp"),
  ]

  /// Every working group the index names, lowercased as `parseQuery` matches them,
  /// most documents first. Not one with a space in its name ("NON WORKING GROUP"):
  /// a value ends at a space, so no query can spell it.
  private static func workingGroups(in index: RFCIndex) -> [String] {
    var counts: [String: Int] = [:]
    for rfc in index.rfcs {
      guard let group = rfc.workingGroup?.lowercased(), !group.contains(" ") else { continue }
      counts[group, default: 0] += 1
    }
    return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
  }
}
