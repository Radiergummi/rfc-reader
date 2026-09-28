import Foundation
import Testing

@testable import RFCKit

/// Which sections of other RFCs a document amends: a citation of a section of a
/// document the updating one says it updates (#179).
@Suite("Amendments")
struct AmendmentsTests {
  private static func document(_ name: String) throws -> RFCDocument {
    try RFCXMLParser.parse(try Fixtures.data(name))
  }

  /// RFC 9283 updates RFC 2850, and says where: Sections 1.2 and 2.
  @Test func `a section citation of an updated document is an amendment`() throws {
    let document = try Self.document("rfc9283.xml")
    let links = Amendments.links(in: document)
    #expect(Set(links.map(\.section)) == ["1.2", "2"])
    #expect(links.allSatisfy { $0.amended == .rfc(2850) && $0.amending == .rfc(9283) })
    #expect(
      links.allSatisfy { $0.amendingSection != nil },
      "every citation sits in a section of the amending document")
  }

  /// RFC 9601 updates six documents and amends sections of four of them.
  @Test func `every amended document is one the document updates`() throws {
    let document = try Self.document("rfc9601.xml")
    let links = Amendments.links(in: document)
    #expect(Set(links.map(\.amended)).isSubset(of: Set(document.header.updates)))
    #expect(links.contains { $0.amended == .rfc(6040) && $0.section == "4.3" })
    #expect(links.contains { $0.amended == .rfc(7450) && $0.section == "5.1.3.3" })
  }

  /// A section of a document it only cites is not amended: RFC 9601 cites sections
  /// of documents it does not update, and none of them is a link.
  @Test func `a section citation of any other document is not an amendment`() throws {
    let document = try Self.document("rfc9601.xml")
    let updated = Set(document.header.updates)
    let cited = document.proseInlines.compactMap { inline -> DocumentID? in
      guard case .crossReference(let xref) = inline,
        case .document(let id, let section) = xref.target,
        section != nil
      else { return nil }
      return id
    }
    #expect(
      cited.contains { !updated.contains($0) }, "the fixture must cite another document's section")
    #expect(Amendments.links(in: document).allSatisfy { updated.contains($0.amended) })
  }

  /// A document that updates nothing amends nothing, however many sections it cites.
  @Test func `a document that updates nothing amends nothing`() throws {
    let document = try Self.document("rfc8999.xml")
    #expect(document.header.updates.isEmpty)
    #expect(Amendments.links(in: document).isEmpty)
  }

  /// One link per place, however often that section cites the same section.
  @Test func `a section amending the same section twice is one link`() throws {
    let links = Amendments.links(in: try Self.document("rfc9682.xml"))
    let keys = links.map { "\($0.amended) \($0.section) \($0.amendingSection ?? "")" }
    #expect(keys.count == Set(keys).count)
    #expect(!links.isEmpty)
  }
}
