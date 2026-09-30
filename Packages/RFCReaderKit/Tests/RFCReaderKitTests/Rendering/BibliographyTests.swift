import RFCKit
import Testing

@testable import RFCReaderKit

/// A citation of a bibliography entry names it by anchor; its preview needs the
/// entry itself, which the body leaves out and the panel holds (#198).
@Suite("Bibliography")
struct BibliographyTests {
  @Test func `an entry is found by its anchor across the document's bibliographies`() throws {
    let groups = ReferenceGroup.groups(in: try Fixtures.rfc8999())
    let entry = try #require(groups.entry(anchor: "QUIC-TRANSPORT"))
    #expect(entry.title == "QUIC: A UDP-Based Multiplexed and Secure Transport")
    #expect(entry.authors.map(\.displayName) == ["Jana Iyengar, Ed.", "Martin Thomson, Ed."])
  }

  @Test func `an anchor no bibliography holds finds nothing`() throws {
    let groups = ReferenceGroup.groups(in: try Fixtures.rfc8999())
    #expect(groups.entry(anchor: "section-2") == nil)
  }

  // MARK: Normative or informative (#184)

  /// RFC 8999 cites RFC 2119 normatively, and RFC 5116 and the QUIC drafts only
  /// informatively.
  @Test func `a citation has the kind of the list that holds its entry`() throws {
    let groups = ReferenceGroup.groups(in: try Fixtures.rfc8999())
    #expect(groups.kind(of: .document(.rfc(2119), section: nil)) == .normative)
    #expect(groups.kind(of: .document(.rfc(5116), section: "2")) == .informative)
    #expect(groups.kind(of: .anchor("QUIC-TLS")) == .informative)
  }

  @Test func `a citation no list holds has no kind`() throws {
    let groups = ReferenceGroup.groups(in: try Fixtures.rfc8999())
    #expect(groups.kind(of: .document(.rfc(1), section: nil)) == .unknown)
    #expect(groups.kind(of: .anchor("section-2")) == .unknown)
  }

  /// A citation of a `<referencegroup>`'s member names the document the member is,
  /// which no entry's own series names; the entry the parser resolved it to is the
  /// group's, and so is the kind.
  @Test func `a citation has the kind of the entry it resolved to`() {
    let group = Reference(
      anchor: "BCP26", title: "BCP 26 consists of RFC 8126",
      seriesInfo: [
        SeriesInfo(name: "BCP", value: "26")
      ])
    let groups = [ReferenceGroup(title: "Normative References", entries: [group])]
    #expect(groups.kind(of: .document(.rfc(8126), section: nil, entry: "BCP26")) == .normative)
    #expect(groups.kind(of: .document(.rfc(8126), section: nil)) == .unknown)
  }

  /// A bare mention of a group's member records no entry, and no entry's series
  /// names the member; the group keeps its members' documents, so the mention has
  /// the group's kind.
  @Test func `a mention of a reference group's member has the group's kind`() {
    let group = Reference(
      anchor: "BCP26", title: "BCP 26 consists of RFC 8126",
      seriesInfo: [
        SeriesInfo(name: "BCP", value: "26")
      ],
      members: [.rfc(8126)])
    let groups = [ReferenceGroup(title: "Informative References", entries: [group])]
    #expect(groups.kind(of: .document(.rfc(8126), section: "4.1")) == .informative)
  }

  /// A document that lists an entry in both counts it as part of the specification.
  @Test func `an entry in both lists is normative`() {
    let entry = Reference(
      anchor: "RFC9110", title: "HTTP Semantics",
      seriesInfo: [
        SeriesInfo(name: "RFC", value: "9110")
      ])
    let groups = [
      ReferenceGroup(title: "Informative References", entries: [entry]),
      ReferenceGroup(title: "Normative References", entries: [entry]),
    ]
    #expect(groups.kind(of: .document(.rfc(9110), section: nil)) == .normative)
  }
}
