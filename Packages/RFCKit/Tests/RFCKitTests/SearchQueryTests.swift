import Testing

@testable import RFCKit

/// The search field's filter vocabulary, made visible (#21): a parsed query written
/// back out in its canonical form, and completion for the qualifier being typed.
@Suite("Search query")
struct SearchQueryTests {
  // MARK: - Round trip

  /// Everything `parseQuery` understands comes back out as a query it reads the same
  /// way — so a saved collection, or a token removed from the field, is exactly the
  /// query that was on screen.
  @Test(arguments: [
    "tls",
    "wg:httpbis",
    "group:QUIC cache",
    "status:std",
    "is:bcp status:info",
    "status:exp status:historic",
    "status:current",
    "author:fielding",
    "by:Nottingham semantics",
    "stream:ietf stream:IRTF",
    "year:2020-2022",
    "year:2022-2020",
    "year:1997",
    "has:xml",
    "wg:httpbis status:std author:fielding year:2020-2022 has:xml status:current HTTP caching",
    #"author:"Roy Fielding" semantics"#,
    #""key words" status:bcp"#,
    #"wg:"NON WORKING GROUP" cache"#,
    #"author:"" cache"#,
  ])
  func `a formatted query parses back to the same filters`(query: String) {
    let parsed = IndexSearch.parseQuery(query)
    #expect(IndexSearch.parseQuery(SearchQuery.format(parsed)) == parsed)
  }

  /// The canonical form: long spellings, lowercased values, one qualifier per
  /// filter in a fixed order, and the free text last.
  @Test func `the canonical form is the one written back`() {
    let parsed = IndexSearch.parseQuery(
      "cache by:Fielding is:standard group:HTTPBIS year:2022-2020")
    #expect(
      SearchQuery.format(parsed) == "wg:httpbis status:std author:fielding year:2020-2022 cache")
  }

  /// A value with a space in it is written back in quotes, or it would read back as a
  /// shorter value and a word of free text.
  @Test func `a value with a space is written back in quotes`() {
    let parsed = IndexSearch.parseQuery("author:\u{201C}Roy Fielding\u{201D}")
    #expect(
      SearchQuery.format(text: parsed.text, filters: parsed.filters) == #"author:"roy fielding""#)
  }

  // MARK: - One vocabulary

  /// Parsing and completion read the same table, so every spelling of every
  /// qualifier filters rather than searching as text, and completion offers its
  /// long name.
  @Test(arguments: SearchQuery.Qualifier.allCases)
  func `every spelling of a qualifier is parsed and completed`(
    qualifier: SearchQuery.Qualifier
  ) throws {
    for spelling in qualifier.spellings {
      #expect(try completions(spelling) == [qualifier.completion])
      let parsed = IndexSearch.parseQuery("\(spelling):\(Self.value(for: qualifier))")
      #expect(parsed.text.isEmpty, "\(spelling): searched as text")
      #expect(!parsed.filters.isEmpty, "\(spelling): set no filter")
    }
  }

  /// A value each qualifier takes.
  private static func value(for qualifier: SearchQuery.Qualifier) -> String {
    switch qualifier {
    case .workingGroup: "httpbis"
    case .status: "std"
    case .author: "fielding"
    case .stream: "ietf"
    case .year: "2020"
    case .after: "2023-06"
    case .before: "2024"
    case .published: "<90d"
    case .has: "xml"
    case .readerData: "bookmarked"
    case .scope: "rfc9110"
    case .sort: "newest"
    }
  }

  /// Every spelling of every `status:` value filters, and completes to its value.
  @Test func `every status spelling is parsed and completed`() throws {
    for value in SearchQuery.StatusValue.all {
      for spelling in value.spellings {
        #expect(IndexSearch.parseQuery("status:\(spelling)").text.isEmpty, "\(spelling)")
        #expect(try completions("status:\(spelling)") == ["status:\(value.name)"])
      }
    }
  }

  @Test func `an empty query formats as nothing`() {
    #expect(SearchQuery.format(text: "", filters: SearchFilters()) == "")
  }

  // MARK: - Completion

  private func completions(_ query: String) throws -> [String] {
    SearchQuery.suggestions(for: query, in: try Fixtures.sampleIndex()).map(\.completion)
  }

  @Test func `a word being typed is offered the qualifiers it starts`() throws {
    #expect(try completions("cache st") == ["cache status:", "cache stream:"])
    #expect(try completions("w") == ["wg:"])
  }

  /// `parseQuery` reads `by:` and `group:` as well; a reader who types one is
  /// offered the qualifier it stands for, by its long name.
  @Test func `a word that begins an alias is offered its qualifier`() throws {
    #expect(try completions("cache by") == ["cache author:"])
    #expect(try completions("gro") == ["wg:"])
  }

  /// `is:` takes the reader's data, and is also an alias of `status:`: it is offered
  /// as itself, and a status typed after it completes to `status:`.
  @Test func `is completes to the reader's data and to statuses`() throws {
    #expect(try completions("is") == ["is:"])
    #expect(
      try completions("is:") == [
        "is:bookmarked", "is:read", "is:offline", "status:std", "status:internet-standard",
        "status:bcp", "status:info", "status:exp", "status:historic", "status:current",
      ])
    #expect(try completions("is:b") == ["is:bookmarked", "status:bcp"])
  }

  @Test func `an empty last word is offered every qualifier`() throws {
    #expect(
      try completions("cache ")
        == [
          "cache wg:", "cache status:", "cache author:", "cache stream:", "cache year:",
          "cache after:", "cache before:", "cache published:", "cache has:xml", "cache is:",
          "cache in:", "cache sort:",
        ])
  }

  @Test func `a working group is completed from the index`() throws {
    #expect(
      try completions("wg:") == ["wg:httpbis", "wg:quic", "wg:tls", #"wg:"non working group""#])
    #expect(try completions("wg:q") == ["wg:quic"])
    #expect(try completions("group:HT") == ["wg:httpbis"])
  }

  /// "NON WORKING GROUP" is where the index files individual submissions, not a
  /// group: it has more documents than any group here, and is offered after them all.
  @Test func `the non-working-group bucket is offered last`() throws {
    #expect(try completions("wg:").last == #"wg:"non working group""#)
  }

  /// "NON WORKING GROUP" names documents in the index; only a quoted value can
  /// spell it, so completion writes one.
  @Test func `a working group with a space in its name is offered in quotes`() throws {
    #expect(try completions("wg:").contains(#"wg:"non working group""#))
    #expect(try completions("cache wg:no") == [#"cache wg:"non working group""#])
    #expect(try completions(#"wg:"non w"#) == [#"wg:"non working group""#])
    let completed = try #require(try completions("wg:no").first)
    #expect(IndexSearch.parseQuery(completed).filters.workingGroups == ["non working group"])
  }

  @Test func `statuses and streams are completed from their vocabulary`() throws {
    #expect(
      try completions("status:") == [
        "status:std", "status:internet-standard", "status:bcp", "status:info", "status:exp",
        "status:historic", "status:current",
      ])
    #expect(try completions("is:e") == ["status:exp"])
    #expect(
      try completions("stream:i") == [
        "stream:ietf", "stream:irtf", "stream:iab", "stream:independent",
      ])
  }

  /// Inside an open quote the word being typed is the quoted value, not what follows
  /// its last space.
  @Test func `a quoted value being typed is completed as one word`() throws {
    #expect(try completions(#"cache by:"Roy s"#) == [])
    #expect(try completions(#"cache by:"Roy "#) == [], "a space inside the quote is the value's")
    #expect(try completions(#"cache wg:"http"#) == ["cache wg:httpbis"])
  }

  /// A colon inside a quoted phrase is the phrase's, as `parseQuery` reads it, so the
  /// phrase is not an unknown qualifier.
  @Test(arguments: [#"cache "note: see"#, #""urn:ietf""#])
  func `a quoted phrase with a colon is not marked as unknown`(query: String) throws {
    let suggestions = SearchQuery.suggestions(for: query, in: try Fixtures.sampleIndex())
    #expect(!suggestions.contains { $0.isUnknown })
  }

  @Test func `a free-form value is offered nothing`() throws {
    #expect(try completions("author:fie").isEmpty)
    #expect(try completions("year:20").isEmpty)
  }

  /// A known qualifier with a value outside its vocabulary is as much a typo as an
  /// unknown qualifier: `parseQuery` searches `status:stnd` as text, and ignores
  /// `stream:ieft` altogether.
  @Test(arguments: ["status:stnd", "has:pdf", "stream:ieft"])
  func `a value the qualifier does not know is marked as unknown`(word: String) throws {
    let suggestions = SearchQuery.suggestions(for: "cache \(word)", in: try Fixtures.sampleIndex())
    #expect(suggestions == [SearchQuery.Suggestion(completion: "cache \(word)", isUnknown: true)])
  }

  /// `parseQuery` takes the long spellings as well; completion offers the short one
  /// they mean rather than nothing.
  @Test func `a long status spelling completes to its short one`() throws {
    #expect(try completions("status:standard") == ["status:std"])
    #expect(try completions("is:informational") == ["status:info"])
    #expect(try completions("status:experimental") == ["status:exp"])
  }

  /// Still searched for as text, as `parseQuery` does; the suggestion says the
  /// qualifier means nothing, so a typo is not silently a word.
  @Test func `an unknown qualifier is marked as unknown`() throws {
    let suggestions = SearchQuery.suggestions(
      for: "cache color:red", in: try Fixtures.sampleIndex())
    #expect(suggestions.map(\.isUnknown) == [true])
    #expect(suggestions.first?.completion == "cache color:red")
  }
}

/// The active filters as the search field shows them (#21): chips under the Mac's
/// field, tokens in the iOS one.
@Suite("Search query terms")
struct SearchQueryTermTests {
  /// The working groups a `wg:` token may name: those of the sample index.
  private let workingGroups: Set<String>

  init() throws {
    workingGroups = SearchQuery.knownWorkingGroups(in: try Fixtures.sampleIndex())
  }

  private func terms(_ query: String) -> [SearchQuery.Term] {
    SearchQuery.terms(of: IndexSearch.parseQuery(query).filters)
  }

  private func tokenized(_ query: String) -> SearchQuery.Tokenized {
    SearchQuery.tokenized(query, workingGroups: workingGroups)
  }

  /// One term per word of the canonical form, in its order, each named for a
  /// reader rather than in the query's syntax.
  @Test func `every filter is a term, in the canonical order`() {
    let terms = terms(
      "cache has:xml year:2022-2020 stream:irtf by:Fielding status:current is:bcp is:std group:HTTPBIS"
    )
    #expect(
      terms.map(\.word) == [
        "wg:httpbis", "status:std", "status:bcp", "status:current", "author:fielding",
        "stream:irtf", "year:2020-2022", "has:xml",
      ])
    #expect(
      terms.map(\.label) == [
        "WG: httpbis", "Standards Track", "Best Current Practice", "Not Obsoleted",
        "Author: fielding", "Stream: IRTF", "Year: 2020–2022", "Has XML",
      ])
  }

  @Test func `a single year is labeled as one`() {
    #expect(terms("year:1997").map(\.label) == ["Year: 1997"])
  }

  @Test func `free text is no term`() {
    #expect(terms("cache color:red").isEmpty)
  }

  /// Removing a chip takes out the words that set it and leaves the rest of the
  /// query as the reader typed it: its order, its aliases, and a word `parseQuery`
  /// ignores, like a stream it does not know.
  @Test func `a term removed from a query leaves the rest as typed`() throws {
    let query = "stream:iab-x cache wg:tls is:standard is:bcp"
    let group = try #require(terms(query).first { $0.word == "wg:tls" })
    #expect(SearchQuery.removing(group, from: query) == "stream:iab-x cache is:standard is:bcp")
    let status = try #require(terms(query).first { $0.word == "status:bcp" })
    #expect(SearchQuery.removing(status, from: query) == "stream:iab-x cache wg:tls is:standard")
  }

  /// Working groups are a union (#355); removing one's chip leaves the others.
  @Test func `removing a working group leaves the others`() throws {
    let query = "wg:quic cache wg:tls"
    let group = try #require(terms(query).first)
    #expect(SearchQuery.removing(group, from: query) == "cache wg:tls")
  }

  /// An author holds one value, the last word's: removing its chip removes every
  /// word naming one, or an earlier one would take its place.
  @Test func `removing an author removes every word naming one`() throws {
    let query = "by:quic cache author:tls"
    let author = try #require(terms(query).first)
    #expect(SearchQuery.removing(author, from: query) == "cache")
  }

  /// The Mac field's caret is after the space the reader typed; removing a chip keeps
  /// it, or the next keystroke would run into the last word.
  @Test func `removing a term keeps the space the reader typed last`() throws {
    let group = try #require(terms("wg:tls").first)
    #expect(SearchQuery.removing(group, from: "wg:tls cache ") == "cache ")
    #expect(SearchQuery.removing(group, from: "wg:tls ") == "")
  }

  /// A chip that has gone from the query while the list catches up removes nothing.
  @Test func `removing a term the query no longer has leaves it`() throws {
    let group = try #require(terms("wg:tls").first)
    #expect(SearchQuery.removing(group, from: "cache status:bcp") == "cache status:bcp")
  }

  // MARK: - Editing tokens and text

  /// What the reader types in the iOS field replaces the text and keeps the tokens.
  @Test func `new text keeps the tokens`() {
    #expect(
      SearchQuery.replacingText(
        in: "wg:tls cache", with: "caching ", workingGroups: workingGroups) == "wg:tls caching ")
  }

  /// A token removed from the iOS field leaves the text as it was.
  @Test func `new tokens keep the text`() {
    let query = "wg:tls is:bcp cache "
    let kept = tokenized(query).terms.filter { $0.word != "wg:tls" }
    #expect(
      SearchQuery.replacingTerms(in: query, with: kept, workingGroups: workingGroups)
        == "status:bcp cache ")
  }

  // MARK: - Tokens

  /// A filter the reader has finished typing becomes a token; the word still being
  /// typed stays text, or `wg:t` would be a token before `wg:tls` could be typed.
  @Test func `a finished filter becomes a token and the word being typed stays text`() {
    let split = tokenized("cache wg:tls status:b")
    #expect(split.terms.map(\.word) == ["wg:tls"])
    #expect(split.text == "cache status:b")
  }

  /// A filter typed in front of the text is not the word being typed, so `wg:t` would
  /// be a token after its first letter, before `wg:tls` could be typed. A working
  /// group becomes a token only once it names one the index knows, as a status only
  /// once it is a status.
  @Test func `a working group the index does not know stays text`() {
    let typing = tokenized("wg:t cache")
    #expect(typing.terms.isEmpty)
    #expect(typing.text == "wg:t cache")
    let typed = tokenized("wg:tls cache")
    #expect(typed.terms.map(\.word) == ["wg:tls"])
    #expect(typed.text == "cache")
  }

  /// The space the reader has just typed is kept, or the field would take it back.
  @Test func `a trailing space stays in the text`() {
    #expect(tokenized("cache ").text == "cache ")
    #expect(tokenized("wg:tls ").text == "")
    #expect(tokenized("wg:tls ").terms.map(\.word) == ["wg:tls"])
  }

  /// A word with a colon that filters nothing is searched as text, so it stays text.
  @Test func `a word that filters nothing stays text`() {
    let split = tokenized("color:red status:stnd cache ")
    #expect(split.terms.isEmpty)
    #expect(split.text == "color:red status:stnd cache ")
  }

  /// A second working group joins the first, as working groups are a union.
  @Test func `a later working group joins the token of an earlier one`() {
    let split = tokenized(
      SearchQuery.joined(terms: terms("wg:tls"), text: "wg:quic "))
    #expect(split.terms.map(\.word) == ["wg:quic", "wg:tls"])
  }

  /// The one search text is what the list filters on; tokens and text are a view of
  /// it, and put back together they are the same query.
  @Test(arguments: ["", "cache", "cache ", "wg:tls status:b", "wg:tls is:bcp cache "])
  func `tokens and text join back to the query they came from`(query: String) {
    let split = tokenized(query)
    let joined = SearchQuery.joined(terms: split.terms, text: split.text)
    #expect(IndexSearch.parseQuery(joined) == IndexSearch.parseQuery(query))
    #expect(tokenized(joined) == split)
  }

  // MARK: - Taking a suggestion

  /// A suggestion that completes a filter ends with a space, so the next word begins
  /// and on iOS the filter becomes a token; one that completes only the qualifier
  /// waits for its value.
  @Test func `a suggestion that completes a filter is taken with a space after it`() throws {
    let index = try Fixtures.sampleIndex()
    #expect(SearchQuery.suggestions(for: "wg:q", in: index).map(\.accepted) == ["wg:quic "])
    #expect(SearchQuery.suggestions(for: "cache w", in: index).map(\.accepted) == ["cache wg:"])
    #expect(
      SearchQuery.suggestions(for: "cache color:red", in: index).map(\.accepted) == [
        "cache color:red"
      ])
  }

  /// A list over the results at every space, after every filter taken as a token, or
  /// on clearing the field would hide them as the reader types.
  @Test func `a word is offered nothing until it has a letter`() throws {
    let index = try Fixtures.sampleIndex()
    #expect(SearchQuery.suggestionsWhileTyping(for: "cache ", in: index).isEmpty)
    #expect(SearchQuery.suggestionsWhileTyping(for: "", in: index).isEmpty)
    #expect(
      SearchQuery.suggestionsWhileTyping(for: "cache w", in: index).map(\.completion) == [
        "cache wg:"
      ])
  }

  /// What the suggestion list shows: the word completed, not the whole query.
  @Test func `a suggestion shows the word it completes`() throws {
    let index = try Fixtures.sampleIndex()
    #expect(
      SearchQuery.suggestions(for: "cache wg:no", in: index).map(\.word) == [
        #"wg:"non working group""#
      ])
  }
}
