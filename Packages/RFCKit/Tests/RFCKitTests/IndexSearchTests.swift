import Testing
@testable import RFCKit

@Suite("Metadata search")
struct IndexSearchTests {
    @Test func numberGoesStraightToTheDocument() throws {
        let search = IndexSearch(index: try Fixtures.sampleIndex())
        #expect(search.search("9110").map(\.rfc.number) == [9110])
        #expect(search.search("rfc 2119").map(\.rfc.number) == [2119])
    }

    @Test func titleWordsRankAboveAbstractMentions() throws {
        let search = IndexSearch(index: try Fixtures.sampleIndex())
        let hits = search.search("HTTP semantics")
        #expect(hits.first?.rfc.number == 9110)
        #expect(hits.contains { $0.rfc.number == 7231 }, "obsoleted RFC 7231 is still findable")
    }

    @Test func filtersParse() {
        let (text, filters) = IndexSearch.parseQuery("wg:httpbis status:std year:2020-2022 cache")
        #expect(text == "cache")
        #expect(filters.workingGroup == "httpbis")
        #expect(filters.statuses == [.internetStandard, .draftStandard, .proposedStandard])
        #expect(filters.yearRange == 2020...2022)
    }

    @Test func filtersApply() throws {
        let search = IndexSearch(index: try Fixtures.sampleIndex())
        let current = search.search("status:current HTTP")
        #expect(!current.contains { $0.rfc.isObsolete })
        #expect(current.contains { $0.rfc.number == 9110 })

        let byAuthor = search.search("author:fielding")
        #expect(byAuthor.allSatisfy { hit in hit.rfc.authors.contains { $0.name.lowercased().contains("fielding") } })
        #expect(!byAuthor.isEmpty)

        let xmlOnly = search.search("has:xml")
        #expect(xmlOnly.allSatisfy { $0.rfc.hasXMLSource })
    }

    @Test func noMatchIsEmpty() throws {
        let search = IndexSearch(index: try Fixtures.sampleIndex())
        #expect(search.search("zzzz-nothing-matches").isEmpty)
    }
}
