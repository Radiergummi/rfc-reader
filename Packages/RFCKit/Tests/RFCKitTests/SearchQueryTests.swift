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

  /// `parseQuery` reads `by:`, `is:` and `group:` as well; a reader who types one
  /// is offered the qualifier it stands for, by its long name.
  @Test func `a word that begins an alias is offered its qualifier`() throws {
    #expect(try completions("cache by") == ["cache author:"])
    #expect(try completions("is") == ["status:"])
    #expect(try completions("gro") == ["wg:"])
  }

  @Test func `an empty last word is offered every qualifier`() throws {
    #expect(
      try completions("cache ")
        == [
          "cache wg:", "cache status:", "cache author:", "cache stream:", "cache year:",
          "cache has:xml",
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
    #expect(IndexSearch.parseQuery(completed).filters.workingGroup == "non working group")
  }

  @Test func `statuses and streams are completed from their vocabulary`() throws {
    #expect(
      try completions("status:") == [
        "status:std", "status:bcp", "status:info", "status:exp", "status:historic",
        "status:current",
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
      for: "cache colour:red", in: try Fixtures.sampleIndex())
    #expect(suggestions.map(\.isUnknown) == [true])
    #expect(suggestions.first?.completion == "cache colour:red")
  }
}
