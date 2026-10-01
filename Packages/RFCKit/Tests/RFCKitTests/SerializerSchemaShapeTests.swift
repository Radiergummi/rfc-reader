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
  private static func converted(_ name: String) throws -> (RFCDocument, XMLTree.Element) {
    let document = LegacyTextParser.parse(try Fixtures.data(name))
    let xml = RFCXMLSerializer().serialize(document)
    return (document, try XMLTree.parse(Data(xml.utf8)))
  }

  /// Every ID the schema declares below `element`, as `SchemaCheck` counts them: each
  /// element's `anchor`, `pn` and `slugifiedName`, once per element.
  private static func declaredIDs(in element: XMLTree.Element) -> [String] {
    element.elements.flatMap { child -> [String] in
      let own = Set([child["anchor"], child["pn"], child["slugifiedName"]].compactMap { $0 })
      return own.sorted() + declaredIDs(in: child)
    }
  }

  /// RFC 2023 ends with an appendix before its references, and RFC 338 has only an
  /// appendix and references, so the back began at the appendix and held a
  /// section before its references.
  @Test(arguments: ["rfc2023.txt", "rfc338.txt"])
  func `the back holds its references first`(fixture: String) throws {
    let (_, rfc) = try Self.converted(fixture)
    let back = try #require(rfc.first("back"))
    let kinds = back.elements.map(\.name)
    let firstSection = kinds.firstIndex(of: "section") ?? kinds.count
    #expect(!kinds[firstSection...].contains("references"), "\(kinds)")
  }

  /// Every element named `name` at or below `element`.
  private static func nested(_ name: String, in element: XMLTree.Element) -> [XMLTree.Element] {
    element.elements.flatMap { child in
      (child.name == name ? [child] : []) + nested(name, in: child)
    }
  }

  /// RFC 2511's `9. References` is followed by its acknowledgements, its authors and
  /// its appendices, one of which holds references of its own, so the back begins
  /// after it. The schema has room for a `<references>` in `<back>` only, so it is
  /// lifted there, keeping its anchor, number and name (#315). The `[HMAC]` its prose
  /// cites is still RFC 2104 on a round trip, and the section reads back as the one
  /// references section it was, not as a section holding a second one.
  @Test func `a references section ahead of the back is lifted into it and still resolves`()
    throws
  {
    let (document, rfc) = try Self.converted("rfc2511.txt")
    let middle = try #require(rfc.first("middle"))
    #expect(Self.nested("references", in: middle).isEmpty)
    let back = try #require(rfc.first("back"))
    #expect(back.all("references").contains { $0["pn"] == "section-9" })
    #expect(
      Self.nested("section", in: back).allSatisfy {
        Self.nested("references", in: $0).isEmpty
      })

    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    let cited = { (document: RFCDocument) in
      document.everyCrossReference.compactMap { xref -> DocumentID? in
        if case .document(let id, _, _) = xref.target { id } else { nil }
      }
    }
    #expect(cited(document).contains(.rfc(2104)))
    #expect(cited(reparsed) == cited(document))
    // Every section reads back, once and with its number, a lifted one at the end of
    // the document rather than where it stood; the rest in their order, each with the
    // subsections it had but its bibliographies.
    let outline = { (document: RFCDocument) in
      document.allSections.map { "\($0.anchor) \($0.number, default: "-")" }.sorted()
    }
    #expect(outline(reparsed) == outline(document))
    let chapters = { (document: RFCDocument) in
      document.allSections.filter { !RFCXMLSerializer.isReferences($0) }.map { section in
        let kept = section.subsections.count { !RFCXMLSerializer.isReferences($0) }
        return "\(section.anchor) \(kept)"
      }
    }
    #expect(chapters(reparsed) == chapters(document))
    let bibliographies = { (document: RFCDocument) in
      document.allSections.filter(RFCXMLSerializer.isReferences).map { section in
        "\(section.anchor) \(section.subsections.count)"
      }.sorted()
    }
    #expect(bibliographies(reparsed) == bibliographies(document))
  }

  // MARK: Bibliographies outside the back

  private static func entry(_ anchor: String) -> Reference {
    Reference(anchor: anchor, title: "Entry \(anchor)")
  }

  private static func serialized(_ sections: [Section]) throws -> XMLTree.Element {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"), sections: sections, source: .text)
    return try XMLTree.parse(Data(RFCXMLSerializer().serialize(document).utf8))
  }

  /// A bibliography under a section, as a subsection of References or under an
  /// appendix, is lifted into the back after its own references, keeping its anchor,
  /// number and name, and the prose of the section it stood in stays where it was
  /// (#315).
  @Test func `a bibliography under a section is lifted into the back`() throws {
    var chapter = Self.chapter("1")
    chapter.blocks = [.paragraph(Paragraph([.text("Prose.")]))]
    chapter.subsections = [Self.references("1.3", entries: ["B"])]
    var appendix = Self.appendix("A")
    appendix.blocks = [.paragraph(Paragraph([.text("More prose.")]))]
    appendix.subsections = [Self.references("A.2", entries: ["C"])]
    let rfc = try Self.serialized([chapter, Self.references("2", entries: ["A"]), appendix])

    let middle = try #require(rfc.first("middle"))
    #expect(Self.nested("references", in: middle).isEmpty)
    #expect(Self.nested("t", in: middle).contains { $0.text == "Prose." })
    let back = try #require(rfc.first("back"))
    #expect(back.elements.map(\.name) == ["references", "references", "references", "section"])
    #expect(
      back.all("references").map { $0["pn"] } == ["section-1.3", "section-2", "section-A.2"])
    #expect(back.all("references")[0].first("name")?.text == "References 1.3")
    #expect(Self.nested("references", in: try #require(back.first("section"))).isEmpty)
  }

  /// A lifted bibliography is written after the sections that follow it, and a later
  /// section numbered like it took its part number first: that `pn` then declared
  /// the ID the lifted list's anchor declared as well. Part numbers go to the first
  /// section in the document, however it is written.
  @Test func `a lifted bibliography keeps its part number from a later section of its number`()
    throws
  {
    var later = Self.chapter("11")
    later.anchor = "section-11-2"
    let rfc = try Self.serialized([
      Self.chapter("1"), Self.references("11", entries: ["B"]), later,
      Self.references("12", entries: ["C"]),
    ])
    let ids = Self.declaredIDs(in: rfc)
    #expect(ids.count == Set(ids).count, "\(ids)")
    #expect(rfc.first("back")?.all("references").map { $0["pn"] } == ["section-11", "section-12"])
  }

  /// A list holding entries beside nested lists is the one shape the schema refuses
  /// there: its own entries go in a nested `<references>` named after it.
  @Test func `entries beside nested lists are wrapped in a list of their own`() throws {
    let parent = Self.references(
      "3", entries: ["A", "B"], subsections: [Self.references("3.1", entries: ["C"])])
    let rfc = try Self.serialized([Self.chapter("1"), parent])
    let list = try #require(rfc.first("back")?.first("references"))
    #expect(list.all("reference").isEmpty)
    let nested = list.all("references")
    #expect(nested.count == 2)
    #expect(nested.first?["anchor"] == "section-3-entries")
    #expect(nested.first?.first("name")?.text == "References 3")
    #expect(nested.first?.all("reference").map { $0["anchor"] } == ["A", "B"])
    #expect(nested.last?["pn"] == "section-3.1")
  }

  /// The wrapper repeats its list's name as written, the number too when a section
  /// numbered alike took the list's part number and it is written unnumbered.
  @Test func `a wrapper is named as its list is`() throws {
    var repeated = Self.references(
      "3", entries: ["B"], subsections: [Self.references("3.1", entries: ["C"])])
    repeated.anchor = "section-3-2"
    let rfc = try Self.serialized([
      Self.chapter("1"), Self.references("3", entries: ["A"]), repeated,
    ])
    let list = try #require(rfc.first("back")?.all("references").last)
    #expect(list["pn"] == nil)
    let wrapper = try #require(list.all("references").first)
    #expect(wrapper["anchor"] == "section-3-2-entries")
    #expect(wrapper.first("name")?.text == list.first("name")?.text)
  }

  /// RFC 338's first chapter, `I.`, reads as an appendix, which left the middle
  /// empty.
  @Test(arguments: ["rfc338.txt", "rfc2023.txt", "rfc1.txt", "rfc391.txt"])
  func `the middle holds a section`(fixture: String) throws {
    let (_, rfc) = try Self.converted(fixture)
    let middle = try #require(rfc.first("middle"))
    #expect(!middle.all("section").isEmpty)
  }

  /// RFC 1 has two appendices A. The second is written unnumbered, with its number
  /// in its name, so no `pn` is declared twice and it reads the same.
  @Test func `no two sections share a part number`() throws {
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

  /// An abstract that holds artwork, as RFC 391's statistics table once did, may not
  /// be written as `<abstract>`. It is written as the body's first section instead,
  /// whole. A model built here, because the parser no longer reads RFC 391's abstract
  /// so: the table's rows were headings that cut it short (#427).
  @Test func `an abstract holding artwork becomes the first section`() throws {
    var header = DocumentHeader(title: "T")
    header.abstract = [
      .paragraph(Paragraph([.text("Attached are the figures.")])),
      .preformatted(Preformatted(kind: .artwork, text: "WIDGET  HOST 1   1200")),
    ]
    let document = RFCDocument(header: header, sections: [Self.chapter("1")], source: .text)
    let rfc = try XMLTree.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    #expect(rfc.first("front")?.first("abstract") == nil)
    let first = try #require(rfc.first("middle")?.first("section"))
    #expect(first["anchor"] == "abstract")
    #expect(!first.all("artwork").isEmpty)
  }

  /// A document whose abstract fits keeps it where it was.
  @Test func `an abstract that fits stays in the front`() throws {
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

  private static func references(
    _ number: String, entries: [String] = [], subsections: [Section] = []
  ) -> Section {
    Section(
      anchor: "section-\(number)", number: number, title: "References \(number)",
      blocks: [.references(ReferenceList(title: "References", entries: entries.map(entry)))],
      subsections: subsections)
  }

  /// The back is the last run of references sections and everything after it.
  /// Whatever comes before that run stays in the middle, an appendix or an earlier
  /// references section among it.
  @Test func `the back starts at the last run of references`() {
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
  @Test func `without references the back is the trailing appendices`() {
    #expect(
      RFCXMLSerializer.backStart([
        Self.chapter("1"), Self.appendix("A"), Self.chapter("2"), Self.appendix("B"),
      ]) == 3)
    #expect(RFCXMLSerializer.backStart([Self.chapter("1"), Self.chapter("2")]) == 2)
    #expect(RFCXMLSerializer.backStart([Self.appendix("A"), Self.appendix("B")]) == 2)
    #expect(RFCXMLSerializer.backStart([]) == 0)
  }
}
