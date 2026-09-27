import Foundation
import Testing

@testable import RFCKit

/// Every in-document link has somewhere to land (#166). Anchors are the reader's key
/// for links, the table of contents and reading positions, so a cross reference to an
/// anchor no part of the model carries is a dead link. RFC 9197 cites anchors on
/// `<dd>`, and RFC 9271 one on a `<tr>`, which the model used to drop.
@Suite("Anchor resolution")
struct AnchorResolutionTests {
  /// Every anchor the model holds, anywhere in the document.
  static func anchors(in document: RFCDocument) -> Set<String> {
    Set(document.allSections.map(\.anchor) + document.blocks.flatMap(\.anchors))
  }

  /// Every anchor a cross reference in the document's prose points at.
  static func citedAnchors(in document: RFCDocument) -> Set<String> {
    Set(
      document.proseInlines.compactMap { inline in
        guard case .crossReference(let xref) = inline, case .anchor(let anchor) = xref.target
        else { return nil }
        return anchor
      })
  }

  /// The prepped XML also cites every section by its `pn` and by its heading's
  /// `slugifiedName` -- `section-4.2`, `name-introduction` -- which no part of the
  /// model holds for a section with an anchor of its own. Those links all sit in
  /// the pre-rendered `<toc>`, which the parser does not read: the reader builds
  /// its contents from the sections. Prose cites a section by its `anchor`, which
  /// the section keeps, so the invariant holds without an exception for either.
  @Test(arguments: [
    "rfc8761.xml", "rfc8771.xml", "rfc8999.xml", "rfc9197.xml", "rfc9220.xml", "rfc9271.xml",
    "rfc9682.xml",
  ])
  func everyCitedAnchorIsHeld(fixture: String) throws {
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let dangling = Self.citedAnchors(in: document).subtracting(Self.anchors(in: document))
    #expect(dangling.isEmpty, "cited but not held: \(dangling.sorted())")
  }

  @Test func aDefinitionKeepsItsOwnAnchor() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9197.xml"))
    let anchors = Self.anchors(in: document)
    #expect(anchors.contains("TraceFlags"))
    #expect(anchors.contains("IOAMTraceType"))
  }

  @Test func aRowKeepsItsAnchor() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9271.xml"))
    #expect(Self.anchors(in: document).contains("EventFSD"))
  }

  /// No RFC yet anchors a `<thead>` row, but the schema lets one, and a link to it
  /// should land as surely as a link to a body row. So RFC 9271's first table with
  /// a header is given one, and the anchor has to come back through the serializer
  /// and the parser on the header row, not on a body row.
  @Test func aHeaderRowKeepsItsAnchor() throws {
    var document = try RFCXMLParser.parse(try Fixtures.data("rfc9271.xml"))
    func anchorFirstHeaderRow(in sections: inout [Section]) -> Bool {
      for section in sections.indices {
        for index in sections[section].blocks.indices {
          guard case .table(var table) = sections[section].blocks[index], !table.header.isEmpty
          else { continue }
          table.headerRowAnchors = ["cited-header"]
          sections[section].blocks[index] = .table(table)
          return true
        }
        if anchorFirstHeaderRow(in: &sections[section].subsections) { return true }
      }
      return false
    }
    try #require(anchorFirstHeaderRow(in: &document.sections))

    let xml = RFCXMLSerializer().serialize(document)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    let tables = reparsed.allSections.flatMap(\.blocks).flattened.compactMap { block -> Table? in
      if case .table(let table) = block { return table }
      return nil
    }
    let table = try #require(tables.first { $0.anchor(ofHeaderRow: 0) == "cited-header" })
    #expect(table.headerRowAnchors == ["cited-header"])
    #expect(!table.rowAnchors.contains("cited-header"))
    #expect(Self.anchors(in: reparsed).contains("cited-header"))
  }

  /// The serializer writes both back, so a round trip keeps the links whole.
  @Test(arguments: ["rfc9197.xml", "rfc9271.xml"])
  func theAnchorsSurviveARoundTrip(fixture: String) throws {
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let xml = RFCXMLSerializer().serialize(document)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(Self.anchors(in: reparsed).isSuperset(of: Self.citedAnchors(in: document)))
  }
}
