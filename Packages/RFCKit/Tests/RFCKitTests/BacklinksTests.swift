import Testing

@testable import RFCKit

/// The sections of a document that refer to each of its sections (#183).
@Suite("Backlinks")
struct BacklinksTests {
  private static func rfc9290() throws -> RFCDocument {
    try RFCXMLParser.parse(try Fixtures.data("rfc9290.xml"))
  }

  /// RFC 9290 refers to its Section 3 from Sections 2 and 3.2, and twice from
  /// Section 5: once to the section, and once to a paragraph in it.
  @Test func `a section's backlinks are the sections that refer to it or into it`() throws {
    let backlinks = Backlinks.within(try Self.rfc9290())
    #expect(
      backlinks["sec-new-attributes"] == [
        Backlink(section: "basic", count: 1),
        Backlink(section: "new-cpdk", count: 1),
        Backlink(section: "seccons", count: 2),
      ])
    #expect(
      backlinks["seccons"] == [
        Backlink(section: "privcons", count: 1),
        Backlink(section: "media-type", count: 1),
      ])
  }

  /// A legacy document's `Section 3.1` in the prose resolves to the section, and is a
  /// backlink like an xref: RFC 1245 refers to Section 3.1 from 3.2 and 3.4, and to
  /// Section 3.2 from 3.5 and 3.6.
  @Test func `a legacy section reference is a backlink`() throws {
    let document = try Fixtures.document("rfc1245.txt")
    let backlinks = Backlinks.within(document)
    #expect(
      backlinks["section-3.1"] == [
        Backlink(section: "section-3.2", count: 1), Backlink(section: "section-3.4", count: 1),
      ])
    #expect(
      backlinks["section-3.2"] == [
        Backlink(section: "section-3.5", count: 1), Backlink(section: "section-3.6", count: 1),
      ])
  }

  /// The introduction of RFC 9290 refers to its own figure, and nothing else refers
  /// to it.
  @Test func `a section referring to itself is no backlink`() throws {
    #expect(Backlinks.within(try Self.rfc9290())["introduction"] == nil)
  }

  /// A citation names the work, not the bibliography row that lists it, and the
  /// reader does not show the bibliography in the body.
  @Test func `a citation is no backlink of the references section`() throws {
    let document = try Self.rfc9290()
    let backlinks = Backlinks.within(document)
    let bibliographies = document.allSections.filter(RFCXMLSerializer.isReferences)
    #expect(!bibliographies.isEmpty)
    #expect(bibliographies.allSatisfy { backlinks[$0.anchor] == nil })
  }

  private func refer(to anchor: String) -> Inline {
    .crossReference(CrossReference(target: .anchor(anchor)))
  }

  private func section(
    _ anchor: String, _ blocks: [Block], subsections: [Section] = []
  ) -> Section {
    Section(anchor: anchor, title: anchor, blocks: blocks, subsections: subsections)
  }

  /// A figure in a section counts for that section; a reference to a subsection is
  /// the subsection's, not its parent's; and so is a citation made in a subsection.
  @Test func `a reference counts for the section that holds its target`() {
    let figure = Block.figure(Figure(title: "F", blocks: [], anchor: "figure-1"))
    let document = RFCDocument(
      header: DocumentHeader(title: "T", abstract: [.paragraph(Paragraph([refer(to: "two")]))]),
      sections: [
        section(
          "one", [.paragraph(Paragraph([refer(to: "figure-1"), refer(to: "two-one")]))],
          subsections: [section("one-one", [.paragraph(Paragraph([refer(to: "two")]))])]),
        section("two", [figure], subsections: [section("two-one", [])]),
      ],
      source: .xml)
    let backlinks = Backlinks.within(document)
    #expect(
      backlinks["two"] == [
        Backlink(section: nil, count: 1),
        Backlink(section: "one", count: 1),
        Backlink(section: "one-one", count: 1),
      ])
    #expect(backlinks["two-one"] == [Backlink(section: "one", count: 1)])
    #expect(backlinks["one"] == nil)
    #expect(backlinks["figure-1"] == nil, "keyed by the section, not the anchor referred to")
  }

  /// A section with prose beside its bibliography is drawn in the body, so it is
  /// referred to and refers like any other; the rows of its bibliography are not
  /// drawn, so an annotation's reference is no backlink. A section that is only a
  /// bibliography cites nothing, and nor does a `References` parent over
  /// bibliographies, even from its heading: the reader draws neither.
  @Test func `only a bibliography's rows and a bibliography alone are left out`() {
    let entries = Block.references(
      ReferenceList(
        title: "R",
        entries: [Reference(anchor: "REF", title: "W", annotation: [refer(to: "one")])]))
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        section("one", [.paragraph(Paragraph([refer(to: "mixed"), refer(to: "REF")]))]),
        section("mixed", [.paragraph(Paragraph([refer(to: "one")])), entries]),
        section("bibliography", [entries]),
        Section(
          anchor: "references", title: [refer(to: "one")],
          subsections: [section("normative", [entries])]),
      ],
      source: .text)
    let backlinks = Backlinks.within(document)
    #expect(backlinks["mixed"] == [Backlink(section: "one", count: 1)])
    #expect(
      backlinks["one"] == [Backlink(section: "mixed", count: 1)],
      "the mixed section's prose; not its annotation, the bibliography's or the parent's heading")
    #expect(backlinks["REF"] == nil && backlinks["bibliography"] == nil)
  }

  /// A reference to an anchor nothing in the document carries lands nowhere.
  @Test func `a reference to no anchor in the document is no backlink`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [section("one", [.paragraph(Paragraph([refer(to: "missing")]))])],
      source: .xml)
    #expect(Backlinks.within(document).isEmpty)
  }
}
