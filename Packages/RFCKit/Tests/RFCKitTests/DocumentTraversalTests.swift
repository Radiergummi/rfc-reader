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
  /// list item, a table cell, a definition's term, a figure, a subsection, and a
  /// bibliography entry with an annotation.
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
              Table(title: nil, header: [], rows: [[[.text("cell "), cite(4)]]])),
            .definitionList([
              DefinitionItem(
                term: [.text("term "), cite(5)],
                definition: [.paragraph(Paragraph(text: "definition"))])
            ]),
            .figure(
              Figure(title: "F", blocks: [.preformatted(Preformatted(kind: .artwork, text: "+-+"))])
            ),
          ],
          subsections: [
            Section(
              anchor: "s1.1", number: "1.1", title: "Sub",
              blocks: [.paragraph(Paragraph([.emphasis([.strong([cite(6)])])]))])
          ]),
        Section(
          anchor: "s2", number: "2", title: "References",
          blocks: [
            .references(
              ReferenceList(
                title: "Normative",
                entries: [
                  Reference(
                    anchor: "RFC7", title: "Seven", seriesInfo: [(name: "RFC", value: "7")],
                    annotation: [.text("see "), cite(8)])
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
    }
  }

  @Test func `every block comes in document order, the abstract first, nesting depth first`() {
    #expect(
      document.blocks.map(label) == [
        "p:abstract ", "list", "p:item ", "table", "definitions", "p:definition", "figure",
        "artwork", "p:", "references",
      ])
  }

  /// Everywhere a reader sees prose: the headings, and every block's own runs,
  /// with the words inside emphasis and strong text flattened out.
  @Test func `every run of prose is reached, headings included`() {
    let cited = document.proseInlines.compactMap { inline -> Int? in
      guard case .crossReference(let xref) = inline, case .document(let id, _) = xref.target else {
        return nil
      }
      return id.number
    }
    #expect(cited == [1, 2, 3, 4, 5, 6, 8])
  }

  @Test func `referenced documents come from everywhere, bibliography included`() {
    #expect(document.referencedDocuments.map(\.number) == [1, 2, 3, 4, 5, 6, 7, 8])
  }

  @Test func `a section is found by anchor or number at any depth`() {
    #expect(document.section(anchor: "s1.1")?.number == "1.1")
    #expect(document.section(number: "2")?.anchor == "s2")
    #expect(document.section(anchor: "missing") == nil)
  }
}
