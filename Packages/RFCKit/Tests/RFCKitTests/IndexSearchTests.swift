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
