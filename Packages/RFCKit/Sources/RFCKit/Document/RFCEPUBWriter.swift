import Foundation

/// Writes an `RFCDocument` as an EPUB 3 book (#408): the HTML export's body, cut
/// into one content document per top-level section, as #408 decided for the reading
/// app's sake, with a navigation document from the section tree and a
/// stylesheet that leaves color and the body font to the reading app.
///
/// The archive stores every entry uncompressed (`StoredZip`), and the same document
/// makes the same bytes.
public struct RFCEPUBWriter: Sendable {
  /// The document what is written is a part of (#386); see
  /// `RFCMarkdownSerializer.outside`.
  public var outside: DocumentID?

  public init(outside: DocumentID? = nil) {
    self.outside = outside
  }

  public func epub(_ document: RFCDocument) -> Data {
    StoredZip.archive(entries(document))
  }

  /// The book's files, in archive order: `mimetype` first, as EPUB asks.
  func entries(_ document: RFCDocument) -> [StoredZip.Entry] {
    let chapters = RFCHTMLSerializer(outside: outside).chapters(document)
    var entries = [
      StoredZip.Entry(path: "mimetype", data: Data("application/epub+zip".utf8)),
      StoredZip.Entry(path: "META-INF/container.xml", data: Data(Self.container.utf8)),
      StoredZip.Entry(
        path: "OEBPS/content.opf", data: Data(Self.package(document, chapters: chapters).utf8)),
      StoredZip.Entry(
        path: "OEBPS/nav.xhtml", data: Data(Self.navigation(document, chapters: chapters).utf8)),
      StoredZip.Entry(path: "OEBPS/style.css", data: Data(Self.stylesheet.utf8)),
    ]
    for chapter in chapters {
      entries.append(
        StoredZip.Entry(path: "OEBPS/" + chapter.file, data: Data(Self.content(chapter).utf8)))
    }
    return entries
  }

  private static let container = """
    <?xml version="1.0" encoding="utf-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>

    """

  /// The book's identifier: an RFC's DOI, `10.17487/RFC9110`, and for a document of
  /// another series its page on rfc-editor.org.
  static func identifier(of header: DocumentHeader) -> String {
    guard let id = header.id else { return "urn:rfc-reader:untitled" }
    if id.series == .rfc { return "urn:doi:10.17487/RFC\(id.number)" }
    return CitationFormatter.url(for: id).absoluteString
  }

  static func package(_ document: RFCDocument, chapters: [RFCHTMLSerializer.Chapter]) -> String {
    let header = document.header
    var metadata = [
      "<dc:identifier id=\"book-id\">\(escaped(identifier(of: header)))</dc:identifier>",
      "<dc:title>\(escaped(RFCHTMLSerializer.documentTitle(of: header)))</dc:title>",
      "<dc:language>en</dc:language>",
    ]
    metadata += header.authors.map { "<dc:creator>\(escaped($0.name))</dc:creator>" }
    if let date = header.date {
      metadata.append("<dc:date>\(w3cDate(date))</dc:date>")
    }
    metadata.append("<dc:publisher>RFC Editor</dc:publisher>")
    // Required, and dated by the document rather than the export, so the same
    // document makes the same book.
    let modified = header.date.map(w3cDate) ?? "1980"
    metadata.append(
      "<meta property=\"dcterms:modified\">\(timestamp(modified))</meta>")

    let manifest =
      [
        "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
        "<item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>",
      ]
      + chapters.enumerated().map { index, chapter in
        "<item id=\"c\(index)\" href=\"\(chapter.file)\" media-type=\"application/xhtml+xml\"/>"
      }
    let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }
    return """
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="en">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
      \(metadata.joined(separator: "\n"))
      </metadata>
      <manifest>
      \(manifest.joined(separator: "\n"))
      </manifest>
      <spine>
      \(spine.joined(separator: "\n"))
      </spine>
      </package>

      """
  }

  /// `2022-06`, `2022`: as much of the date as the document gives, and no day the
  /// month does not have.
  static func w3cDate(_ date: PublicationDate) -> String {
    func padded(_ value: Int, to width: Int) -> String {
      let digits = String(value)
      return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    var parts = [padded(date.year, to: 4)]
    if let month = date.month, (1...12).contains(month) {
      parts.append(padded(month, to: 2))
      if let day = date.day, isDay(day, of: month, in: date.year) {
        parts.append(padded(day, to: 2))
      }
    }
    return parts.joined(separator: "-")
  }

  static func isDay(_ day: Int, of month: Int, in year: Int) -> Bool {
    let components = DateComponents(year: year, month: month, day: day)
    return components.isValidDate(in: Calendar(identifier: .gregorian))
  }

  /// `date` as a whole timestamp, its missing parts the first of each.
  static func timestamp(_ date: String) -> String {
    var parts = date.split(separator: "-").map(String.init)
    while parts.count < 3 { parts.append("01") }
    return parts.joined(separator: "-") + "T00:00:00Z"
  }

  /// The navigation document: the abstract, then the sections as the document nests
  /// them, each linking into the chapter that holds it.
  static func navigation(_ document: RFCDocument, chapters: [RFCHTMLSerializer.Chapter]) -> String {
    let files = chapters.map(\.file)
    func item(_ section: Section, file: String) -> String {
      let link =
        "<a href=\"\(file)#\(escaped(section.anchor))\">\(escaped(RFCHTMLSerializer.title(of: section)))</a>"
      guard !section.subsections.isEmpty else { return "<li>\(link)</li>" }
      let children = section.subsections.map { item($0, file: file) }
      return "<li>\(link)\n<ol>\n\(children.joined(separator: "\n"))\n</ol></li>"
    }
    var items = ["<li><a href=\"\(files[0])\">\(escaped(chapters[0].title))</a></li>"]
    for (section, file) in zip(document.sections, files.dropFirst()) {
      items.append(item(section, file: file))
    }
    return """
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
      <head>
      <meta charset="utf-8"/>
      <title>Contents</title>
      </head>
      <body>
      <nav epub:type="toc" id="toc">
      <h1>Contents</h1>
      <ol>
      \(items.joined(separator: "\n"))
      </ol>
      </nav>
      </body>
      </html>

      """
  }

  static func content(_ chapter: RFCHTMLSerializer.Chapter) -> String {
    """
    <?xml version="1.0" encoding="utf-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>\(escaped(chapter.title))</title>
    <link rel="stylesheet" type="text/css" href="style.css"/>
    </head>
    <body>
    \(chapter.body)
    </body>
    </html>

    """
  }

  private static func escaped(_ text: String) -> String {
    RFCHTMLSerializer.escaped(text)
  }

  /// The book's look: the reader's structure, without its colors or body font, which
  /// the reading app's themes and its reader's choice set. Artwork is set small
  /// enough that 72 columns fit an iPad's page, and scrolls where they do not.
  public static let stylesheet = """
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; font-weight: bold; margin: 1.5em 0 0.5em; }
    h1 { font-size: 1.5em; }
    h2 { font-size: 1.3em; }
    h3 { font-size: 1.15em; }
    h4, h5, h6 { font-size: 1em; }
    .byline { font-size: 0.9em; opacity: 0.75; }
    p, ul, ol, dl, figure, blockquote, aside, pre, .table { margin: 0 0 0.8em; }
    p.indented { margin-left: 2em; }
    code, pre { font-family: ui-monospace, Menlo, Courier, monospace; }
    code { font-size: 0.9em; }
    pre {
      font-size: 0.7em;
      line-height: 1.3;
      white-space: pre;
      overflow-x: auto;
      padding: 0.5em 0;
    }
    pre code { font-size: inherit; }
    figure { margin-left: 0; margin-right: 0; }
    figcaption, caption { font-size: 0.85em; text-align: center; padding-top: 0.3em; }
    caption { caption-side: bottom; }
    .table { overflow-x: auto; }
    table { border-collapse: collapse; font-size: 0.9em; }
    th, td { text-align: left; vertical-align: top; padding: 0.3em 0.5em; border-bottom: 1px solid rgba(128, 128, 128, 0.4); }
    blockquote, aside { margin-left: 0; padding-left: 1em; border-left: 3px solid rgba(128, 128, 128, 0.4); }
    ul.bare, ol.marked { list-style: none; }
    ul.bare { padding-left: 1.5em; }
    ol.marked { padding-left: 2.5em; }
    ol.marked li { position: relative; }
    ol.marked .marker { position: absolute; left: -2.5em; width: 2.2em; text-align: right; }
    dt { font-weight: bold; }
    dd { margin: 0 0 0.6em 2em; }
    .index .letter { font-weight: bold; margin-top: 1.2em; }
    """
}
