import CoreGraphics
import Foundation
import PDFKit
import RFCKit
import Testing
import UniformTypeIdentifiers

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Export: formats")
struct ExportFormatTests {
  private let june = PublicationDate(year: 2026, month: 6)

  @Test func `a file is named by its series and number`() {
    #expect(ExportFormat.pdf.fileName(for: .rfc(10042)) == "RFC-10042.pdf")
    #expect(ExportFormat.pdf.fileName(for: DocumentID(series: .bcp, number: 14)) == "BCP-14.pdf")
    #expect(ExportFormat.fileStem(for: .rfc(9110)) == "RFC-9110")
  }

  /// Finder tags: the series, the working group and the status, and nothing empty.
  @Test func `a file is tagged with its working group and status`() {
    let metadata = RFCMetadata(
      id: .rfc(10042), title: "A Protocol", date: june, currentStatus: .informational,
      workingGroup: "sshm")
    #expect(ExportFormat.tagNames(for: metadata) == ["RFC", "sshm", "Informational"])
  }

  @Test func `a file from no working group, of no known status, is tagged RFC alone`() {
    let none = RFCMetadata(
      id: .rfc(10042), title: "A Protocol", date: june, currentStatus: .unknown,
      workingGroup: "NON WORKING GROUP")
    #expect(ExportFormat.tagNames(for: none) == ["RFC"])
    #expect(ExportFormat.tagNames(for: nil) == ["RFC"])
    let empty = RFCMetadata(
      id: .rfc(10042), title: "A Protocol", date: june, currentStatus: .historic, workingGroup: "")
    #expect(ExportFormat.tagNames(for: empty) == ["RFC", "Historic"])
  }

  /// Changing the format keeps a name the user typed, and swaps its extension.
  @Test func `a new format keeps the name and changes the extension`() {
    #expect(ExportFormat.pdf.renaming("rfc9110.md") == "rfc9110.pdf")
    #expect(ExportFormat.pdf.renaming("HTTP semantics") == "HTTP semantics.pdf")
    #expect(ExportFormat.pdf.renaming("notes.v2.txt") == "notes.v2.pdf")
    #expect(ExportFormat.pdf.renaming("RFC-10042.pdf") == "RFC-10042.pdf")
    #expect(ExportFormat.pdf.renaming("RFC-10042") == "RFC-10042.pdf")
  }

  /// A dot in a name is not always an extension: only a suffix that names a file
  /// type is replaced.
  @Test func `a new format keeps a dot that is not an extension`() {
    #expect(ExportFormat.pdf.renaming("RFC-10042 v1.2") == "RFC-10042 v1.2.pdf")
    #expect(ExportFormat.pdf.renaming("RFC-10042 v1.2.pdf") == "RFC-10042 v1.2.pdf")
  }

  @Test func `PDF is rendered, and typed as a PDF`() {
    #expect(ExportFormat.pdf.source == .rendered)
    #expect(ExportFormat.pdf.contentType == .pdf)
    #expect(ExportFormat.pdf.name(in: .english) == "PDF")
  }

  /// The published files are the RFC Editor's, and the rest are made from the
  /// model; each is typed and named as its kind of file is (#377).
  @Test func `each format has its source, type and extension`() {
    #expect(ExportFormat.html.source == .rendered)
    #expect(ExportFormat.html.contentType == .html)
    #expect(ExportFormat.html.fileName(for: .rfc(9110)) == "RFC-9110.html")
    #expect(ExportFormat.text.source == .published)
    #expect(ExportFormat.text.contentType == .plainText)
    #expect(ExportFormat.text.fileName(for: .rfc(9110)) == "RFC-9110.txt")
    #expect(ExportFormat.xml.source == .published)
    #expect(ExportFormat.xml.contentType == .xml)
    #expect(ExportFormat.xml.fileName(for: .rfc(9110)) == "RFC-9110.xml")
    #expect(ExportFormat.markdown.source == .rendered)
    #expect(ExportFormat.markdown.contentType.conforms(to: .plainText))
    #expect(ExportFormat.markdown.fileName(for: .rfc(9110)) == "RFC-9110.md")
    #expect(ExportFormat.text.name(in: .english) == "Plain Text")
  }

  @Test func `every document offers every format but the grammar`() throws {
    #expect(
      ExportFormat.available(for: try Fixtures.rfc2119())
        == [.pdf, .epub, .html, .markdown, .text, .xml, .annotations])
  }

  @Test func `highlights and notes are a Markdown file`() {
    #expect(ExportFormat.annotations.source == .rendered)
    #expect(ExportFormat.annotations.contentType == ExportFormat.markdown.contentType)
    #expect(ExportFormat.annotations.fileName(for: .rfc(9110)) == "RFC-9110.md")
    #expect(ExportFormat.annotations.name(in: .english) == "Highlights and Notes")
    #expect(ExportFormat.annotations.renaming("RFC-9110.pdf") == "RFC-9110.md")
    #expect(!ExportFormat.annotations.narrows)
  }

  /// The page and the Markdown are the serializers' (RFCKit pins what they write);
  /// PDF and the published files are not made from the model here.
  @Test func `the page and the Markdown are made from the document`() throws {
    let document = try Fixtures.rfc8999()
    #expect(ExportFormat.html.text(of: document) == RFCHTMLSerializer().page(document))
    #expect(ExportFormat.markdown.text(of: document) == RFCMarkdownSerializer().serialize(document))
    for format in [ExportFormat.pdf, .text, .xml] {
      #expect(format.text(of: document) == nil, "\(format)")
    }
  }

  /// The book is the EPUB writer's, typed and named as an EPUB (#408).
  @Test func `the book is made from the document`() throws {
    let document = try Fixtures.rfc8999()
    #expect(ExportFormat.epub.source == .rendered)
    #expect(ExportFormat.epub.contentType == .epub)
    #expect(ExportFormat.epub.fileName(for: .rfc(9110)) == "RFC-9110.epub")
    #expect(ExportFormat.epub.data(of: document) == RFCEPUBWriter().epub(document))
    #expect(ExportFormat.epub.text(of: document) == nil)
    #expect(ExportFormat.html.data(of: document) == Data(RFCHTMLSerializer().page(document).utf8))
    #expect(ExportFormat.pdf.data(of: document) == nil)
  }

  /// A legacy RFC's XML says it is a conversion, and names the text it came from;
  /// the XML parser reads it back.
  @Test func `a legacy RFC's XML says it is the app's conversion`() throws {
    let document = try Fixtures.rfc2119()
    let xml = ExportFormat.convertedXML(of: document)
    #expect(xml.contains("<!-- Converted by RFC Reader from the plain-text RFC"))
    #expect(xml.contains("https://www.rfc-editor.org/rfc/rfc2119.txt"))
    #expect(try RFCXMLParser.parse(Data(xml.utf8)).header.title == document.header.title)
  }

  /// The Mac's pop-up remembers the last format by its raw value; one this build
  /// does not have, or none, falls back to the first rather than to nothing.
  @Test func `a remembered format falls back to the first`() {
    #expect(ExportFormat(remembered: "pdf") == .pdf)
    #expect(ExportFormat(remembered: "no-such-format") == ExportFormat.allCases[0])
    #expect(ExportFormat(remembered: nil) == ExportFormat.allCases[0])
  }
}

@Suite("Export: links")
@MainActor
struct ExportLinkTests {
  private let references = [
    "WEB": Reference(
      anchor: "WEB", title: "A Web Page", url: URL(string: "https://example.com/page")),
    "RFC2119": Reference(
      anchor: "RFC2119", title: "Key words", seriesInfo: [SeriesInfo(name: "RFC", value: "2119")]),
    "NOWHERE": Reference(anchor: "NOWHERE", title: "An Unpublished Note"),
    "LOCAL": Reference(
      anchor: "LOCAL", title: "A Local File", url: URL(string: "file:///etc/hosts")),
    "LOCAL-RFC": Reference(
      anchor: "LOCAL-RFC", title: "Key words",
      seriesInfo: [SeriesInfo(name: "RFC", value: "2119")], url: URL(string: "file:///etc/hosts")),
  ]

  private func target(_ string: String) throws -> PDFExport.Target? {
    PDFExport.target(of: try #require(URL(string: string)), references: references)
  }

  @Test func `an anchor is a destination in the file`() throws {
    #expect(try target("rfc-anchor:section-4.2") == .anchor("section-4.2"))
  }

  @Test func `another RFC is its page on rfc-editor.org`() throws {
    let link = RFCLink(id: .rfc(9110), section: "4.2")
    #expect(PDFExport.target(of: link.appURL, references: [:]) == .web(link.webURL))
  }

  /// The body leaves the bibliography out, so a citation goes where its entry does.
  @Test func `a citation goes where its bibliography entry does`() throws {
    #expect(
      try target("rfc-reference:WEB") == .web(try #require(URL(string: "https://example.com/page")))
    )
    #expect(try target("rfc-reference:RFC2119") == .web(RFCLink(id: .rfc(2119)).webURL))
    #expect(try target("rfc-reference:NOWHERE") == nil)
    #expect(try target("rfc-reference:NO-SUCH-ENTRY") == nil)
  }

  @Test func `a web link stays, and nothing else becomes one`() throws {
    #expect(
      try target("https://example.com/") == .web(try #require(URL(string: "https://example.com/"))))
    #expect(try target("mailto:someone@example.com") != nil)
    #expect(try target("file:///etc/hosts") == nil)
  }

  /// An entry's URL is held to the same schemes as a link in the text; one that is
  /// not followable leaves the RFC the entry names, or nothing.
  @Test func `a citation's URL is held to the schemes a link is`() throws {
    #expect(try target("rfc-reference:LOCAL") == nil)
    #expect(try target("rfc-reference:LOCAL-RFC") == .web(RFCLink(id: .rfc(2119)).webURL))
  }

  /// A print's build keeps no live links, but it keeps where each one went, on the
  /// same runs, for an exported PDF to link again.
  @Test func `a paper build keeps every link's destination`() throws {
    let document = try Fixtures.rfc8999()
    let screen = DocumentTextBuilder.build(document, style: ReadingStyle())
    let paper = DocumentTextBuilder.build(
      document, style: PrintLayout(paperSize: PrintLayout.letter).style)
    // As sets: the paper's narrower column may lay a table out differently. A
    // heading's backlink caption goes nowhere, and paper has none (#183).
    let destinations = urls(.link, in: screen.text).filter {
      $0.scheme != ReaderLinkScheme.backlinksScheme
    }
    #expect(Set(destinations) == Set(urls(.rfcLinkTarget, in: paper.text)))
    #expect(!urls(.link, in: screen.text).isEmpty)
    #expect(urls(.link, in: paper.text).isEmpty)
  }

  /// An exported PDF is read on screen: a reference is an ordinary link, underlined
  /// in the link color, and neither a chip nor a print's plain text.
  @Test func `an export's references are underlined links, not chips`() throws {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    #expect(layout.exportStyle.references == .link)
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: layout.exportStyle)
    let whole = NSRange(location: 0, length: built.text.length)
    var chips = 0
    built.text.enumerateAttribute(.rfcChip, in: whole) { value, _, _ in
      if value != nil { chips += 1 }
    }
    #expect(chips == 0)
    #expect(!built.text.string.contains("\u{FFFC}"))
    #expect(urls(.link, in: built.text).isEmpty)

    var linked = 0
    var references = 0
    built.text.enumerateAttribute(.rfcLinkTarget, in: whole) { value, range, _ in
      guard value != nil else { return }
      linked += 1
      built.text.enumerateAttributes(in: range) { attributes, _, _ in
        if attributes[.rfcReference] != nil { references += 1 }
        #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes[.foregroundColor] as? PlatformColor == RFCColors.link)
      }
    }
    #expect(linked > 0)
    #expect(references > 0)
  }

  private func urls(_ key: NSAttributedString.Key, in text: NSAttributedString) -> [URL] {
    var found: [URL] = []
    text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, _, _ in
      if let url = value as? URL { found.append(url) }
    }
    return found
  }
}

@Suite("Export: outline and info")
@MainActor
struct ExportOutlineTests {
  @Test func `the outline follows the sections the build holds`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let outline = PDFExport.outline(of: document, built: built)
    #expect(outline.first?.anchor == DocumentTextBuilder.abstractAnchor)

    func all(_ entries: [PDFExport.OutlineEntry]) -> [PDFExport.OutlineEntry] {
      entries.flatMap { [$0] + all($0.children) }
    }
    // Every entry has somewhere to go.
    for entry in all(outline) {
      #expect(built.anchors.offset(of: entry.anchor) != nil, "no destination for \(entry.anchor)")
    }
    // The bibliography is in the panel, not the body, so not in the outline either.
    let listed = Set(all(outline).map(\.anchor))
    for section in document.allSections where section.holdsOnlyReferences {
      #expect(!listed.contains(section.anchor))
    }
    // Nested as the document nests them.
    let nested = try #require(document.sections.first { !$0.subsections.isEmpty })
    let entry = try #require(outline.first { $0.anchor == nested.anchor })
    #expect(entry.children.map(\.anchor) == nested.subsections.map(\.anchor))
    #expect(entry.title == nested.displayTitle)
  }

  @Test func `the file says what document it is`() {
    let header = DocumentHeader(
      id: .rfc(9999), title: "A Protocol", authors: [Author(name: "A. Writer", role: .editor)],
      keywords: ["examples"])
    let info = PDFExport.Info(header: header, metadata: nil)
    #expect(info.title == "RFC 9999: A Protocol")
    #expect(info.subject == "RFC 9999")
    #expect(info.author == "A. Writer, Ed.")
    #expect(info.keywords == ["examples"])
  }

  private let june = PublicationDate(year: 2026, month: 6)

  /// Keywords carry what the file's tags say too: the working group and the status.
  @Test func `the file's keywords include its working group and status`() {
    let header = DocumentHeader(
      id: .rfc(10042), title: "A Protocol", date: june, keywords: ["hybrid"])
    let metadata = RFCMetadata(
      id: .rfc(10042), title: "A Protocol", date: june, keywords: ["ignored"],
      currentStatus: .informational,
      workingGroup: "sshm")
    let info = PDFExport.Info(header: header, metadata: metadata)
    #expect(info.title == "RFC 10042: A Protocol")
    #expect(info.keywords == ["hybrid", "sshm", "Informational"])
  }

  @Test func `a document with no number is titled by its title alone`() {
    let info = PDFExport.Info(header: DocumentHeader(title: "A Protocol"), metadata: nil)
    #expect(info.title == "A Protocol")
    #expect(info.subject.isEmpty)
  }
}

@Suite("Export: placing things on the page")
struct ExportGeometryTests {
  typealias Page = PrintPagination.Page

  @Test func `a PDF page runs bottom-up`() {
    let rect = CGRect(x: 54, y: 100, width: 200, height: 20)
    #expect(
      PDFExport.pdfRect(rect, paperHeight: 792) == CGRect(x: 54, y: 672, width: 200, height: 20))
  }

  @Test func `a page puts its slice of the document at the top of the column`() {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    let page = Page(top: 600, bottom: 1200)
    let placed = layout.onPaper(CGRect(x: 10, y: 650, width: 100, height: 12), page: page)
    #expect(placed.minX == layout.contentRect.minX + 10)
    #expect(placed.minY == layout.contentRect.minY + 50)
  }

  /// A destination goes to its first line's top, which is where a page starts: a
  /// heading that opens a page is on that page, at the top of the column.
  @Test func `a heading that opens a page is placed on that page`() throws {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    let pages = [Page(top: 0, bottom: 100), Page(top: 110, bottom: 200)]
    let place = try #require(PDFExport.destination(lineTop: 110, pages: pages, layout: layout))
    #expect(place.page == 1)
    #expect(place.point.x == layout.contentRect.minX)
    #expect(place.point.y == layout.paperSize.height - layout.contentRect.minY)
    #expect(PDFExport.destination(lineTop: -1, pages: pages, layout: layout) == nil)
  }

  /// A link's words are on the page that holds their middle, in its PDF coordinates.
  @Test func `a link is placed on the page that holds its middle`() throws {
    let layout = PrintLayout(paperSize: PrintLayout.letter)
    let pages = [Page(top: 0, bottom: 100), Page(top: 110, bottom: 200)]
    let words = CGRect(x: 10, y: 120, width: 50, height: 12)
    let placed = try #require(PDFExport.linkBounds(words, pages: pages, layout: layout))
    #expect(placed.page == 1)
    #expect(
      placed.rect
        == PDFExport.pdfRect(
          layout.onPaper(words, page: pages[1]), paperHeight: layout.paperSize.height))
  }

  @Test func `a position is on the last page that starts above it`() {
    let pages = [
      Page(top: 0, bottom: 100), Page(top: 110, bottom: 200), Page(top: 200, bottom: 290),
    ]
    #expect(PrintPagination.page(containing: 0, in: pages) == 0)
    #expect(PrintPagination.page(containing: 105, in: pages) == 0)
    #expect(PrintPagination.page(containing: 110, in: pages) == 1)
    #expect(PrintPagination.page(containing: 250, in: pages) == 2)
    #expect(PrintPagination.page(containing: -1, in: pages) == nil)
    #expect(PrintPagination.page(containing: 0, in: []) == nil)
  }
}

/// The outline as it is in the file, read back from disk: PDFKit drops an outline
/// it is given when it writes the file, links and info intact (#990), so the
/// drawing writes it, and PDFKit's pass afterwards must keep it.
@Suite("Export: the outline in the written file")
struct ExportOutlineFileTests {
  private typealias Entry = PDFExport.OutlineEntry

  private let outline = [
    Entry(
      title: "Introduction", anchor: "section-1",
      children: [Entry(title: "Terminology", anchor: "section-1.1", children: [])]),
    Entry(
      title: "Not in the file", anchor: "elsewhere",
      children: [Entry(title: "Nor this", anchor: "section-1.2", children: [])]),
    Entry(title: "Security Considerations", anchor: "section-2", children: []),
  ]

  private let destinations = [
    "section-1": PDFExport.Place(page: 0, point: CGPoint(x: 54, y: 700)),
    "section-1.1": PDFExport.Place(page: 1, point: CGPoint(x: 54, y: 500)),
    "section-1.2": PDFExport.Place(page: 1, point: CGPoint(x: 54, y: 400)),
    "section-2": PDFExport.Place(page: 2, point: CGPoint(x: 54, y: 300)),
  ]

  @Test func `the outline survives the file being written`() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: file) }
    try written(pages: 3).write(to: file)
    let document = try #require(PDFDocument(url: file))
    let root = try #require(document.outlineRoot, "the written file has no outline")

    func children(of item: PDFOutline) -> [PDFOutline] {
      (0..<item.numberOfChildren).compactMap { item.child(at: $0) }
    }
    func place(of item: PDFOutline) -> PDFExport.Place? {
      guard let destination = item.destination, let page = destination.page else { return nil }
      return PDFExport.Place(page: document.index(for: page), point: destination.point)
    }
    // An entry with nowhere to go is left out, its subsections with it.
    let top = children(of: root)
    #expect(top.map(\.label) == ["Introduction", "Security Considerations"])
    #expect(top.map(place(of:)) == [destinations["section-1"], destinations["section-2"]])
    let nested = try #require(top.first.map(children(of:)))
    #expect(nested.map(\.label) == ["Terminology"])
    #expect(nested.map(place(of:)) == [destinations["section-1.1"]])
    // What PDFKit adds to the drawing is still there.
    #expect(document.page(at: 0)?.annotations.count == 1)
  }

  /// `count` blank pages with the outline, as the export makes them: drawn with
  /// it, then read by PDFKit, given a link and written again.
  private func written(pages count: Int) throws -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: PrintLayout.letter)
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
    for _ in 0..<count {
      context.beginPDFPage(nil)
      context.endPDFPage()
    }
    PDFExport.setOutline(outline, destinations: destinations, in: context)
    context.closePDF()

    let document = try #require(PDFDocument(data: data as Data))
    let link = PDFAnnotation(
      bounds: CGRect(x: 54, y: 600, width: 100, height: 12), forType: .link, withProperties: nil)
    link.url = URL(string: "https://www.rfc-editor.org/")
    try #require(document.page(at: 0)).addAnnotation(link)
    return try #require(document.dataRepresentation())
  }
}
