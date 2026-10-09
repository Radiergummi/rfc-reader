import Foundation
import Testing

@testable import RFCKit

/// Which sections of other RFCs a document amends: a citation of a section of a
/// document the updating one says it updates (#179).
@Suite("Amendments")
struct AmendmentsTests {
  /// RFC 9283 updates RFC 2850, and says where: Sections 1.2 and 2.
  @Test func `a section citation of an updated document is an amendment`() throws {
    let document = try Fixtures.document("rfc9283.xml")
    let links = Amendments.links(in: document)
    #expect(Set(links.map(\.section)) == ["1.2", "2"])
    #expect(links.allSatisfy { $0.amended == .rfc(2850) && $0.amending == .rfc(9283) })
    #expect(
      links.allSatisfy { $0.amendingSection != nil },
      "every citation sits in a section of the amending document")
  }

  /// RFC 9601 updates six documents and amends sections of four of them.
  @Test func `every amended document is one the document updates`() throws {
    let document = try Fixtures.document("rfc9601.xml")
    let links = Amendments.links(in: document)
    #expect(Set(links.map(\.amended)).isSubset(of: Set(document.header.updates)))
    #expect(links.contains { $0.amended == .rfc(6040) && $0.section == "4.3" })
    #expect(links.contains { $0.amended == .rfc(7450) && $0.section == "5.1.3.3" })
  }

  /// A section of a document it only cites is not amended: RFC 9601 cites
  /// Section 5.3 of RFC 3168, which it does not update, and that is no link.
  @Test func `a section citation of any other document is not an amendment`() throws {
    let document = try Fixtures.document("rfc9601.xml")
    #expect(!document.header.updates.contains(.rfc(3168)))
    let citesRFC3168 = document.proseInlines.contains { inline in
      guard case .crossReference(let xref) = inline,
        case .document(.rfc(3168), "5.3", _) = xref.target
      else { return false }
      return true
    }
    #expect(citesRFC3168, "the fixture must cite a section of a document it does not update")
    #expect(!Amendments.links(in: document).contains { $0.amended == .rfc(3168) })
  }

  /// A document that updates nothing amends nothing, however many sections it
  /// cites: RFC 9290 cites sections of other documents and updates none.
  @Test func `a document that updates nothing amends nothing`() throws {
    let document = try Fixtures.document("rfc9290.xml")
    #expect(document.header.updates.isEmpty)
    let citesASection = document.proseInlines.contains { inline in
      guard case .crossReference(let xref) = inline,
        case .document(_, _?, _) = xref.target
      else { return false }
      return true
    }
    #expect(citesASection, "the fixture must cite a section of another document")
    #expect(Amendments.links(in: document).isEmpty)
  }

  /// One link per place, however often that place cites the same section: RFC 9601
  /// cites a section of a document it updates twice in one of its own sections.
  @Test func `a section amending the same section twice is one link`() throws {
    let document = try Fixtures.document("rfc9601.xml")
    let updated = Set(document.header.updates)
    let citedByPlace = document.proseInlinesBySection.map { place in
      let cited = place.inlines.compactMap { inline -> String? in
        guard case .crossReference(let xref) = inline,
          case .document(let id, let section?, _) = xref.target,
          updated.contains(id)
        else { return nil }
        return "\(id.fileStem) \(section)"
      }
      return (anchor: place.sectionAnchor, cited: cited)
    }
    let repeating = try #require(
      citedByPlace.first { Set($0.cited).count < $0.cited.count },
      "the fixture must cite a section of an updated document twice in one place")
    let links = Amendments.links(in: document).filter { $0.amendingSection == repeating.anchor }
    #expect(links.count == Set(repeating.cited).count)
  }

  /// A bibliography entry's note describes the entry, and amends nothing: a section
  /// of an updated document cited in one is no link. RFC 9283's references carry no
  /// note, so the test gives one of them a citation of RFC 2850's Section 3, a
  /// section the document cites nowhere else.
  @Test func `a section citation in a reference annotation is not an amendment`() throws {
    var document = try Fixtures.document("rfc9283.xml")
    let citation = Inline.crossReference(
      CrossReference(target: .document(.rfc(2850), section: "3")))
    let index = try #require(
      document.sections.firstIndex { section in
        section.blocks.contains { if case .references = $0 { true } else { false } }
      })
    document.sections[index].blocks = document.sections[index].blocks.map { block in
      guard case .references(var list) = block else { return block }
      list.entries[0].annotation = [.text("See "), citation]
      return .references(list)
    }
    #expect(document.proseInlines.contains(citation))
    #expect(!Amendments.links(in: document).contains { $0.section == "3" })
  }

  // MARK: Series (#417)

  /// RFC 9283 with a citation of `section` of `series` in its first section, and the
  /// RFCs it updates replaced by `updates`, where given.
  static func citingSeries(
    _ series: DocumentID, section: String, updates: [DocumentID]? = nil
  ) throws -> RFCDocument {
    var document = try Fixtures.document("rfc9283.xml")
    if let updates { document.header.updates = updates }
    document.sections[0].blocks.append(
      .paragraph(
        Paragraph([
          .text("See "),
          .crossReference(CrossReference(target: .document(series, section: section))),
        ])))
    return document
  }

  static let bcp = DocumentID(series: .bcp, number: 999)

  /// A BCP or STD names no RFC, so a citation of its section counts as one of the RFCs
  /// it holds that the document updates.
  @Test func `a section of a series of one updated RFC is that RFC's`() throws {
    let document = try Self.citingSeries(Self.bcp, section: "7")
    let links = Amendments.links(in: document) { $0 == Self.bcp ? [.rfc(2850)] : [] }
    #expect(links.contains { $0.amended == .rfc(2850) && $0.section == "7" })
    #expect(!links.contains { $0.amended == Self.bcp })
    #expect(!Amendments.links(in: document).contains { $0.section == "7" }, "no members, no link")
  }

  /// Of a series of several, the one member the document updates is the one amended.
  @Test func `a section of a series is the one member the document updates`() throws {
    let document = try Self.citingSeries(Self.bcp, section: "7")
    let links = Amendments.links(in: document) { _ in [.rfc(2850), .rfc(8000)] }
    #expect(links.contains { $0.amended == .rfc(2850) && $0.section == "7" })
  }

  /// Two members it updates could each be the one meant, and neither is guessed at.
  @Test func `a section of a series with two updated members amends neither`() throws {
    let document = try Self.citingSeries(
      Self.bcp, section: "7", updates: [.rfc(2850), .rfc(8000)])
    let links = Amendments.links(in: document) { _ in [.rfc(2850), .rfc(8000)] }
    #expect(!links.contains { $0.section == "7" })
  }

  /// A series whose members the document does not update is an ordinary citation.
  @Test func `a section of a series the document updates nothing of amends nothing`() throws {
    let document = try Self.citingSeries(Self.bcp, section: "7")
    let links = Amendments.links(in: document) { _ in [.rfc(8000)] }
    #expect(!links.contains { $0.section == "7" })
  }

  /// A row that cannot say which document amends is no use to a reader asking which
  /// later documents amend the open one.
  @Test func `a document without a number amends nothing`() throws {
    var document = try Fixtures.document("rfc9283.xml")
    document.header.id = nil
    #expect(Amendments.links(in: document).isEmpty)
  }
}
