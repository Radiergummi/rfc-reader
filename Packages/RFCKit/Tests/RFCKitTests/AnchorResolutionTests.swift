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
    var anchors: Set<String> = []
    func insert(_ anchor: String?) {
      if let anchor { anchors.insert(anchor) }
    }
    func visit(_ blocks: [Block]) {
      for block in blocks {
        switch block {
        case .paragraph(let paragraph): insert(paragraph.anchor)
        case .list(let list):
          for item in list.items {
            insert(item.anchor)
            visit(item.blocks)
          }
        case .definitionList(let items):
          for item in items {
            insert(item.anchor)
            insert(item.definitionAnchor)
            visit(item.definition)
          }
        case .preformatted(let content): insert(content.anchor)
        case .figure(let figure):
          insert(figure.anchor)
          visit(figure.blocks)
        case .table(let table):
          insert(table.anchor)
          table.rowAnchors.forEach(insert)
        case .blockQuote(let inner), .aside(let inner): visit(inner)
        case .references(let list):
          for entry in list.entries { insert(entry.anchor) }
        }
      }
    }
    visit(document.header.abstract)
    for section in document.allSections {
      insert(section.anchor)
      visit(section.blocks)
    }
    return anchors
  }

  /// Every anchor a cross reference in the document's prose points at.
  static func citedAnchors(in document: RFCDocument) -> Set<String> {
    var cited: Set<String> = []
    func visit(_ inlines: [Inline]) {
      for inline in inlines {
        switch inline {
        case .crossReference(let xref):
          if case .anchor(let anchor) = xref.target { cited.insert(anchor) }
        case .emphasis(let inner), .strong(let inner), .link(_, let inner): visit(inner)
        default: break
        }
      }
    }
    func visit(_ blocks: [Block]) {
      for block in blocks {
        switch block {
        case .paragraph(let paragraph): visit(paragraph.inlines)
        case .list(let list):
          for item in list.items { visit(item.blocks) }
        case .definitionList(let items):
          for item in items {
            visit(item.term)
            visit(item.definition)
          }
        case .figure(let figure): visit(figure.blocks)
        case .table(let table): (table.header + table.rows).joined().forEach(visit)
        case .blockQuote(let inner), .aside(let inner): visit(inner)
        case .preformatted, .references: break
        }
      }
    }
    visit(document.header.abstract)
    for section in document.allSections {
      visit(section.title)
      visit(section.blocks)
    }
    return cited
  }

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

  /// The serializer writes both back, so a round trip keeps the links whole.
  @Test(arguments: ["rfc9197.xml", "rfc9271.xml"])
  func theAnchorsSurviveARoundTrip(fixture: String) throws {
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let xml = RFCXMLSerializer().serialize(document)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(Self.anchors(in: reparsed).isSuperset(of: Self.citedAnchors(in: document)))
  }
}
