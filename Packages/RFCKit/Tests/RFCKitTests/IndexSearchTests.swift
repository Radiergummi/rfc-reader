import Testing

@testable import RFCKit

@Suite("Metadata search")
struct IndexSearchTests {
  @Test func `number goes straight to the document`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("9110").map(\.rfc.number) == [9110])
    #expect(search.search("rfc 2119").map(\.rfc.number) == [2119])
  }

  @Test func `title words rank above abstract mentions`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    let hits = search.search("HTTP semantics")
    #expect(hits.first?.rfc.number == 9110)
    #expect(hits.contains { $0.rfc.number == 7231 }, "obsoleted RFC 7231 is still findable")
  }

  @Test func `filters parse`() {
    let (text, filters) = IndexSearch.parseQuery("wg:httpbis status:std year:2020-2022 cache")
    #expect(text == "cache")
    #expect(filters.workingGroup == "httpbis")
    #expect(filters.statuses == [.internetStandard, .draftStandard, .proposedStandard])
    #expect(filters.yearRange == 2020...2022)
  }

  // MARK: Quoted values (#177)

  @Test func `a quoted value is one token`() {
    let parsed = IndexSearch.parseQuery(#"author:"Roy Fielding" cache"#)
    #expect(parsed.filters.author == "roy fielding")
    #expect(parsed.text == "cache")
  }

  /// Smart Punctuation, on by default on iOS, types these for `"`.
  @Test func `typographic quotes quote a value too`() {
    let parsed = IndexSearch.parseQuery("author:\u{201C}Roy Fielding\u{201D} cache")
    #expect(parsed.filters.author == "roy fielding")
    #expect(parsed.text == "cache")
  }

  /// Smart Punctuation picks a quote's direction from the character before it, so
  /// after a colon it types a closing one; a German keyboard types „ and “.
  @Test(arguments: [
    "author:\u{201D}Roy Fielding\u{201D} cache",
    "author:\u{201E}Roy Fielding\u{201C} cache",
  ])
  func `any typographic quote opens a value`(query: String) {
    let parsed = IndexSearch.parseQuery(query)
    #expect(parsed.filters.author == "roy fielding")
    #expect(parsed.text == "cache")
  }

  /// `wg:"` is a value still being typed, and filtering on an empty group would
  /// empty the list; it is free text, as `wg:` is.
  @Test func `an empty quoted value is not a filter`() {
    let parsed = IndexSearch.parseQuery(#"cache wg:""#)
    #expect(parsed.filters.workingGroup == nil)
    #expect(parsed.text == #"cache wg:""#)
  }

  /// The query is being typed: the closing quote has not arrived yet.
  @Test func `an unclosed quote runs to the end of the query`() {
    let parsed = IndexSearch.parseQuery(#"cache author:"Roy Fiel"#)
    #expect(parsed.filters.author == "roy fiel")
    #expect(parsed.text == "cache")
  }

  @Test func `a quoted phrase stays one term of the free text`() {
    #expect(IndexSearch.parseQuery(#""key words" by:bradner"#).text == #""key words""#)
  }

  /// RFC 8174's title has both words, but not side by side.
  @Test func `a quoted phrase has to match as a phrase`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("uppercase key").contains { $0.rfc.number == 8174 })
    #expect(search.search(#""uppercase key""#).isEmpty)
    let phrase = search.search(#""key words""#).map(\.rfc.number)
    #expect(phrase.contains(2119))
    #expect(phrase.contains(8174))
  }

  /// The title bonus compares the title with the query as written, less its quotes;
  /// the same terms in another order do not earn it.
  @Test func `a quoted phrase still earns the bonus for a title that reads as the query`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    let inOrder = try #require(search.search(#""key words" for"#).first { $0.rfc.number == 2119 })
    let reversed = try #require(search.search(#"for "key words""#).first { $0.rfc.number == 2119 })
    #expect(inOrder.score == reversed.score + 50)
  }

  @Test func `filters apply`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    let current = search.search("status:current HTTP")
    #expect(!current.contains { $0.rfc.isObsolete })
    #expect(current.contains { $0.rfc.number == 9110 })

    let byAuthor = search.search("author:fielding")
    #expect(
      byAuthor.allSatisfy { hit in
        hit.rfc.authors.contains { $0.name.lowercased().contains("fielding") }
      })
    #expect(!byAuthor.isEmpty)

    let xmlOnly = search.search("has:xml")
    #expect(xmlOnly.allSatisfy { $0.rfc.hasXMLSource })
  }

  @Test func `no match is empty`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("zzzz-nothing-matches").isEmpty)
  }
}
