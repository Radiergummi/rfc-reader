import Foundation
import Testing

@testable import RFCKit

/// A legacy figure's caption becomes its title, and a drawing says it is one (#361).
@Suite("Figure captions")
struct FigureCaptionTests {
  // MARK: Guards

  @Test func `a label with a title is a caption`() {
    #expect(
      LegacyTextParser.caption(["        Figure 4:  Relay sequence"])
        == .init(isTable: false, number: 4, label: "Figure 4", title: "Relay sequence"))
    #expect(
      LegacyTextParser.caption(["Table 2.  Option codes"])
        == .init(isTable: true, number: 2, label: "Table 2", title: "Option codes"))
    #expect(
      LegacyTextParser.caption(["Fig. 6 -- Gateway layout"])
        == .init(isTable: false, number: 6, label: "Fig. 6", title: "Gateway layout"))
  }

  @Test func `a label alone is a caption without a title`() {
    #expect(
      LegacyTextParser.caption(["                Figure 9."])
        == .init(isTable: false, number: 9, label: "Figure 9", title: nil))
  }

  /// A title runs onto a second line, or stands on the line above a label alone.
  @Test func `a caption may take two lines`() {
    #expect(
      LegacyTextParser.caption(["Figure 5: Relay sequence over", "a congested path"])?.title
        == "Relay sequence over a congested path")
    #expect(
      LegacyTextParser.caption(["     Lookup Reply Layout", "         Figure 3.2"])
        == .init(isTable: false, number: nil, label: "Figure 3.2", title: "Lookup Reply Layout"))
  }

  /// A figure numbered by its section has no whole number, so it keeps the name the
  /// prose calls it by in its title.
  @Test func `a figure numbered by section keeps its label in its title`() throws {
    let caption = try #require(LegacyTextParser.caption(["Figure 3.2: Lookup reply"]))
    #expect(caption.number == nil)
    #expect(caption.blockTitle == "Figure 3.2: Lookup reply")
  }

  @Test(arguments: [
    ["Figure 3 shows the relay sequence"],
    ["See Figure 3: it shows the sequence"],
    ["Figure 3", "is the relay sequence", "over a congested path"],
    ["Figures 3 and 4"],
  ])
  func `a sentence about a figure is no caption`(lines: [String]) {
    #expect(LegacyTextParser.caption(lines) == nil)
  }

  private static func artwork(_ text: String) -> Block {
    .preformatted(Preformatted(kind: .artwork, text: text))
  }

  private static let drawing = """
    +--------+          +--------+
    | Client | -------> | Server |
    +--------+          +--------+
    """

  @Test func `a caption under a drawing makes it a figure`() throws {
    let blocks = LegacyTextParser.figuring([
      .paragraph(Paragraph([.text("The exchange:")])), Self.artwork(Self.drawing),
      Self.artwork("Figure 1: The exchange"),
    ])
    #expect(blocks.count == 2)
    guard case .figure(let figure) = blocks.last else {
      Issue.record("no figure")
      return
    }
    #expect(figure.number == 1)
    #expect(figure.title == "The exchange")
    #expect(figure.anchor == "figure-1")
    #expect(
      figure.blocks == [
        .preformatted(Preformatted(kind: .artwork, text: Self.drawing, type: "ascii-art"))
      ])
  }

  /// A title between a drawing and a caption with none takes the caption's place, and
  /// a note there stays in the figure.
  @Test func `a title and a note above a caption are the figure's`() throws {
    let blocks = LegacyTextParser.figuring([
      Self.artwork(Self.drawing), Self.artwork("Client and Server"),
      Self.artwork("Each box is one host."), Self.artwork("Figure 2."),
    ])
    guard case .figure(let figure) = blocks.only else {
      Issue.record("not one figure: \(blocks)")
      return
    }
    #expect(figure.title == "Client and Server")
    #expect(figure.blocks.count == 2)
    #expect(figure.blocks.last == Self.artwork("Each box is one host."))
  }

  /// A drawing that took its title in, past a blank line, gives it up to the caption.
  @Test func `a title the drawing took in is split off`() throws {
    let blocks = LegacyTextParser.figuring([
      Self.artwork(Self.drawing + "\n\n          Client and Server"), Self.artwork("Figure 2."),
    ])
    guard case .figure(let figure) = blocks.only else {
      Issue.record("not one figure: \(blocks)")
      return
    }
    #expect(figure.title == "Client and Server")
    #expect(
      figure.blocks == [
        .preformatted(Preformatted(kind: .artwork, text: Self.drawing, type: "ascii-art"))
      ])
  }

  @Test func `a table's caption titles the table above it`() throws {
    let table = Table(
      title: nil, header: [Table.Row(cells: [[.text("Code")]])],
      rows: [Table.Row(cells: [[.text("1")]])])
    let blocks = LegacyTextParser.figuring([.table(table), Self.artwork("Table 3: Codes")])
    guard case .table(let titled) = blocks.only else {
      Issue.record("not one table: \(blocks)")
      return
    }
    #expect(titled.title == "Codes")
    #expect(titled.number == 3)
    #expect(titled.anchor == "table-3")
  }

  /// A caption under prose, or under a line of words that stands under no drawing,
  /// captions nothing the parser can see, and stays as it was.
  @Test func `a caption under no verbatim block stays`() {
    let caption = Self.artwork("Figure 4.")
    let prose: [Block] = [.paragraph(Paragraph([.text("The exchange.")])), caption]
    #expect(LegacyTextParser.figuring(prose) == prose)
    let title: [Block] = [prose[0], Self.artwork("Client and Server"), caption]
    #expect(LegacyTextParser.figuring(title) == title)
  }

  /// Two figures one number, as a figure continued over a page: the first has the
  /// anchor.
  @Test func `a number's anchor goes to its first figure`() {
    let blocks = LegacyTextParser.figuring([
      Self.artwork(Self.drawing), Self.artwork("Figure 3"),
      Self.artwork(Self.drawing), Self.artwork("Figure 3 (Continued)"),
    ])
    let anchors = blocks.map { block -> String? in
      guard case .figure(let figure) = block else { return "not a figure" }
      return figure.anchor
    }
    #expect(anchors == ["figure-3", nil])
  }

  @Test func `artwork that is no drawing stays untyped`() {
    let words = Self.artwork("client sends HELLO\nserver sends WELCOME")
    #expect(LegacyTextParser.figuring([words]) == [words])
  }

  // MARK: Through a document

  private static func figures(in document: RFCDocument) -> [Figure] {
    var figures: [Figure] = []
    func visit(_ section: Section) {
      for block in section.blocks {
        if case .figure(let figure) = block { figures.append(figure) }
      }
      section.subsections.forEach(visit)
    }
    document.sections.forEach(visit)
    return figures
  }

  /// RFC 793 captions its figures `Figure N.` alone, under a title of their own: the
  /// header layout's title has a note between it and the caption.
  @Test func `RFC 793's captions name its figures`() throws {
    let figures = Self.figures(in: try Fixtures.parse("rfc793.txt"))
    let header = try #require(figures.first { $0.number == 3 })
    #expect(header.title == "TCP Header Format")
    #expect(header.anchor == "figure-3")
    guard case .preformatted(let layout)? = header.blocks.first else {
      Issue.record("no layout")
      return
    }
    #expect(layout.type == "ascii-art")
    #expect(header.blocks.count == 2)
    #expect(
      try #require(figures.first { $0.number == 6 }).title == "TCP Connection State Diagram")
    // The figures whose drawing is verbatim: the sequence spaces of Figures 4 and 5,
    // and the ladders from Figure 7 on, read as prose and lists, and their captions
    // stay as they were.
    #expect(figures.compactMap(\.number) == [1, 2, 3, 6])
  }

  /// RFC 1005 numbers its figures by section and sets the title above the label.
  @Test func `RFC 1005's figures keep their section numbers`() throws {
    let figures = Self.figures(in: try Fixtures.parse("rfc1005.txt"))
    #expect(figures.contains { $0.title == "Figure 2.1: IP Class A Mapping" && $0.number == nil })
    #expect(figures.allSatisfy { $0.anchor == nil })
  }
}

extension Array {
  fileprivate var only: Element? { count == 1 ? first : nil }
}
