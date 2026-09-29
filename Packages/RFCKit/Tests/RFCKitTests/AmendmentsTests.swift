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

  /// A section of a document it only cites is not amended: RFC 9601 cites
  /// Section 5.3 of RFC 3168, which it does not update, and that is no link.
  @Test func `a section citation of any other document is not an amendment`() throws {
    let document = try Self.document("rfc9601.xml")
    #expect(!document.header.updates.contains(.rfc(3168)))
    let citesRFC3168 = document.proseInlines.contains { inline in
      guard case .crossReference(let xref) = inline else { return false }
      return xref.target == .document(.rfc(3168), section: "5.3")
    }
    #expect(citesRFC3168, "the fixture must cite a section of a document it does not update")
    #expect(!Amendments.links(in: document).contains { $0.amended == .rfc(3168) })
  }

  /// A document that updates nothing amends nothing, however many sections it
  /// cites: RFC 9290 cites sections of other documents and updates none.
  @Test func `a document that updates nothing amends nothing`() throws {
    let document = try Self.document("rfc9290.xml")
    #expect(document.header.updates.isEmpty)
    let citesASection = document.proseInlines.contains { inline in
      guard case .crossReference(let xref) = inline,
        case .document(_, _?) = xref.target
      else { return false }
      return true
    }
    #expect(citesASection, "the fixture must cite a section of another document")
    #expect(Amendments.links(in: document).isEmpty)
  }

  /// One link per place, however often that place cites the same section: RFC 9601
  /// cites sections of the documents it updates twelve times, two of them repeats.
  @Test func `a section amending the same section twice is one link`() throws {
    let document = try Self.document("rfc9601.xml")
    let updated = Set(document.header.updates)
    let citations = document.proseInlines.filter { inline in
      guard case .crossReference(let xref) = inline,
        case .document(let id, _?) = xref.target
      else { return false }
      return updated.contains(id)
    }
    let links = Amendments.links(in: document)
    #expect(citations.count == 12)
    #expect(links.count == 10)
    #expect(Set(links).count == links.count)
  }

  /// A row that cannot say which document amends is no use to a reader asking which
  /// later documents amend the open one.
  @Test func `a document without a number amends nothing`() throws {
    var document = try Self.document("rfc9283.xml")
    document.header.id = nil
    #expect(Amendments.links(in: document).isEmpty)
  }
}
