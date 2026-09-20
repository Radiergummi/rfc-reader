import Testing
@testable import RFCKit

@Suite("RFC index parser")
struct RFCIndexParserTests {
    @Test func parsesEveryEntryKind() throws {
        let index = try Fixtures.sampleIndex()
        #expect(index.rfcs.count >= 9)
        #expect(index.series.contains { $0.id == DocumentID(series: .bcp, number: 14) })
        #expect(index.series.contains { $0.id == DocumentID(series: .std, number: 97) })
        #expect(index.notIssued.contains(14))
    }

    @Test func readsRichMetadata() throws {
        let index = try Fixtures.sampleIndex()
        let http = try #require(index[9110])
        #expect(http.title == "HTTP Semantics")
        #expect(http.authors.map(\.name) == ["R. Fielding", "M. Nottingham", "J. Reschke"])
        #expect(http.authors.allSatisfy { $0.role == "Editor" })
        #expect(http.date == PublicationDate(year: 2022, month: 6))
        #expect(http.formats.contains(.xml))
        #expect(http.hasXMLSource)
        #expect(http.pageCount == 194)
        #expect(http.isAlso == [DocumentID(series: .std, number: 97)])
        #expect(http.obsoletes.contains(.rfc(7231)))
        #expect(http.updates == [.rfc(3864)])
        #expect(http.currentStatus == .internetStandard)
        #expect(http.stream == .ietf)
        #expect(http.workingGroup == "httpbis")
        #expect(http.area == "wit")
        #expect(http.doi == "10.17487/RFC9110")
        #expect(http.hasErrata)
        #expect(http.draft == "draft-ietf-httpbis-semantics-19")
        #expect(http.abstract?.hasPrefix("The Hypertext Transfer Protocol (HTTP)") == true)
    }

    @Test func legacyEntriesHaveSensibleDefaults() throws {
        let index = try Fixtures.sampleIndex()
        let pigeons = try #require(index[1149])
        #expect(pigeons.currentStatus == .experimental)
        #expect(pigeons.stream == .independent)
        #expect(!pigeons.hasXMLSource)
        #expect(pigeons.date.year == 1990)
    }

    @Test func obsoleteChainIsNavigable() throws {
        let index = try Fixtures.sampleIndex()
        let old = try #require(index[7231])
        #expect(old.isObsolete)
        #expect(old.obsoletedBy == [.rfc(9110)])
        #expect(index.documentsAffecting(7231).map(\.number) == [9110])
    }

    @Test func seriesMembership() throws {
        let index = try Fixtures.sampleIndex()
        let bcp14 = try #require(index.series(DocumentID(series: .bcp, number: 14)))
        #expect(bcp14.members == [.rfc(2119), .rfc(8174)])
    }
}
