import CoreGraphics
import CoreText
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Print: page layout")
struct PrintLayoutTests {
  @Test func `the US prints on Letter and everywhere else on A4`() {
    #expect(PrintLayout.paperSize(for: Locale(identifier: "en_US")) == PrintLayout.letter)
    #expect(PrintLayout.paperSize(for: Locale(identifier: "de_DE")) == PrintLayout.isoA4)
    #expect(PrintLayout.paperSize(for: Locale(identifier: "en_GB")) == PrintLayout.isoA4)
  }

  @Test func `the text sits inside the margins`() {
    let layout = PrintLayout(paperSize: PrintLayout.isoA4)
    #expect(layout.contentRect.minX == PrintLayout.sideMargin)
    #expect(layout.contentRect.maxX == PrintLayout.isoA4.width - PrintLayout.sideMargin)
    #expect(layout.contentRect.minY == PrintLayout.verticalMargin)
    #expect(layout.contentRect.maxY == PrintLayout.isoA4.height - PrintLayout.verticalMargin)
  }

  @Test func `the header and footer sit in the margins, not over the text`() {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    #expect(layout.headerRect.maxY <= layout.contentRect.minY)
    #expect(layout.footerRect.minY >= layout.contentRect.maxY)
    #expect(layout.headerRect.minX == layout.contentRect.minX)
    #expect(layout.footerRect.width == layout.contentRect.width)
  }

  @Test func `the document is built to the paper's column, at the print size`() {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    #expect(layout.style.measure == layout.contentRect.width)
    #expect(layout.style.bodySize == PrintLayout.bodySize)
    #expect(!layout.style.emitsLinks)
  }

  /// The published text's artwork only reads at its own 72 columns, so they have to
  /// fit the narrower of the two papers without wrapping.
  @Test func `the original text's 72 columns fit the narrowest paper`() {
    let font = PlatformFont.monospacedSystemFont(
      ofSize: PrintLayout.originalTextSize, weight: .regular)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: String(repeating: "0", count: 72), attributes: [.font: font]))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let narrowest = min(
      PrintLayout(paperSize: PrintLayout.letter).contentRect.width,
      PrintLayout(paperSize: PrintLayout.isoA4).contentRect.width)
    #expect(width <= narrowest)
  }

  @Test func `paper too small for the margins has an empty column, not a negative one`() {
    let layout = PrintLayout(paperSize: CGSize(width: 80, height: 100))
    #expect(layout.contentRect.width == 0)
    #expect(layout.contentRect.height == 0)
  }
}

@Suite("Print: pagination")
struct PrintPaginationTests {
  typealias Line = PrintPagination.Line
  typealias Page = PrintPagination.Page

  /// `count` lines `height` tall, stacked from the top.
  private func lines(_ count: Int, height: CGFloat = 10) -> [Line] {
    (0..<count).map { Line(minY: CGFloat($0) * height, maxY: CGFloat($0 + 1) * height) }
  }

  @Test func `lines that fit make one page`() {
    #expect(PrintPagination.pages(of: lines(5), pageHeight: 100) == [Page(top: 0, bottom: 50)])
  }

  @Test func `nothing to lay out makes no pages`() {
    #expect(PrintPagination.pages(of: [], pageHeight: 100).isEmpty)
    #expect(PrintPagination.pages(of: lines(3), pageHeight: 0).isEmpty)
  }

  @Test func `a page ends before the first line that would run past its foot`() {
    let pages = PrintPagination.pages(of: lines(25), pageHeight: 100)
    // The tenth line ends exactly at the page's foot, and stays on it.
    #expect(
      pages == [
        Page(top: 0, bottom: 100), Page(top: 100, bottom: 200), Page(top: 200, bottom: 250),
      ])
  }

  /// A page's slice runs from the top of its first line, so the space between
  /// paragraphs at a break is not carried to the top of the next page.
  @Test func `the next page starts at its first line, not at the last one's foot`() {
    let spaced = [
      Line(minY: 0, maxY: 60),
      Line(minY: 80, maxY: 140),
    ]
    let pages = PrintPagination.pages(of: spaced, pageHeight: 100)
    #expect(pages == [Page(top: 0, bottom: 60), Page(top: 80, bottom: 140)])
  }

  @Test func `a heading at the foot of a page moves to the top of the next`() {
    var stack = lines(9)
    stack.append(Line(minY: 90, maxY: 100, keepsWithNext: true))
    stack.append(Line(minY: 100, maxY: 110))
    let pages = PrintPagination.pages(of: stack, pageHeight: 100)
    #expect(pages == [Page(top: 0, bottom: 90), Page(top: 90, bottom: 110)])
  }

  @Test func `a heading of several lines moves whole`() {
    var stack = lines(8)
    stack.append(Line(minY: 80, maxY: 90, keepsWithNext: true))
    stack.append(Line(minY: 90, maxY: 100, keepsWithNext: true))
    stack.append(Line(minY: 100, maxY: 110))
    let pages = PrintPagination.pages(of: stack, pageHeight: 100)
    #expect(pages == [Page(top: 0, bottom: 80), Page(top: 80, bottom: 110)])
  }

  /// A page of nothing but headings would otherwise be moved until it was empty.
  @Test func `a page of nothing but headings still ends`() {
    let headings = (0..<12).map {
      Line(minY: CGFloat($0) * 10, maxY: CGFloat($0 + 1) * 10, keepsWithNext: true)
    }
    let pages = PrintPagination.pages(of: headings, pageHeight: 100)
    #expect(pages.first == Page(top: 0, bottom: 100))
    #expect(pages.allSatisfy { $0.height > 0 })
  }

  @Test func `a line taller than a page gets a page of its own`() {
    let stack = [
      Line(minY: 0, maxY: 10),
      Line(minY: 10, maxY: 260),
      Line(minY: 260, maxY: 270),
    ]
    let pages = PrintPagination.pages(of: stack, pageHeight: 100)
    #expect(
      pages == [Page(top: 0, bottom: 10), Page(top: 10, bottom: 260), Page(top: 260, bottom: 270)])
  }

  /// Every line lands on exactly one page, whole: none is cut, dropped or repeated.
  @Test func `every line is on exactly one page`() {
    var stack: [Line] = []
    var y: CGFloat = 0
    for index in 0..<400 {
      let height = CGFloat(8 + index % 7 * 3)
      stack.append(Line(minY: y, maxY: y + height, keepsWithNext: index % 23 == 0))
      y += height + CGFloat(index % 5 == 0 ? 6 : 0)
    }
    let pages = PrintPagination.pages(of: stack, pageHeight: 700)
    for line in stack {
      let holding = pages.filter { $0.top <= line.minY && line.maxY <= $0.bottom }
      #expect(holding.count == 1)
    }
    #expect(pages.allSatisfy { $0.height <= 700 })
  }

  typealias Span = PrintPagination.Span

  @Test func `a page draws the paragraphs that reach into it`() {
    let spans = [
      Span(minY: 0, maxY: 40),
      Span(minY: 40, maxY: 120),
      Span(minY: 120, maxY: 150),
      Span(minY: 150, maxY: 260),
    ]
    #expect(PrintPagination.spans(spans, on: Page(top: 0, bottom: 100)) == 0..<2)
    // The second paragraph continues onto this page, and is drawn on both.
    #expect(PrintPagination.spans(spans, on: Page(top: 100, bottom: 200)) == 1..<4)
    #expect(PrintPagination.spans(spans, on: Page(top: 200, bottom: 260)) == 3..<4)
  }

  /// A paragraph that ends where a page starts, or starts where it ends, is not on it.
  @Test func `a paragraph touching a page's edge is not on it`() {
    let spans = [Span(minY: 0, maxY: 100), Span(minY: 100, maxY: 200), Span(minY: 200, maxY: 300)]
    #expect(PrintPagination.spans(spans, on: Page(top: 100, bottom: 200)) == 1..<2)
  }

  @Test func `no paragraphs, no range`() {
    #expect(PrintPagination.spans([], on: Page(top: 0, bottom: 100)).isEmpty)
  }
}

@Suite("Builder: what keeps with the next paragraph")
@MainActor
struct BuilderKeepsWithNextTests {
  @Test func `every heading keeps with what follows, the abstract's included`() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
    for entry in built.anchors.entries where entry.heading != nil {
      #expect(built.keepsWithNext.contains(entry.offset))
    }
    let abstract = try #require(built.anchors.offset(of: DocumentTextBuilder.abstractAnchor))
    #expect(built.keepsWithNext.contains(abstract))
    // A figure is anchored, but it is not a heading.
    let figure = try #require(built.anchors.offset(of: "fig-long"))
    #expect(!built.keepsWithNext.contains(figure))
  }

  @Test func `a title block's title keeps with what follows`() throws {
    let title = DocumentTextBuilder.TitleBlock(title: "A Protocol for Examples", details: [])
    let built = DocumentTextBuilder.build(
      try Fixtures.rfc8999(), style: ReadingStyle(), title: title)
    #expect(built.keepsWithNext.contains(0))
  }
}

@Suite("Print: title and running header")
@MainActor
struct PrintFurnitureTests {
  private func header(authors: [Author] = []) -> DocumentHeader {
    DocumentHeader(
      id: .rfc(9999), title: "A Protocol for Examples", abbreviatedTitle: "Examples",
      authors: authors, date: PublicationDate(year: 2026, month: 6),
      workingGroup: "Example Working Group", category: "Standards Track")
  }

  @Test func `the running header is number, short title and date`() {
    let furniture = PrintFurniture(header: header(), metadata: nil)
    #expect(furniture.headerLeading == "RFC 9999")
    #expect(furniture.headerCenter == "Examples")
    #expect(furniture.headerTrailing == "June 2026")
    #expect(furniture.footerCenter == "Standards Track")
  }

  @Test func `a document without a short title runs its whole title`() {
    let furniture = PrintFurniture(
      header: DocumentHeader(title: "A Protocol for Examples"), metadata: nil)
    #expect(furniture.headerCenter == "A Protocol for Examples")
    #expect(furniture.headerLeading.isEmpty)
  }

  @Test func `the footer names authors by surname, as an RFC does`() {
    #expect(PrintFurniture.byline([]) == "")
    #expect(PrintFurniture.byline([Author(name: "A. Writer")]) == "Writer")
    #expect(
      PrintFurniture.byline([Author(name: "A. Writer"), Author(name: "B. Scribe")])
        == "Writer & Scribe")
    #expect(
      PrintFurniture.byline([
        Author(name: "A. Writer"), Author(name: "B. Scribe"), Author(name: "C. Author"),
      ]) == "Writer, et al.")
  }

  @Test func `the title block carries the identity line and the authors`() {
    let furniture = PrintFurniture(
      header: header(authors: [
        Author(name: "A. Writer", role: "editor"), Author(name: "B. Scribe"),
      ]),
      metadata: nil)
    #expect(furniture.titleBlock.title == "A Protocol for Examples")
    #expect(
      furniture.titleBlock.details == [
        "RFC 9999 · Standards Track · June 2026 · Example Working Group",
        "A. Writer, Ed., B. Scribe",
      ])
  }

  /// What the document's header leaves out, the index fills in; what it says, wins.
  @Test func `the header and the index merge as they do on screen`() {
    let metadata = RFCMetadata(
      id: .rfc(9999), title: "Index Title", authors: [Author(name: "I. Ndex")],
      date: PublicationDate(year: 2025, month: 1), workingGroup: "Index Group")
    let bare = HeaderSummary(header: DocumentHeader(title: "A Protocol"), metadata: metadata)
    #expect(bare.title == "A Protocol")
    #expect(bare.date == "January 2025")
    #expect(bare.workingGroup == "Index Group")
    #expect(bare.authors == [Author(name: "I. Ndex")])
    let full = HeaderSummary(
      header: header(authors: [Author(name: "A. Writer")]), metadata: metadata)
    #expect(full.date == "June 2026")
    #expect(full.workingGroup == "Example Working Group")
    #expect(full.authors == [Author(name: "A. Writer")])
  }

  @Test func `pages are numbered as an RFC numbers them`() {
    #expect(PrintFurniture.pageLabel(7) == "[Page 7]")
  }
}

@Suite("Builder: title block")
@MainActor
struct BuilderTitleTests {
  private let title = DocumentTextBuilder.TitleBlock(
    title: "A Protocol for Examples", details: ["RFC 9999 · June 2026", "", "A. Writer"])

  @Test func `a print's build has no links, and keeps its chips`() throws {
    let built = DocumentTextBuilder.build(
      try Fixtures.rfc8999(), style: PrintLayout(paperSize: PrintLayout.letter).style)
    let whole = NSRange(location: 0, length: built.text.length)
    var links = 0
    var chips = 0
    built.text.enumerateAttribute(.link, in: whole) { value, _, _ in
      if value != nil { links += 1 }
    }
    built.text.enumerateAttribute(.rfcChip, in: whole) { value, _, _ in
      if value != nil { chips += 1 }
    }
    #expect(links == 0)
    #expect(chips > 0)
  }

  @Test func `the reader's build has no title block`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    #expect(!built.text.string.hasPrefix(document.header.title))
  }

  @Test func `a title block opens the text, with its details a line each`() throws {
    let built = DocumentTextBuilder.build(
      try Fixtures.rfc8999(), style: ReadingStyle(), title: title)
    #expect(
      built.text.string.hasPrefix("A Protocol for Examples\nRFC 9999 · June 2026\nA. Writer\n"))
  }

  /// The anchors are recorded as the text is emitted, so a title block before them
  /// moves every one of them by its own length, and each still names its heading.
  @Test func `anchors still point at their headings after a title block`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(), title: title)
    let text = built.text.string as NSString
    for section in document.allSections where !DocumentTextBuilder.holdsOnlyReferences(section) {
      let offset = try #require(built.anchors.offset(of: section.anchor))
      let length = min((section.displayTitle as NSString).length, text.length - offset)
      #expect(
        text.substring(with: NSRange(location: offset, length: length)) == section.displayTitle)
    }
  }
}
