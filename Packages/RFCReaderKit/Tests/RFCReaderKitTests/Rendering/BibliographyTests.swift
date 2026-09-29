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
}
