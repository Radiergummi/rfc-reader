import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The model text, element by element, as the design fixes it (#522).
@Suite("Annotations: the model text")
struct ModelTextTests {
  private func text(_ blocks: Block..., anchor: String = "section-1") -> String {
    let model = ModelText(
      RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [Section(anchor: anchor, number: "1", title: "Heading", blocks: blocks)],
        source: .xml))
    return model.text(in: 0..<model.length)
  }

  private func model(_ block: Block) -> ModelText {
    ModelText(Fixtures.document(block))
  }

  @Test func `a heading is its title, never its number`() {
    #expect(text() == "Heading\n")
  }

  @Test func `a paragraph is its inlines, a reference as its derived text`() {
    let reference = Inline.crossReference(
      CrossReference(target: .document(.rfc(9110), section: nil)))
    #expect(
      text(
        .paragraph(Paragraph([.text("See "), .emphasis([.text("this")]), .text(" "), reference])))
        == "Heading\nSee this RFC\u{00A0}9110")
  }

  @Test func `a list is its items joined by newlines, with no markers`() {
    let list = ListBlock(
      style: .bullet, items: [ListItem(text: "one"), ListItem(text: "two")])
    #expect(text(.list(list)) == "Heading\none\ntwo")
  }

  @Test func `a definition is its term, a newline, then its definition`() {
    let list = DefinitionList([
      DefinitionItem(
        term: [.text("term")], definition: [.paragraph(Paragraph(text: "means"))], anchor: "dt",
        definitionAnchor: "dd")
    ])
    let model = model(.definitionList(list))
    #expect(model.text(in: model.span(of: "dt")!.range) == "term\nmeans")
    #expect(model.text(in: model.span(of: "dd")!.range) == "means")
  }

  @Test func `verbatim text is as published, folds and all`() {
    let folded = Fixtures.folded(String(repeating: "x", count: 70))
    let model = model(.preformatted(folded))
    #expect(model.text(in: model.span(of: "folded")!.range) == folded.text)
  }

  @Test func `a figure is its title, a newline, then its artwork`() {
    let figure = Figure(
      title: "Layout", number: 1,
      blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))], anchor: "figure-1")
    let model = model(.figure(figure))
    #expect(model.text(in: model.span(of: "figure-1")!.range) == "Layout\n+--+")
  }

  @Test func `a table is its rows, cells joined by tabs, the header first`() {
    let table = RFCKit.Table(
      title: "Codes", number: 1,
      header: [Table.Row(cells: [[.text("Code")], [.text("Meaning")]])],
      rows: [Table.Row(cells: [[.text("1")], [.text("one")]], anchor: "row-1")],
      anchor: "table-1")
    let model = model(.table(table))
    #expect(model.text(in: model.span(of: "table-1")!.range) == "Code\tMeaning\n1\tone")
    #expect(model.text(in: model.span(of: "row-1")!.range) == "1\tone")
  }

  @Test func `a quotation and an aside are their blocks`() {
    #expect(
      text(
        .blockQuote([.paragraph(Paragraph(text: "a")), .paragraph(Paragraph(text: "b"))]),
        .aside([.paragraph(Paragraph(text: "Note: c"))]))
        == "Heading\na\nb\nNote: c")
  }

  @Test func `a section holds its anchored blocks and not its subsections`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "One",
          blocks: [.paragraph(Paragraph(text: "first", anchor: "p-1"))],
          subsections: [
            Section(
              anchor: "section-1.1", number: "1.1", title: "Sub",
              blocks: [.paragraph(Paragraph(text: "inner"))])
          ])
      ], source: .xml)
    let model = ModelText(document)
    #expect(model.text(in: model.span(of: "section-1")!.range) == "One\nfirst")
    #expect(model.text(in: model.span(of: "p-1")!.range) == "first")
    #expect(model.text(in: model.span(of: "section-1.1")!.range) == "Sub\ninner")
    #expect(model.span(of: "p-1")!.parent.map { model.spans[$0].anchor } == "section-1")
  }

  @Test func `a position is under the innermost anchor holding it`() {
    let model = model(.paragraph(Paragraph(text: "first", anchor: "p-1")))
    let start = model.span(of: "p-1")!.range.lowerBound
    #expect(model.position(at: start + 2, isEnd: false) == Position(anchor: "p-1", offset: 2))
    // The heading is the section's own.
    #expect(model.position(at: 1, isEnd: false) == Position(anchor: "section-1", offset: 1))
    // An end where the paragraph ends is in the paragraph.
    #expect(model.position(at: start + 5, isEnd: true) == Position(anchor: "p-1", offset: 5))
    #expect(model.offset(of: Position(anchor: "p-1", offset: 2)) == start + 2)
    #expect(model.position(at: start + 2, under: "section-1")?.anchor == "section-1")
  }

  @Test func `an offset counts Unicode scalars`() {
    let model = model(.paragraph(Paragraph(text: "a😀b", anchor: "p-1")))
    let start = model.span(of: "p-1")!.range.lowerBound
    // "b" is three UTF-16 units in, two scalars.
    #expect(model.position(at: start + 3, isEnd: false) == Position(anchor: "p-1", offset: 2))
    #expect(model.offset(of: Position(anchor: "p-1", offset: 2)) == start + 3)
  }

  @Test func `a bibliography is no part of the text`() {
    let references = Section(
      anchor: "references", number: "9", title: "References",
      blocks: [.references(ReferenceList(title: "References", entries: []))])
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [Section(anchor: "section-1", number: "1", title: "One"), references],
      source: .xml)
    #expect(ModelText(document).span(of: "references") == nil)
  }
}

/// What the builder maps and hides, for the shapes the column chooses between.
@Suite("Annotations: what a build maps")
struct PositionMapShapeTests {
  private let table = RFCKit.Table(
    title: nil, number: nil,
    header: [Table.Row(cells: [[.text("Code")], [.text("Meaning")]])],
    rows: [
      Table.Row(
        cells: [[.text("1")], [.text(String(repeating: "a long meaning ", count: 12))]],
        anchor: "row-1")
    ],
    anchor: "table-1")

  @Test func `a stacked table hides its header row and maps its cells`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.table(table)), style: ReadingStyle(measure: 200))
    let map = built.positions
    let row = try #require(map.model.span(of: "row-1"))
    let header = map.model.span(of: "table-1")!.range.lowerBound..<row.range.lowerBound - 1
    #expect(map.storageRanges(forModel: header).isEmpty)
    let cell = row.range.lowerBound..<row.range.lowerBound + 1
    let drawn = try #require(map.storageRanges(forModel: cell).first)
    #expect((built.text.string as NSString).substring(with: drawn) == "1")
  }

  @Test func `a grid's tab is the join between its cells`() throws {
    let narrow = RFCKit.Table(
      title: nil, number: nil, header: [], rows: [Table.Row(cells: [[.text("a")], [.text("b")]])],
      anchor: "table-1")
    let built = DocumentTextBuilder.build(
      Fixtures.document(.table(narrow)), style: ReadingStyle(measure: 600))
    let span = try #require(built.positions.model.span(of: "table-1"))
    let ranges = built.positions.storageRanges(forModel: span.range)
    #expect(ranges.count == 1)
    #expect((built.text.string as NSString).substring(with: ranges[0]) == "a\tb")
  }

  @Test func `a section number and a chip's symbol are the storage's own`() throws {
    let reference = Inline.crossReference(
      CrossReference(target: .document(.rfc(9110), section: nil)))
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph([.text("See "), reference]))), style: ReadingStyle())
    let storage = built.text.string as NSString
    // "1. " before the heading maps to nothing.
    #expect(built.positions.modelOffset(forStorage: 0) == nil)
    let symbol = storage.range(of: "\u{FFFC}").location
    #expect(built.positions.modelOffset(forStorage: symbol) == nil)
    let label = storage.range(of: "RFC\u{00A0}9110").location
    #expect(built.positions.modelOffset(forStorage: label) != nil)
  }

  @Test func `a block shown unfolded maps its lines and hides its header`() throws {
    let unfolded = String(repeating: "x", count: 70)
    let folded = Fixtures.folded(unfolded)
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(folded)), style: ReadingStyle(measure: 2000))
    let span = try #require(built.positions.model.span(of: "folded"))
    let ranges = built.positions.storageRanges(forModel: span.range)
    let shown = ranges.map { (built.text.string as NSString).substring(with: $0) }.joined()
    #expect(shown == unfolded)
    #expect(
      built.positions.hidden.contains { built.positions.model.text(in: $0).contains("NOTE") })
  }

  @Test func `a selection hull leaves out what is the storage's own`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph(text: "words", anchor: "p-1"))),
      style: ReadingStyle())
    let storage = built.text.string as NSString
    let whole = NSRange(location: 0, length: storage.length)
    let range = try #require(built.positions.modelRange(forStorage: whole))
    // From the heading's first word to the paragraph's last.
    #expect(built.positions.model.text(in: range) == "S\nwords")
  }

  @Test func `tabs expanded align with the tab they came from`() {
    let runs = PositionMap.alignment(of: Array("a       b".utf16), to: Array("a\tb".utf16))
    #expect(runs.map(\.length).reduce(0, +) == 2)
    #expect(runs.first?.model == 0 && runs.last?.model == 2 && runs.last?.storage == 8)
  }
}
