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

  /// Filters built by hand, not by `parseQuery`, which lowercases what it reads:
  /// the prepared fields are lowercased, so the needles have to be as well (#151).
  @Test func `a filter value built in capitals matches`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    func numbers(group: String? = nil, author: String? = nil) -> [Int] {
      var filters = SearchFilters()
      filters.workingGroup = group
      filters.author = author
      return search.search(text: "", filters: filters, limit: .max).map(\.rfc.number)
    }
    #expect(!numbers(group: "httpbis").isEmpty)
    #expect(numbers(group: "HTTPBIS") == numbers(group: "httpbis"))
    #expect(!numbers(author: "fielding").isEmpty)
    #expect(numbers(author: "FIELDING") == numbers(author: "fielding"))
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

  /// An empty value filters out everything, as it did through Foundation, rather
  /// than matching every document with no working group, or with any author.
  @Test func `an empty filter value matches nothing`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    for keyPath in [\SearchFilters.workingGroup, \SearchFilters.author] {
      var filters = SearchFilters()
      filters[keyPath: keyPath] = ""
      #expect(search.search(text: "", filters: filters, limit: .max).isEmpty)
    }
  }

  @Test func `no match is empty`() throws {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    #expect(search.search("zzzz-nothing-matches").isEmpty)
  }
}
