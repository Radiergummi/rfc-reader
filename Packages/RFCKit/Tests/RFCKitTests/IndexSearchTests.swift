import Testing

@testable import RFCKit

@Suite("Metadata search")
struct IndexSearchTests {
  @Test func `number goes straight to the document`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("9110").map(\.rfc.number) == [9110])
    #expect(search.search("rfc 2119").map(\.rfc.number) == [2119])
  }

  /// Typing a number is often typing the start of a longer one: `991` on its way to
  /// 9910. The document the number names comes first, then every number it begins,
  /// newest first — and only numbers, not titles that happen to contain the digits.
  @Test func `a number lists the document it names, then the numbers it begins`() {
    let rfcs = [991, 9910, 9915, 9919, 199, 2991].map { number in
      RFCMetadata(
        id: DocumentID(series: .rfc, number: number),
        // A title holding the digits is not a number match.
        title: number == 2991 ? "The 991 Profile" : "Document \(number)",
        date: PublicationDate(year: 2026))
    }
    let search = IndexSearch(index: RFCIndex(rfcs: rfcs))
    #expect(search.search("991").map(\.rfc.number) == [991, 9919, 9915, 9910])
    #expect(search.search("RFC 991").map(\.rfc.number) == [991, 9919, 9915, 9910])
    #expect(search.search("99").map(\.rfc.number) == [9919, 9915, 9910, 991])
  }

  @Test func `a number query is told apart from words, and says which numbers it matches`() {
    #expect(IndexSearch.number(in: "991") == 991)
    #expect(IndexSearch.number(in: " RFC 991 ") == 991)
    #expect(IndexSearch.number(in: "991 http") == nil)
    #expect(IndexSearch.number(in: "status:std 991") == nil)
    #expect(IndexSearch.number(in: "BCP 14") == nil)
    #expect(IndexSearch.matches(.rfc(9910), number: 991))
    #expect(IndexSearch.matches(.rfc(991), number: 991))
    #expect(!IndexSearch.matches(.rfc(9), number: 99))
    #expect(!IndexSearch.matches(DocumentID(series: .bcp, number: 991), number: 991))
  }

  @Test func `title words rank above abstract mentions`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    let hits = search.search("HTTP semantics")
    #expect(hits.first?.rfc.number == 9110)
    #expect(hits.contains { $0.rfc.number == 7231 }, "obsoleted RFC 7231 is still findable")
  }

  @Test func `filters parse`() {
    let parsed = IndexSearch.parseQuery("wg:httpbis status:std year:2020-2022 cache")
    #expect(parsed.text == "cache")
    #expect(parsed.filters.workingGroup == "httpbis")
    #expect(parsed.filters.statuses == [.internetStandard, .draftStandard, .proposedStandard])
    #expect(parsed.filters.yearRange == 2020...2022)
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

  /// A space typed inside the quotes, before or after the value, is not part of it.
  @Test func `a quoted value loses the spaces at its edges`() {
    #expect(IndexSearch.parseQuery(#"author:" "#).filters.author == nil)
    #expect(IndexSearch.parseQuery(#"wg:"httpbis ""#).filters.workingGroup == "httpbis")
  }

  /// The query is being typed: the closing quote has not arrived yet.
  @Test func `an unclosed quote runs to the end of the query`() {
    let parsed = IndexSearch.parseQuery(#"cache author:"Roy Fiel"#)
    #expect(parsed.filters.author == "roy fiel")
    #expect(parsed.text == "cache")
  }

  /// A quote opens a quoted run only at the start of a word or right after `key:`;
  /// anywhere else it is a character of the word, as the inch mark is here.
  @Test func `a quote inside a word is part of it`() {
    let parsed = IndexSearch.parseQuery(#"3.5" floppy status:bcp"#)
    #expect(parsed.filters.statuses == [.bestCurrentPractice])
    #expect(parsed.text == #"3.5" floppy"#)
  }

  @Test(arguments: [
    (#"3.5" floppy status:bcp"#, [#"3.5""#, "floppy", "status:bcp"]),
    (#"wg:ab"c d"#, [#"wg:ab"c"#, "d"]),
    (#"a"b "c d""#, [#"a"b"#, #""c d""#]),
    (#"by:"Roy Fielding" x"#, [#"by:"Roy Fielding""#, "x"]),
  ])
  func `a quote opens a run only at the start of a word or after a key`(
    query: String, words: [String]
  ) {
    #expect(SearchQuery.words(in: query) == words)
  }

  @Test(arguments: [
    (#"3.5""#, #"3.5""#),
    (#""key words""#, "key words"),
    (#""key words"#, "key words"),
    ("\u{201E}key words\u{201C}", "key words"),
  ])
  func `only the quotes of a quoted run are taken off`(word: String, text: String) {
    #expect(SearchQuery.unquoted(word) == text)
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

  // MARK: Authors (#177)

  /// The index holds an author as an initial and a surname, "R. Fielding"; a reader
  /// may spell the given name out.
  @Test(arguments: [
    "author:fielding",
    #"author:"R. Fielding""#,
    #"author:"Roy Fielding""#,
    "author:\u{201C}roy fielding\u{201D}",
    #"by:"R Fielding""#,
  ])
  func `an author is found by surname, or by an initial or a given name before it`(query: String)
    throws
  {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search(query).contains { $0.rfc.number == 9110 })
  }

  /// The index holds no given names, so a lone one is read as a surname.
  @Test func `a lone given name is read as a surname`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("author:roy").isEmpty)
  }

  @Test func `a given name has to fit the author's initial`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search(#"author:"Mark Fielding""#).isEmpty)
    #expect(search.search(#"author:"Mark Nottingham""#).contains { $0.rfc.number == 9110 })
  }

  /// A given name comes before the surname, as the index writes the name.
  @Test func `a given name after the surname does not match`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search(#"author:"Fielding Roy""#).isEmpty)
  }

  @Test(arguments: [
    ("R. Fielding", "fielding", true),
    ("R. Fielding", "fiel", true),
    ("R. Fielding", "roy fielding", true),
    ("R. Fielding", "r. fielding", true),
    ("R. Fielding", "roy", false),
    ("R. Fielding", "mark fielding", false),
    ("J.K. Reynolds", "joyce k. reynolds", true),
    ("J.K. Reynolds", "karen reynolds", true),
    ("L-E. Jonsson", "lars-erik jonsson", true),
    ("SN Bhatti", "saleem bhatti", true),
    ("F. Le Faucheur", "francois le faucheur", true),
    ("F. Le Faucheur", "le faucheur", true),
    ("M. St. Johns", "michael st. johns", true),
    ("RFC Editor", "rfc", true),
    ("RFC Editor", "rfc editor", true),
    ("IAB", "iab", true),
    ("M. K\u{00FC}hlewind", "mirja kuhlewind", true),
    ("M. Ku\u{0308}hlewind", "k\u{00FC}hlewind", true),
    ("\u{00C9}. Vyncke", "eric vyncke", true),
  ])
  func `an author name matches a query by surname and initials`(
    name: String, query: String, matches: Bool
  ) {
    #expect(AuthorName(name).matches(AuthorQuery(query)) == matches)
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

  /// The filters normalize their own text, so a hand-built filter matches like a
  /// parsed one: the prepared fields it is matched against are lowercased.
  @Test func `a text filter value is stored lowercased`() {
    var filters = SearchFilters()
    filters.workingGroup = "HTTPBIS"
    filters.author = "Fielding"
    #expect(filters.workingGroup == "httpbis")
    #expect(filters.author == "fielding")
  }

  /// A hand-built filter in mixed case narrows the search as the typed one does.
  /// Only the working group depends on the setter's lowercasing here: the author
  /// query folds its own value when it is prepared.
  @Test func `a hand-built mixed-case filter finds what a typed one does`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    var filters = SearchFilters()
    filters.workingGroup = "HTTPBIS"
    filters.author = "Fielding"
    let handBuilt = search.search(text: "", filters: filters, limit: .max)
    #expect(!handBuilt.isEmpty)
    #expect(handBuilt.allSatisfy { $0.rfc.workingGroup?.lowercased() == "httpbis" })
    #expect(handBuilt.allSatisfy { $0.rfc.authors.contains { $0.name.contains("Fielding") } })
    let typed = search.search("wg:httpbis author:fielding", limit: .max)
    #expect(handBuilt.map(\.rfc.number) == typed.map(\.rfc.number))
  }

  /// A working group matches as a whole name, and an author as part of one, as they
  /// did before the filters read the prepared fields.
  @Test func `a working group matches whole and an author in part`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("wg:httpb", limit: .max).isEmpty)
    let whole = Set(search.search("author:fielding", limit: .max).map(\.rfc.number))
    #expect(!whole.isEmpty)
    #expect(whole.isSubset(of: search.search("author:field", limit: .max).map(\.rfc.number)))
  }

  /// An empty value is no filter: it is stored as nil, and matches every document.
  @Test func `an empty filter value matches like no filter`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    let everything = search.search(text: "", filters: SearchFilters(), limit: .max)
    for keyPath in [\SearchFilters.workingGroup, \SearchFilters.author] {
      var filters = SearchFilters()
      filters[keyPath: keyPath] = ""
      #expect(filters[keyPath: keyPath] == nil)
      #expect(filters.isEmpty)
      let hits = search.search(text: "", filters: filters, limit: .max)
      #expect(hits.map(\.rfc.number) == everything.map(\.rfc.number))
    }
  }

  @Test func `no match is empty`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("zzzz-nothing-matches").isEmpty)
  }
}
