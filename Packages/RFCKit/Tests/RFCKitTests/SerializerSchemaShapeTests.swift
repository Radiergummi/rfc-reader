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

  /// Every ID the schema declares below `element`, as `SchemaCheck` counts them: each
  /// element's `anchor`, `pn` and `slugifiedName`, once per element.
  private static func declaredIDs(in element: RFCKit.XMLElement) -> [String] {
    element.elements.flatMap { child -> [String] in
      let own = Set([child["anchor"], child["pn"], child["slugifiedName"]].compactMap { $0 })
      return own.sorted() + declaredIDs(in: child)
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

  /// RFC 2511's `9. References` is followed by its acknowledgements, its authors and
  /// its appendices, one of which holds references of its own, so the back begins
  /// after it and it is written in the middle. The `[HMAC]` its prose cites is RFC
  /// 2104 only while the parser reads reference lists wherever they sit, and the
  /// section reads back as the one references section it was, not as a section
  /// holding a second one.
  @Test func aReferencesSectionAheadOfTheBackStillResolves() throws {
    let (document, rfc) = try Self.converted("rfc2511.txt")
    let middle = try #require(rfc.first("middle"))
    #expect(middle.elements.contains { $0.name == "references" && $0["pn"] == "section-9" })

    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    let cited = { (document: RFCDocument) in
      document.everyCrossReference.compactMap { xref -> DocumentID? in
        if case .document(let id, _) = xref.target { id } else { nil }
      }
    }
    #expect(cited(document).contains(.rfc(2104)))
    #expect(cited(reparsed) == cited(document))
    let outline = { (document: RFCDocument) in
      document.allSections.map { "\($0.anchor) \($0.number ?? "-") \($0.subsections.count)" }
    }
    #expect(outline(reparsed) == outline(document))
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
    let ids = Self.declaredIDs(in: rfc)
    #expect(ids.count == Set(ids).count)

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
    #expect(!first.all("artwork").isEmpty)
  }

  /// A document whose abstract fits keeps it where it was.
  @Test func anAbstractThatFitsStaysInTheFront() throws {
    let (_, rfc) = try Self.converted("rfc2119.txt")
    #expect(rfc.first("front")?.first("abstract") != nil)
  }

  // MARK: Where the back starts

  private static func chapter(_ number: String) -> Section {
    Section(anchor: "section-\(number)", number: number, title: "Chapter")
  }

  private static func appendix(_ number: String) -> Section {
    Section(anchor: "appendix-\(number)", number: number, title: "Appendix", isAppendix: true)
  }

  private static func references(_ number: String) -> Section {
    Section(
      anchor: "section-\(number)", number: number, title: "References",
      blocks: [.references(ReferenceList(title: "References", entries: []))])
  }

  /// The back is the last run of references sections and everything after it.
  /// Whatever comes before that run stays in the middle, an appendix or an earlier
  /// references section among it.
  @Test func theBackStartsAtTheLastRunOfReferences() {
    #expect(RFCXMLSerializer.backStart([Self.chapter("1"), Self.references("2")]) == 1)
    #expect(
      RFCXMLSerializer.backStart([
        Self.chapter("1"), Self.references("2"), Self.references("3"),
      ]) == 1)
    #expect(
      RFCXMLSerializer.backStart([
        Self.chapter("1"), Self.references("2"), Self.appendix("A"), Self.appendix("B"),
      ]) == 1)
    #expect(
      RFCXMLSerializer.backStart([
        Self.chapter("1"), Self.references("2"), Self.appendix("A"), Self.references("B"),
      ]) == 3)
  }

  /// With no references, the back is the appendices the document ends with, and
  /// there is none when they are all it has, or it has nothing.
  @Test func withoutReferencesTheBackIsTheTrailingAppendices() {
    #expect(
      RFCXMLSerializer.backStart([
        Self.chapter("1"), Self.appendix("A"), Self.chapter("2"), Self.appendix("B"),
      ]) == 3)
    #expect(RFCXMLSerializer.backStart([Self.chapter("1"), Self.chapter("2")]) == 2)
    #expect(RFCXMLSerializer.backStart([Self.appendix("A"), Self.appendix("B")]) == 2)
    #expect(RFCXMLSerializer.backStart([]) == 0)
  }
}
