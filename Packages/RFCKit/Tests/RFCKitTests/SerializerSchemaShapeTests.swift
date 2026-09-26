import Foundation
import Testing

@testable import RFCKit

/// The shapes the RFCXML schema requires of a converted legacy document, which the
/// last four causes of #65 broke: `<back>` holds its references before its sections,
/// `<middle>` holds at least one section, no two sections share a `pn`, and
/// `<abstract>` holds paragraphs and lists only. Each is tested on a legacy RFC the
/// corpus's schema check named for it, through the parser and the serializer.
@Suite("Serializer: schema shape")
struct SerializerSchemaShapeTests {
  private static func converted(_ name: String) throws -> (RFCDocument, RFCKit.XMLElement) {
    let document = LegacyTextParser.parse(try Fixtures.data(name))
    let xml = RFCXMLSerializer().serialize(document)
    return (document, try XMLTreeBuilder.parse(Data(xml.utf8)))
  }

  private static func partNumbers(in element: RFCKit.XMLElement) -> [String] {
    element.elements.flatMap { child -> [String] in
      let own =
        ["section", "references"].contains(child.name) ? [child["pn"]].compactMap { $0 } : []
      return own + partNumbers(in: child)
    }
  }

  /// RFC 2023 ends with an appendix before its references, and RFC 338 has only an
  /// appendix and references, so the back began at the appendix and held a
  /// section before its references.
  @Test(arguments: ["rfc2023.txt", "rfc338.txt"])
  func theBackHoldsItsReferencesFirst(fixture: String) throws {
    let (_, rfc) = try Self.converted(fixture)
    let back = try #require(rfc.first("back"))
    let kinds = back.elements.map(\.name)
    let firstSection = kinds.firstIndex(of: "section") ?? kinds.count
    #expect(!kinds[firstSection...].contains("references"), "\(kinds)")
  }

  /// RFC 338's first chapter, `I.`, reads as an appendix, which left the middle
  /// empty.
  @Test(arguments: ["rfc338.txt", "rfc2023.txt", "rfc1.txt", "rfc391.txt"])
  func theMiddleHoldsASection(fixture: String) throws {
    let (_, rfc) = try Self.converted(fixture)
    let middle = try #require(rfc.first("middle"))
    #expect(!middle.all("section").isEmpty)
  }

  /// RFC 1 has two appendices A. The second is written unnumbered, with its number
  /// in its name, so no `pn` is declared twice and it reads the same.
  @Test func noTwoSectionsShareAPartNumber() throws {
    let (document, rfc) = try Self.converted("rfc1.txt")
    let partNumbers = Self.partNumbers(in: rfc)
    #expect(partNumbers.count == Set(partNumbers).count)

    // Whitespace inside a title collapses on the way back in, as it always has, so
    // compare what reads, not the spacing.
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    let titles = { (document: RFCDocument) in
      document.allSections.map { $0.displayTitle.collapsingWhitespace() }
    }
    #expect(titles(reparsed) == titles(document))
  }

  /// RFC 391's abstract holds its statistics table as artwork, which `<abstract>`
  /// may not. It is written as the body's first section instead, whole.
  @Test func anAbstractHoldingArtworkBecomesTheFirstSection() throws {
    let (document, rfc) = try Self.converted("rfc391.txt")
    #expect(
      document.header.abstract.contains {
        if case .preformatted = $0 { true } else { false }
      })
    #expect(rfc.first("front")?.first("abstract") == nil)
    let first = try #require(rfc.first("middle")?.first("section"))
    #expect(first["anchor"] == "abstract")
    #expect(first.all("artwork").count > 0)
  }

  /// A document whose abstract fits keeps it where it was.
  @Test func anAbstractThatFitsStaysInTheFront() throws {
    let (_, rfc) = try Self.converted("rfc2119.txt")
    #expect(rfc.first("front")?.first("abstract") != nil)
  }
}
