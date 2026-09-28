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

    /// Every spelling it is read by: its name, then its long spellings.
    var spellings: [String] { [name] + longSpellings }

    /// Whether this is `current`, the obsolete filter.
    var excludesObsolete: Bool { statuses.isEmpty }

    static let all: [StatusValue] = [
      StatusValue(
        name: "std", longSpellings: ["standard", "standards"],
        statuses: [.internetStandard, .draftStandard, .proposedStandard]),
      StatusValue(name: "bcp", longSpellings: [], statuses: [.bestCurrentPractice]),
      StatusValue(name: "info", longSpellings: ["informational"], statuses: [.informational]),
      StatusValue(name: "exp", longSpellings: ["experimental"], statuses: [.experimental]),
      StatusValue(name: "historic", longSpellings: [], statuses: [.historic]),
      StatusValue(name: "current", longSpellings: [], statuses: []),
    ]

    init(name: String, longSpellings: [String], statuses: Set<PublicationStatus>) {
      self.name = name
      self.longSpellings = longSpellings
      self.statuses = statuses
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
  static func spelling(of stream: Stream) -> String {
    stream.rawValue.lowercased()
  }

  /// The stream a `stream:` value names.
  static func stream(spelled spelling: some StringProtocol) -> Stream? {
    let spelling = spelling.lowercased()
    return Stream.allCases.first { Self.spelling(of: $0) == spelling }
  }

  /// The one value `has:` takes.
  static let xmlValue = "xml"

  // MARK: - Writing a query back out

  /// The canonical form of a parsed query: one qualifier per filter, long spellings,
  /// in a fixed order, then the free text. `parseQuery` reads it back to the same
  /// filters and text.
  public static func format(text: String, filters: SearchFilters) -> String {
    func word(_ qualifier: Qualifier, _ value: String) -> String { "\(qualifier.name):\(value)" }
    var words: [String] = []
    if let group = filters.workingGroup { words.append(word(.workingGroup, group)) }
    words += statusWords(filters.statuses).map { word(.status, $0) }
    if filters.excludeObsolete, let current = StatusValue.all.first(where: \.excludesObsolete) {
      words.append(word(.status, current.name))
    }
    if let author = filters.author { words.append(word(.author, author)) }
    words += Stream.allCases.filter(filters.streams.contains).map {
      word(.stream, spelling(of: $0))
    }
    if let years = filters.yearRange {
      words.append(
        word(
          .year,
          years.lowerBound == years.upperBound
            ? "\(years.lowerBound)" : "\(years.lowerBound)-\(years.upperBound)"))
    }
    if filters.requiresXML { words.append(word(.has, xmlValue)) }
    let text = text.trimmingCharacters(in: .whitespaces)
    if !text.isEmpty { words.append(text) }
    return words.joined(separator: " ")
  }

  /// The `status:` values, in `StatusValue.all` order, whose statuses together make
  /// up `statuses`. `parseQuery` only ever produces unions of these groups.
  private static func statusWords(_ statuses: Set<PublicationStatus>) -> [String] {
    StatusValue.all.compactMap { value in
      value.excludesObsolete || !value.statuses.isSubset(of: statuses) ? nil : value.name
    }
  }

  // MARK: - Completion

  public struct Suggestion: Sendable, Hashable {
    /// The whole query with the word being typed completed.
    public var completion: String
    /// A qualifier `parseQuery` does not know: the word is searched for as text.
    public var isUnknown: Bool
  }

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
      let begun = Qualifier.allCases.filter { qualifier in
        qualifier.spellings.contains { $0.hasPrefix(typed) }
      }
      return offer(begun.map(\.completion))
    }
    let typed = word[word.index(after: colon)...].lowercased()
    guard let qualifier = Qualifier(spelling: word[..<colon]) else {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    let matching: [String] =
      switch qualifier {
      case .workingGroup: workingGroups(in: index).filter { $0.hasPrefix(typed) }
      // A long spelling completes to the short value it means.
      case .status:
        StatusValue.all.filter { $0.spellings.contains { $0.hasPrefix(typed) } }.map(\.name)
      case .stream: Stream.allCases.map(spelling(of:)).filter { $0.hasPrefix(typed) }
      case .has: [xmlValue].filter { $0.hasPrefix(typed) }
      case .author, .year: []
      }
    if matching.isEmpty, !typed.isEmpty, qualifier.isClosed {
      return [Suggestion(completion: query, isUnknown: true)]
    }
    return offer(matching.map { "\(qualifier.name):\($0)" })
  }

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
