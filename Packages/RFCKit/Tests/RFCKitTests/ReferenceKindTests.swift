import Testing

@testable import RFCKit

/// Whether a bibliography is normative or informative, from its title (#184).
@Suite("Reference kind")
struct ReferenceKindTests {
  /// The spellings measured over the converted corpus: 4,717 normative, 4,638
  /// informative, 31 informational and 10 non-normative lists.
  @Test(arguments: [
    ("Normative References", ReferenceList.Kind.normative),
    ("Normative", .normative),
    ("Informative References", .informative),
    ("Informational References", .informative),
    ("Non-Normative References", .informative),
    ("Informative", .informative),
    ("NORMATIVE REFERENCES", .normative),
    ("6.1.  Normative References", .normative),
    ("Informative References:", .informative),
    ("References", .unknown),
    ("References and Bibliography", .unknown),
  ])
  func `a title names the kind`(title: String, kind: ReferenceList.Kind) {
    #expect(ReferenceList.Kind(title: title) == kind)
  }

  /// A section about the rule, not a list: matching on the word alone read it as one.
  @Test func `a title that only mentions normative references names no kind`() {
    #expect(
      ReferenceList.Kind(
        title: "Standards Track, Informational Documents, and Normative References")
        == .unknown)
  }

  @Test func `an XML document's split references have their kinds`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
    #expect(Self.kinds(in: document) == [.normative, .informative])
  }

  @Test func `a legacy document's split references have their kinds`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    #expect(Self.kinds(in: document) == [.normative, .informative])
  }

  /// Before about RFC 2200 a document has one list, and whether a reference in it is
  /// normative is simply not said.
  @Test func `a single list of references has no kind`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc793.txt"))
    #expect(Self.kinds(in: document) == [.unknown])
  }

  private static func kinds(in document: RFCDocument) -> [ReferenceList.Kind] {
    document.allSections.flatMap { section in
      section.blocks.compactMap { block -> ReferenceList.Kind? in
        guard case .references(let list) = block, !list.entries.isEmpty else { return nil }
        return list.kind
      }
    }
  }
}
