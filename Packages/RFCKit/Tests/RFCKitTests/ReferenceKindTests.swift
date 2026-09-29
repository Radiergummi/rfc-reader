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

  /// A list can say how it is ordered after its kind, in parentheses; the kind is
  /// still what it names. Titles in that shape, not quoted from a document.
  @Test(arguments: [
    ("Normative References (By Number)", ReferenceList.Kind.normative),
    ("Informative References (In Order of Citation)", .informative),
    ("References (By Number)", .unknown),
  ])
  func `a trailing parenthetical does not hide the kind`(title: String, kind: ReferenceList.Kind) {
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

  /// The entry a citation resolved to is recorded on its target, so its kind can be
  /// read from the list that holds the entry.
  @Test func `an XML citation records the entry it resolved to`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
    #expect(
      Self.targets(in: document).contains(
        .document(.rfc(9000), section: nil, entry: "QUIC-TRANSPORT")))
  }

  /// A `<referencegroup>` is one entry in its list, so a citation of one of its
  /// members resolves to the group's entry: RFC 9682 cites RFC 8949, which its
  /// normative references hold only as a member of STD 94.
  @Test func `a citation of a reference group's member records the group as its entry`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9682.xml"))
    #expect(
      Self.targets(in: document).contains(.document(.rfc(8949), section: "3.3", entry: "STD94")))
  }

  @Test func `a legacy citation records the entry it resolved to`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let entry = try #require(Self.entries(in: document).first { $0.documentID == .rfc(733) })
    #expect(
      Self.targets(in: document).contains(.document(.rfc(733), section: nil, entry: entry.anchor)))
  }

  private static func targets(in document: RFCDocument) -> [CrossReference.Target] {
    document.proseInlines.compactMap { inline in
      guard case .crossReference(let xref) = inline else { return nil }
      return xref.target
    }
  }

  private static func entries(in document: RFCDocument) -> [Reference] {
    document.blocks.flatMap { block -> [Reference] in
      guard case .references(let list) = block else { return [] }
      return list.entries
    }
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
