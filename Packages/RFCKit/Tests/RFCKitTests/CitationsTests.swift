import Foundation
import Testing

@testable import RFCKit

/// Which documents a document cites, from where, and how (#174): the rows of the
/// corpus's citation index.
@Suite("Citations")
struct CitationsTests {
  private static func citations(_ fixture: String) throws -> [Citation] {
    Citations.of(try Fixtures.document(fixture))
  }

  /// RFC 9290 cites RFC 7252 from four sections, four times from the one anchored
  /// `basic`, all through its normative entry.
  @Test func `a document's citations of another are counted per section`() throws {
    let citations = try Self.citations("rfc9290.xml").filter { $0.cited == .rfc(7252) }
    #expect(
      citations == [
        Citation(cited: .rfc(7252), place: .section("introduction"), count: 1, kind: .normative),
        Citation(
          cited: .rfc(7252), place: .section("terminology-and-requirements-language"), count: 1,
          kind: .normative),
        Citation(cited: .rfc(7252), place: .section("basic"), count: 4, kind: .normative),
        Citation(cited: .rfc(7252), place: .section("uco"), count: 1, kind: .normative),
      ])
  }

  @Test func `a citation through an informative entry is informative`() throws {
    let citations = try Self.citations("rfc9290.xml")
    #expect(
      citations.contains(
        Citation(
          cited: .rfc(6082), place: .section("detailed-semantics"), count: 1, kind: .informative)))
  }

  /// RFC 9290's abstract names RFC 7807, which it updates.
  @Test func `the abstract cites first`() throws {
    let citations = try Self.citations("rfc9290.xml")
    #expect(
      citations.first
        == Citation(cited: .rfc(7807), place: .abstract, count: 1, kind: .normative))
  }

  /// RFC 9290's bibliography also lists IANA registries, a W3C document and Unicode,
  /// none of them in a series, and an Internet-Draft.
  @Test func `only documents in a series are cited, and never the document itself`() throws {
    let cited = Set(try Self.citations("rfc9290.xml").map(\.cited))
    #expect(!cited.contains(.rfc(9290)))
    #expect(cited.allSatisfy { [.rfc, .std, .bcp].contains($0.series) })
  }

  /// A citation of a group's member and one of the group are kept apart, as the
  /// source makes them: RFC 9290 cites RFC 8949 and STD 94, its group.
  @Test func `a group and its member are cited apart`() throws {
    let terminology = try Self.citations("rfc9290.xml").filter {
      $0.place == .section("terminology-and-requirements-language")
    }
    #expect(terminology.contains { $0.cited == .rfc(8949) && $0.count == 2 })
    #expect(
      terminology.contains {
        $0.cited == DocumentID(series: .std, number: 94) && $0.count == 2
      })
  }

  /// RFC 2049 has one list, titled References, which says neither kind; it lists RFC
  /// 783 and never cites it.
  @Test func `a listed document the prose never cites is cited from the bibliography`() throws {
    let citations = try Self.citations("rfc2049.txt")
    #expect(
      citations.contains(Citation(cited: .rfc(783), place: .bibliography, count: 1, kind: .unknown))
    )
    #expect(citations.allSatisfy { $0.kind == .unknown })
    // Once from the bibliography, and not at all once the prose has cited it.
    let bibliography = citations.filter { $0.place == .bibliography }.map(\.cited)
    #expect(Set(bibliography).count == bibliography.count)
    #expect(!bibliography.contains(.rfc(822)))
  }

  /// RFC 1245 has no bibliography, so its mentions of other RFCs name no entry.
  @Test func `a mention no entry names has no kind`() throws {
    let citations = try Self.citations("rfc1245.txt")
    #expect(citations.contains(Citation(cited: .rfc(1247), place: .abstract, count: 2, kind: nil)))
    #expect(citations.allSatisfy { $0.kind == nil })
  }

  /// The index names a document by its file, which a header may not: whichever ID is
  /// given is the one never cited.
  @Test func `the document named as citing is never cited`() throws {
    let citations = Citations.of(try Fixtures.document("rfc9290.xml"), citing: .rfc(7252))
    #expect(!citations.contains { $0.cited == .rfc(7252) })
    #expect(!citations.isEmpty)
  }

  @Test func `citations survive encoding`() throws {
    let citations = try Self.citations("rfc9290.xml")
    let data = try JSONEncoder().encode(citations)
    #expect(try JSONDecoder().decode([Citation].self, from: data) == citations)
  }
}
