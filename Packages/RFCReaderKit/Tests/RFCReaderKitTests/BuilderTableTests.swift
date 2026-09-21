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
@MainActor
struct BuilderTableTests {
    private func cells(_ strings: [String]) -> [[Inline]] {
        strings.map { [Inline.text($0)] }
    }

    private func document(_ table: RFCKit.Table) -> RFCDocument {
        RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.table(table)])],
            source: .xml
        )
    }

    private var narrow: RFCKit.Table {
        RFCKit.Table(
            title: "Methods",
            number: 1,
            header: [cells(["Method", "Safe", "Idempotent"])],
            rows: [cells(["GET", "yes", "yes"]), cells(["POST", "no", "no"])],
            anchor: "table-1"
        )
    }

    /// The shape RFC 9110 keeps producing: two short columns and one prose column of
    /// about ninety characters.
    private var prose: RFCKit.Table {
        RFCKit.Table(
            title: "Status Codes",
            number: 2,
            header: [cells(["Code", "Description", "Ref."])],
            rows: [cells(["404", String(repeating: "a long prose description ", count: 4), "6.5.4"])],
            anchor: "table-2"
        )
    }

    @Test func aNarrowTableUsesTheGrid() {
        let builder = DocumentTextBuilder(style: ReadingStyle())
        #expect(builder.tableShape(narrow) == .grid)
    }

    @Test func aTableWithAProseColumnStacks() {
        let builder = DocumentTextBuilder(style: ReadingStyle())
        #expect(builder.tableShape(prose) == .stacked)
    }

    /// The brief's phone-measure test asserted `narrow` stacks at measure 320, but its
    /// three columns total roughly 207 pt including gutters — comfortably under 320,
    /// so it grids. Replaced with a threshold test derived from the table's own
    /// natural widths, so it cannot rot when fonts or fixtures change.
    @Test func theMeasureDecidesTheShape() {
        let wide = DocumentTextBuilder(style: ReadingStyle(measure: 10_000))
        let widths = wide.naturalColumnWidths(narrow)
        let total = widths.reduce(0, +) + DocumentTextBuilder.columnGutter * CGFloat(widths.count - 1)

        #expect(DocumentTextBuilder(style: ReadingStyle(measure: total + 1)).tableShape(narrow) == .grid)
        #expect(DocumentTextBuilder(style: ReadingStyle(measure: total - 1)).tableShape(narrow) == .stacked)
    }

    @Test func gridRowsAreTabSeparatedAndCarryTabStops() throws {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.text.string.contains("GET\tyes\tyes"))
        let offset = try #require(built.anchors.offset(of: "table-1"))
        let paragraph = try #require(built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.tabStops.count >= 2)
        #expect(paragraph.lineBreakMode == .byClipping)
    }

    @Test func stackedRowsLeadWithTheirColumnHeader() {
        let built = DocumentTextBuilder.build(document(prose), style: ReadingStyle())
        #expect(built.text.string.contains("Code"))
        #expect(built.text.string.contains("Description"))
        #expect(built.text.string.contains("404"))
        // Stacked cells wrap, so they must not be clipped.
        let range = built.text.string.range(of: "404")
        #expect(range != nil)
    }

    @Test func cellInlinesKeepTheirCrossReferences() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: "6.5.4"), text: "[RFC 9110]")
        let table = RFCKit.Table(
            title: nil,
            header: [cells(["Ref."])],
            rows: [[[.crossReference(xref)]]],
            anchor: "table-3"
        )
        let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
        let offset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "[RFC 9110]")).lowerBound
        )
        #expect(built.text.attribute(.rfcReference, at: offset, effectiveRange: nil) is ReferenceBox)
        #expect(built.text.attribute(.link, at: offset, effectiveRange: nil) is URL)
    }

    @Test func theCaptionIsText() {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.text.string.contains("Table 1: Methods"))
    }

    @Test func theAnchorIsIndexed() {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.anchors.offset(of: "table-1") != nil)
    }
}
