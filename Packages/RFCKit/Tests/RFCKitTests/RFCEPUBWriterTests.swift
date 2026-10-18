import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// The EPUB a document is exported as (#408): a stored zip whose `mimetype` comes
/// first, a package and navigation that name every content document, one content
/// document per top-level section, and links that find their anchor in the file
/// they name. Committed fixtures for the guarantees; no book is committed.
@Suite("EPUB writer")
struct RFCEPUBWriterTests {
  @Test func `the checksum is zip's CRC-32`() {
    #expect(StoredZip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    #expect(StoredZip.crc32(Data()) == 0)
  }

  @Test func `a stored archive reads back as its entries`() throws {
    let entries = [
      StoredZip.Entry(path: "mimetype", data: Data("application/epub+zip".utf8)),
      StoredZip.Entry(path: "OEBPS/a.xhtml", data: Data("<p>é</p>".utf8)),
    ]
    let read = try ZipReading.entries(of: StoredZip.archive(entries))
    #expect(read.map(\.path) == entries.map(\.path))
    #expect(read.map(\.data) == entries.map(\.data))
  }

  @Test func `the mimetype entry is first, stored, and says EPUB`() throws {
    let book = RFCEPUBWriter().epub(try Fixtures.document("rfc8999.xml"))
    // The bytes a reader sniffs: the local header's name at offset 30, then the type.
    #expect(book.subdata(in: 30..<38) == Data("mimetype".utf8))
    #expect(book.subdata(in: 38..<58) == Data("application/epub+zip".utf8))
    #expect(book[8] == 0 && book[9] == 0)
  }

  @Test func `an RFC is identified by its DOI, and dated by its publication`() throws {
    let header = DocumentHeader(
      id: .rfc(9110), title: "HTTP Semantics", authors: [Author(name: "R. Fielding")],
      date: PublicationDate(year: 2022, month: 6))
    let document = RFCDocument(header: header, sections: [], source: .xml)
    let package = RFCEPUBWriter.package(
      document, chapters: RFCHTMLSerializer().chapters(document))
    #expect(
      package.contains("<dc:identifier id=\"book-id\">urn:doi:10.17487/RFC9110</dc:identifier>"))
    #expect(package.contains("<dc:title>RFC 9110: HTTP Semantics</dc:title>"))
    #expect(package.contains("<dc:creator>R. Fielding</dc:creator>"))
    #expect(package.contains("<dc:date>2022-06</dc:date>"))
    #expect(package.contains("<meta property=\"dcterms:modified\">2022-06-01T00:00:00Z</meta>"))
  }

  /// A legacy RFC can have a section with neither number nor words; a book's
  /// titles and contents entries may not be empty, so it is called by its anchor.
  @Test func `an untitled section is called by its anchor`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "A Protocol"),
      sections: [Section(anchor: "section-0", title: "")], source: .text)
    #expect(RFCHTMLSerializer().chapters(document)[1].title == "section-0")
    #expect(RFCEPUBWriter.navigation(document).contains("#section-0\">section-0</a>"))
  }

  /// Books' themes set the colors and the body font; the book's stylesheet leaves
  /// them alone, and sets artwork small, scrolling where it is still too wide.
  @Test func `the stylesheet leaves color and the body font to the reading app`() {
    let style = RFCEPUBWriter.stylesheet
    #expect(!style.contains("color:"))
    #expect(!style.contains("background"))
    #expect(!style.contains("body"))
    #expect(style.contains("overflow-x: auto"))
  }

  // MARK: Guarantees, over committed fixtures

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `every file is well-formed, and every link finds its anchor`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let entries = try ZipReading.entries(of: RFCEPUBWriter().epub(document))
    #expect(entries.first?.path == "mimetype")
    var ids: [String: Set<String>] = [:]
    var links: [(file: String, href: String)] = []
    for entry in entries
    where entry.path.hasSuffix(".xhtml") || entry.path.hasSuffix(".xml")
      || entry.path.hasSuffix(".opf")
    {
      let reader = MarkupReader()
      let parser = XMLParser(data: entry.data)
      parser.delegate = reader
      #expect(parser.parse(), "\(fixture) \(entry.path): \(String(describing: parser.parserError))")
      let name = String(entry.path.split(separator: "/").last ?? "")
      ids[name] = reader.ids
      links += reader.hrefs.map { (name, $0) }
    }
    let chapters = RFCHTMLSerializer().chapters(document).map(\.file)
    #expect(chapters.count == document.sections.count + 1)
    for chapter in chapters { #expect(ids[chapter] != nil, "\(fixture): \(chapter) is packaged") }
    for (file, href) in links where !href.contains(":") {
      let parts = href.split(separator: "#", maxSplits: 1).map(String.init)
      let target = parts[0].isEmpty ? file : parts[0]
      let anchors = try #require(ids[target], "\(fixture): \(file) links to \(href)")
      if parts.count == 2 {
        #expect(anchors.contains(parts[1]), "\(fixture): \(file) links to \(href)")
      }
    }
  }

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `no prose is lost across the chapters`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    var text = ""
    for chapter in RFCHTMLSerializer().chapters(document) {
      let reader = MarkupReader()
      let parser = XMLParser(data: Data(RFCEPUBWriter.content(chapter).utf8))
      parser.delegate = reader
      _ = parser.parse()
      text += " " + reader.text
    }
    let normalized = SerializedText.normalized(text)
    var cursor = normalized.startIndex
    for leaf in SerializedText.leaves(of: document) {
      let range = try #require(
        normalized.range(of: leaf, range: cursor..<normalized.endIndex), "\(fixture): \(leaf)")
      cursor = range.upperBound
    }
  }

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `the same document makes the same book`(fixture: String) throws {
    let first = RFCEPUBWriter().epub(try Fixtures.parse(fixture))
    let second = RFCEPUBWriter().epub(try Fixtures.parse(fixture))
    #expect(first == second)
  }

  /// `make epubcheck` (#408): with `RFC_EPUB_OUTPUT` set, the fixtures' books are
  /// written there for epubcheck to validate. Skipped otherwise.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["RFC_EPUB_OUTPUT"] != nil),
    arguments: RFCMarkdownSerializerTests.fixtures)
  func `write the book for epubcheck`(fixture: String) throws {
    let directory = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RFC_EPUB_OUTPUT"]))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = (fixture as NSString).deletingPathExtension + ".epub"
    try RFCEPUBWriter().epub(try Fixtures.document(fixture))
      .write(to: directory.appending(path: name))
  }
}

/// The entries of a zip whose every entry is stored, read by their local headers.
enum ZipReading {
  struct Entry {
    var path: String
    var data: Data
  }

  struct Malformed: Error {}

  static func entries(of archive: Data) throws -> [Entry] {
    let bytes = [UInt8](archive)
    func value(at offset: Int, size: Int) -> Int {
      (0..<size).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
    }
    var entries: [Entry] = []
    var offset = 0
    while offset + 30 <= bytes.count, value(at: offset, size: 4) == 0x0403_4b50 {
      guard value(at: offset + 8, size: 2) == 0 else { throw Malformed() }
      let size = value(at: offset + 18, size: 4)
      let nameLength = value(at: offset + 26, size: 2)
      let extra = value(at: offset + 28, size: 2)
      let nameStart = offset + 30
      let dataStart = nameStart + nameLength + extra
      guard dataStart + size <= bytes.count,
        let path = String(bytes: bytes[nameStart..<nameStart + nameLength], encoding: .utf8)
      else { throw Malformed() }
      let data = Data(bytes[dataStart..<dataStart + size])
      guard StoredZip.crc32(data) == UInt32(value(at: offset + 14, size: 4)) else {
        throw Malformed()
      }
      entries.append(Entry(path: path, data: data))
      offset = dataStart + size
    }
    guard value(at: offset, size: 4) == 0x0201_4b50 else { throw Malformed() }
    return entries
  }
}

/// A content document's character data, its ids and its links.
private final class MarkupReader: NSObject, XMLParserDelegate {
  var text = ""
  var ids: Set<String> = []
  var hrefs: [String] = []

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String] = [:]
  ) {
    if let id = attributes["id"] { ids.insert(id) }
    if elementName == "a", let href = attributes["href"] { hrefs.append(href) }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }
}
