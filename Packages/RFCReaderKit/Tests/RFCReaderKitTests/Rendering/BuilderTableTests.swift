import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: tables")
struct BuilderTableTests {
  private func row(_ strings: [String]) -> RFCKit.Table.Row {
    RFCKit.Table.Row(cells: strings.map { [Inline.text($0)] })
  }

  private func document(_ table: RFCKit.Table) -> RFCDocument {
    Fixtures.document(.table(table))
  }

  private var narrow: RFCKit.Table {
    RFCKit.Table(
      title: "Methods",
      number: 1,
      header: [row(["Method", "Safe", "Idempotent"])],
      rows: [row(["GET", "yes", "yes"]), row(["POST", "no", "no"])],
      anchor: "table-1"
    )
  }

  /// The shape RFC 9110 keeps producing: two short columns and one prose column of
  /// about ninety characters.
  private var prose: RFCKit.Table {
    RFCKit.Table(
      title: "Status Codes",
      number: 2,
      header: [row(["Code", "Description", "Ref."])],
      rows: [row(["404", String(repeating: "a long prose description ", count: 4), "6.5.4"])],
      anchor: "table-2"
    )
  }

  /// The production path: measure the columns, then let the widths decide.
  private func shape(
    _ table: RFCKit.Table,
    measure: CGFloat = ReadingStyle().measure
  ) -> TableShape {
    let builder = DocumentTextBuilder(style: ReadingStyle(measure: measure))
    return builder.tableShape(widths: builder.naturalColumnWidths(table))
  }

  @Test func `a narrow table uses the grid`() {
    #expect(shape(narrow) == .grid)
  }

  @Test func `a table with a prose column stacks`() {
    #expect(shape(prose) == .stacked)
  }

  /// The brief's phone-measure test asserted `narrow` stacks at measure 320, but its
  /// three columns total roughly 207 pt including gutters — comfortably under 320,
  /// so it grids. Replaced with a threshold test derived from the table's own
  /// natural widths, so it cannot rot when fonts or fixtures change.
  @Test func `the measure decides the shape`() {
    let wide = DocumentTextBuilder(style: ReadingStyle(measure: 10_000))
    let widths = wide.naturalColumnWidths(narrow)
    let total = widths.reduce(0, +) + DocumentTextBuilder.columnGutter * CGFloat(widths.count - 1)

    #expect(shape(narrow, measure: total + 1) == .grid)
    #expect(shape(narrow, measure: total - 1) == .stacked)
  }

  /// A cell is measured as it is set: strong text in a data cell renders bold, and
  /// in a header cell heavy, and measuring its plain text in the row's font alone
  /// left the column too narrow for it, so the text ran past its tab stop (#360).
  @Test func `a cell is measured in the fonts it is set in`() throws {
    let words = "Implementation Considerations"
    for inHeader in [false, true] {
      func table(_ cell: [Inline]) -> RFCKit.Table {
        let rows = [RFCKit.Table.Row(cells: [cell])]
        return RFCKit.Table(title: nil, header: inHeader ? rows : [], rows: inHeader ? [] : rows)
      }
      let builder = DocumentTextBuilder(style: ReadingStyle())
      let plain = builder.naturalColumnWidths(table([.text(words)]))[0]
      let strong = table([.strong([.text(words)])])
      let measured = builder.naturalColumnWidths(strong)[0]
      #expect(measured > plain, "header: \(inHeader)")

      let built = DocumentTextBuilder.build(document(strong), style: ReadingStyle())
      let offset = try Fixtures.offset(of: words, in: built.text)
      let set = built.text.attributedSubstring(
        from: NSRange(location: offset, length: (words as NSString).length))
      #expect(measured == builder.lineWidth(set), "header: \(inHeader)")
    }
  }

  /// A reference chip is measured as it is drawn: its symbol is an attachment, which
  /// CoreText measures as nothing, and the padding kern around it is added only once
  /// the build is done. Measured as its label alone, the column was too narrow for it,
  /// the chip ran past its tab stop, and the next cell fell through to
  /// `defaultTabInterval` (#488).
  @Test func `a chip cell ends before its tab stop`() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: nil))
    let table = RFCKit.Table(
      title: nil,
      header: [],
      rows: [RFCKit.Table.Row(cells: [[.crossReference(xref)], [.text("next")]])]
    )
    #expect(shape(table) == .grid)
    let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
    let next = try Fixtures.offset(of: "next", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: next, effectiveRange: nil) as? NSParagraphStyle)
    let stop = try #require(paragraph.tabStops.first).location

    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(built.text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 10_000, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    defer { withExtendedLifetime(storage) {} }

    let location = try #require(layout.location(atOffset: next))
    let fragment = try #require(layout.textLayoutFragment(for: location))
    let start = layout.offset(of: fragment.rangeInElement.location)
    let line = try #require(fragment.textLineFragments.first)
    let x = line.typographicBounds.minX + line.locationForCharacter(at: next - start).x
    #expect(abs(x - stop) < 0.5, "the next cell starts at \(x), its tab stop is at \(stop)")
  }

  @Test func `grid rows are tab separated and carry tab stops`() throws {
    let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
    #expect(built.text.string.contains("GET\tyes\tyes"))
    let offset = try #require(built.anchors.offset(of: "table-1"))
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.tabStops.count >= 2)
    #expect(paragraph.lineBreakMode == .byClipping)
  }

  @Test func `stacked rows lead with their column header`() throws {
    #expect(shape(prose) == .stacked)

    let built = DocumentTextBuilder.build(document(prose), style: ReadingStyle())
    // "Code  404" (bold label, two spaces, cell) only appears in the stacked
    // shape; the grid shape would emit "Code\tDescription\tRef." on one line
    // and "404\t…" on another, never this adjacency.
    #expect(built.text.string.contains("Code  404"))

    let offset = try Fixtures.offset(of: "404", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    // Stacked cells wrap, so they must not be clipped.
    #expect(paragraph.lineBreakMode != .byClipping)
  }

  @Test func `cell inlines keep their cross references`() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: "6.5.4"), text: "[RFC 9110]")
    let table = RFCKit.Table(
      title: nil,
      header: [row(["Ref."])],
      rows: [RFCKit.Table.Row(cells: [[.crossReference(xref)]])],
      anchor: "table-3"
    )
    let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
    let offset = try Fixtures.offset(of: "[RFC 9110]", in: built.text)
    #expect(built.text.attribute(.rfcReference, at: offset, effectiveRange: nil) is ReferenceBox)
    #expect(built.text.attribute(.link, at: offset, effectiveRange: nil) is URL)
  }

  @Test func `the caption is text`() {
    let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
    #expect(built.text.string.contains("Table 1: Methods"))
  }

  /// As xml2rfc writes it: the number and the name, the number alone, the name
  /// alone, and nothing for a block that has neither.
  @Test func `a caption is the number, the name, or both`() {
    #expect(DocumentTextBuilder.caption("Table", number: 2, title: "Codes") == "Table 2: Codes")
    #expect(DocumentTextBuilder.caption("Table", number: 2, title: nil) == "Table 2")
    #expect(DocumentTextBuilder.caption("Table", number: nil, title: "Codes") == "Codes")
    #expect(DocumentTextBuilder.caption("Table", number: nil, title: nil) == nil)
  }

  @Test func `the anchor is indexed`() {
    let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
    #expect(built.anchors.offset(of: "table-1") != nil)
  }

  /// A row a document cites is indexed where the row starts, in either shape (#166).
  /// The cited row is the second, so the grid's step past its header row is pinned
  /// too: the header and the body share one enumeration there.
  @Test(arguments: [TableShape.grid, .stacked])
  func `a rows anchor is indexed at the row`(shape expected: TableShape) throws {
    var table = expected == .grid ? narrow : prose
    if expected == .stacked { table.rows.append(row(["410", "gone", "6.5.9"])) }
    table.rows[1].anchor = "cited-row"
    #expect(shape(table) == expected)
    let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
    let offset = try #require(built.anchors.offset(of: "cited-row"))
    let rowStart = expected == .grid ? "POST" : "Code  410"
    #expect(try Fixtures.offset(of: rowStart, in: built.text) == offset)
  }

  /// A header row's anchor is indexed at the header: its own row in the grid, and
  /// the first label in the stacked shape, where the header labels every cell
  /// instead of standing as a row.
  @Test(arguments: [TableShape.grid, .stacked])
  func `a header rows anchor is indexed at the header`(shape expected: TableShape) throws {
    var table = expected == .grid ? narrow : prose
    table.header[0].anchor = "cited-header"
    #expect(shape(table) == expected)
    let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
    let offset = try #require(built.anchors.offset(of: "cited-header"))
    let header = expected == .grid ? "Method" : "Code"
    #expect(try Fixtures.offset(of: header, in: built.text) == offset)
  }
}
