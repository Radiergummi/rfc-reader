import Testing

@testable import RFCKit

/// One traversal of the whole document (#131): every block, and every run of prose,
/// in document order, so a question asked of the whole model cannot miss a place
/// the way #127's walk missed the headings.
@Suite("Document traversal")
struct DocumentTraversalTests {
  private func cite(_ number: Int) -> Inline {
    .crossReference(CrossReference(target: .document(.rfc(number), section: nil)))
  }

  /// One of each thing, in each place it can be: the abstract, a heading, a nested
  /// list item, a table's header and body cells, a definition's term, a figure, a
  /// block quote, an aside, a subsection, and a bibliography entry with an annotation.
  private var document: RFCDocument {
    RFCDocument(
      header: DocumentHeader(
        title: "T", abstract: [.paragraph(Paragraph([.text("abstract "), cite(1)]))]),
      sections: [
        Section(
          anchor: "s1", number: "1", title: [.text("Heading "), cite(2)],
          blocks: [
            .list(
              ListBlock(
                style: .bullet,
                items: [ListItem(blocks: [.paragraph(Paragraph([.text("item "), cite(3)]))])])),
            .table(
              Table(
                title: nil, header: [Table.Row(cells: [[.text("head "), cite(4)]])],
                rows: [Table.Row(cells: [[.text("cell "), cite(5)]])])),
            .definitionList(
              DefinitionList([
                DefinitionItem(
                  term: [.text("term "), cite(6)],
                  definition: [.paragraph(Paragraph(text: "definition"))])
              ])),
            .figure(
              Figure(title: "F", blocks: [.preformatted(Preformatted(kind: .artwork, text: "+-+"))])
            ),
            .blockQuote([.paragraph(Paragraph([.text("quote "), cite(7)]))]),
            .aside([.paragraph(Paragraph([.text("aside "), cite(8)]))]),
          ],
          subsections: [
            Section(
              anchor: "s1.1", number: "1.1", title: "Sub",
              blocks: [.paragraph(Paragraph([.emphasis([.strong([cite(9)])])]))])
          ]),
        Section(
          anchor: "s2", number: "2", title: "References",
          blocks: [
            .references(
              ReferenceList(
                title: "Normative",
                entries: [
                  Reference(
                    anchor: "RFC10", title: "Ten",
                    seriesInfo: [SeriesInfo(name: "RFC", value: "10")],
                    annotation: [.text("see "), cite(11)])
                ]))
          ]),
      ],
      source: .xml)
  }

  private func label(_ block: Block) -> String {
    switch block {
    // The literal words only: a cross reference's label is not the test's to spell.
    case .paragraph(let paragraph):
      "p:"
        + paragraph.inlines.compactMap { if case .text(let text) = $0 { text } else { nil } }
        .joined()
    case .list: "list"
    case .definitionList: "definitions"
    case .preformatted: "artwork"
    case .figure: "figure"
    case .table: "table"
    case .blockQuote: "quote"
    case .aside: "aside"
    case .references: "references"
    case .index: "index"
    }
  }

  @Test func `every block comes in document order, the abstract first, nesting depth first`() {
    #expect(
      document.blocks.map(label) == [
        "p:abstract ", "list", "p:item ", "table", "definitions", "p:definition", "figure",
        "artwork", "quote", "p:quote ", "aside", "p:aside ", "p:", "references",
      ])
  }

  /// Everywhere a reader sees prose: the headings, and every block's own runs,
  /// with the words inside emphasis and strong text flattened out.
  @Test func `every run of prose is reached, headings included`() {
    let cited = document.proseInlines.compactMap { inline -> Int? in
      guard case .crossReference(let xref) = inline, case .document(let id, _, _) = xref.target
      else {
        return nil
      }
      return id.number
    }
    #expect(cited == [1, 2, 3, 4, 5, 6, 7, 8, 9, 11])
  }

  @Test func `referenced documents come from everywhere, bibliography included`() {
    #expect(document.referencedDocuments.map(\.number) == Array(1...11))
  }

  @Test func `a section is found by anchor or number at any depth`() {
    #expect(document.section(anchor: "s1.1")?.number == "1.1")
    #expect(document.section(number: "2")?.anchor == "s2")
    #expect(document.section(anchor: "missing") == nil)
  }

  /// A link names a place by section number or by anchor, and the reader and the
  /// link preview must land on the same one (#29).
  @Test func `a place resolves to its section's anchor, or stands as an anchor`() {
    #expect(document.anchor(forPlace: "1.1") == "s1.1")
    #expect(document.anchor(forPlace: "s2") == "s2")
    #expect(document.anchor(forPlace: "figure-3") == "figure-3")
  }
}
