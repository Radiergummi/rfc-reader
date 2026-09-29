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
    let parsed = IndexSearch.parseQuery("wg:httpbis status:std year:2020-2022 cache")
    #expect(parsed.text == "cache")
    #expect(parsed.filters.workingGroup == "httpbis")
    #expect(parsed.filters.statuses == [.internetStandard, .draftStandard, .proposedStandard])
    #expect(parsed.filters.yearRange == 2020...2022)
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

  /// The filters normalise their own text, so a hand-built filter matches like a
  /// parsed one: the prepared fields it is matched against are lowercased.
  @Test func `a text filter value is stored lowercased`() {
    var filters = SearchFilters()
    filters.workingGroup = "HTTPBIS"
    filters.author = "Fielding"
    #expect(filters.workingGroup == "httpbis")
    #expect(filters.author == "fielding")
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
