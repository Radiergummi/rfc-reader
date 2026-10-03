import Testing

@testable import RFCKit

/// What an RFC entity's query finds for what was typed or said (#192): the RFC a
/// number names, a series' members, or what the index search finds.
@Suite("Document lookup")
struct DocumentLookupTests {
  private func lookup(_ query: String) throws -> [Int] {
    let search = IndexSearch(index: try Fixtures.sampleIndex())
    return DocumentLookup.rfcs(matching: query, in: search).map(\.number)
  }

  /// A number in any spelling names one RFC, and nothing it begins: Siri asking
  /// which of RFC 9110 and RFC 91100 was meant would be asking for nothing.
  @Test func `a number in any spelling names its RFC alone`() throws {
    for spelling in ["9110", "RFC 9110", "rfc9110", "RFC-9110", " RFC 9110 "] {
      #expect(try lookup(spelling) == [9110], "\(spelling)")
    }
  }

  @Test func `a series names its members`() throws {
    #expect(try lookup("BCP 14") == [2119, 8174])
    #expect(try lookup("bcp14") == [2119, 8174])
  }

  @Test func `words are searched as the sidebar searches them`() throws {
    #expect(try lookup("avian carriers") == [1149])
    #expect(try lookup("HTTP Semantics").first == 9110)
  }

  /// A number the index lacks is searched like any other text, which is how a
  /// title's digits are still found.
  @Test func `a number not in the index is searched for`() throws {
    #expect(try lookup("2616") == [])
  }

  @Test func `an obsoleted RFC is found, and says what replaced it`() throws {
    let index = try Fixtures.sampleIndex()
    let rfc = try #require(
      DocumentLookup.rfcs(matching: "7231", in: IndexSearch(index: index)).first)
    #expect(rfc.isObsolete)
    #expect(rfc.obsoletionNote == "Obsoleted by RFC 9110")
    #expect(index[9110]?.obsoletionNote == nil)
  }

  /// What a Shortcut or Spotlight hands back: the file stems, in the order given,
  /// without the ones the index has not got.
  @Test func `identifiers name RFCs in the order given`() throws {
    let index = try Fixtures.sampleIndex()
    let found = DocumentLookup.rfcs(identifiedBy: ["rfc9110", "rfc1", "RFC2119", "rfc1149"], in: index)
    #expect(found.map(\.number) == [9110, 1149])
  }
}
