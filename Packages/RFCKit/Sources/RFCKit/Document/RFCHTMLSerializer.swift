import Foundation

/// Writes an `RFCDocument` as one self-contained page that reads like the reader
/// (#377): its type, cards behind artwork and tables, light and dark, and the
/// reader's anchors, so a link to a section of the page resolves.
///
/// The markup is XHTML, well-formed XML as well as HTML: every element closed, every
/// entity escaped, nothing only an HTML parser reads. The EPUB export (#408) wraps
/// the same body in content documents of its own, so the styling stays out of the
/// body, in `stylesheet`, which the page embeds and an EPUB replaces.
public struct RFCHTMLSerializer: Sendable {
  public init() {}

  /// The whole page: the document's body, under a head that names it and embeds
  /// `stylesheet`.
  public func page(_ document: RFCDocument) -> String {
    let title = Self.documentTitle(of: document.header)
    return """
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
      <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <title>\(Writer.escaped(title))</title>
      <style>
      \(Self.stylesheet)
      </style>
      </head>
      <body>
      \(body(document))
      </body>
      </html>

      """
  }

  /// What the page's `<body>` holds: the document's header, its abstract and its
  /// sections, each section an `<section>` with the section's anchor.
  public func body(_ document: RFCDocument) -> String {
    var writer = Writer(links: ExportLinks(document: document, inDocument: .fragments))
    writer.header(document)
    for section in document.sections {
      writer.section(section, level: 2)
    }
    return writer.output
  }
}

extension RFCHTMLSerializer {
  /// One content document of a document cut into several, as an EPUB is (#408).
  struct Chapter: Equatable {
    var file: String
    var title: String
    var body: String
  }

  /// `document` cut into the header and abstract, then one chapter per top-level
  /// section, with every link to an anchor qualified by the file it is in.
  func chapters(_ document: RFCDocument) -> [Chapter] {
    let front = "front.xhtml"
    let fileNames = document.sections.indices.map { "chapter-\($0 + 1).xhtml" }
    var files: [String: String] = [:]
    func place(_ anchors: [String], in file: String) {
      for anchor in anchors where files[anchor] == nil { files[anchor] = file }
    }
    // The abstract's anchor where the header writes it: not when there is no
    // abstract, nor when a section has the anchor (`Writer.header`).
    if Writer.writesAbstractAnchor(document) { place([FullTextIndex.abstractAnchor], in: front) }
    place(document.header.abstract.flattened.flatMap(\.anchors), in: front)
    for (section, file) in zip(document.sections, fileNames) {
      let sections = section.withSubsections
      place(
        sections.map(\.anchor) + sections.flatMap(\.blocks).flattened.flatMap(\.anchors), in: file)
    }
    var links = ExportLinks(document: document, inDocument: .fragments)
    links.chapterFiles = ExportLinks.ChapterFiles(files: files, fallback: front)

    var writer = Writer(links: links)
    writer.header(document)
    var chapters = [
      Chapter(file: front, title: Self.documentTitle(of: document.header), body: writer.output)
    ]
    for (section, file) in zip(document.sections, fileNames) {
      var writer = Writer(links: links)
      writer.section(section, level: 1)
      chapters.append(Chapter(file: file, title: Self.title(of: section), body: writer.output))
    }
    return chapters
  }

  /// What an exported document is called: `RFC 9110: HTTP Semantics`, the title
  /// alone, or the number alone; `Untitled` for one with neither, since a page's,
  /// a book's and a contents entry's title may not be empty.
  static func documentTitle(of header: DocumentHeader) -> String {
    let title = [
      header.id?.displayName, header.title.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ")
    return title.isEmpty ? "Untitled" : title
  }

  /// What a chapter or a contents entry calls `section`: its heading, or for one
  /// with neither number nor words, which a legacy RFC can have, its anchor, since a
  /// title and a link in a book's contents may not be empty.
  static func title(of section: Section) -> String {
    let title = section.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? section.anchor : title
  }

  /// `text` escaped for XML, as the page escapes it.
  static func escaped(_ text: String) -> String {
    Writer.escaped(text)
  }
}

extension RFCHTMLSerializer {
  fileprivate struct Writer {
    let links: ExportLinks
    var output = ""
    /// The ids written so far: an id is written once, so the page stays valid
    /// should the model carry an anchor twice.
    private var ids: Set<String> = []

    init(links: ExportLinks) {
      self.links = links
    }

    // MARK: Structure

    mutating func header(_ document: RFCDocument) {
      let header = document.header
      output += "<header>\n<h1>\(Self.escaped(header.title))</h1>\n"
      let byline = ExportLinks.byline(of: header)
      if !byline.isEmpty { output += "<p class=\"byline\">\(Self.escaped(byline))</p>\n" }
      output += "</header>\n"
      guard !header.abstract.isEmpty else { return }
      open(
        "section", id: Self.writesAbstractAnchor(document) ? FullTextIndex.abstractAnchor : nil,
        class: "abstract")
      output += "<h2>Abstract</h2>\n"
      blocks(header.abstract)
      output += "</section>\n"
    }

    /// Whether the abstract is written with the anchor the full-text index gives
    /// it: when there is one, and no section has the anchor.
    static func writesAbstractAnchor(_ document: RFCDocument) -> Bool {
      !document.header.abstract.isEmpty
        && !document.allSections.contains { $0.anchor == FullTextIndex.abstractAnchor }
    }

    mutating func section(_ section: Section, level: Int) {
      open("section", id: section.anchor)
      let heading = "h\(min(level, 6))"
      output += "<\(heading)>" + inlines(section.displayTitleInlines) + "</\(heading)>\n"
      blocks(section.blocks)
      for subsection in section.subsections {
        self.section(subsection, level: level + 1)
      }
      output += "</section>\n"
    }

    /// `<name id="…" class="…">`, the id left out when it is nil or already written.
    mutating func open(_ name: String, id: String? = nil, class className: String? = nil) {
      output += "<\(name)\(attributes(id: id, class: className))>"
      if ["section", "ul", "ol", "dl", "blockquote", "aside", "figure", "div", "table"].contains(
        name)
      {
        output += "\n"
      }
    }

    mutating func attributes(id: String?, class className: String?) -> String {
      var result = ""
      if let id, ids.insert(id).inserted { result += " id=\"\(Self.escaped(id))\"" }
      if let className { result += " class=\"\(className)\"" }
      return result
    }

    // MARK: Blocks

    mutating func blocks(_ blocks: [Block]) {
      for block in blocks { self.block(block) }
    }

    mutating func block(_ block: Block) {
      switch block {
      case .paragraph(let paragraph):
        open("p", id: paragraph.anchor, class: paragraph.indent > 0 ? "indented" : nil)
        output += inlines(paragraph.inlines) + "</p>\n"
      case .list(let list):
        self.list(list)
      case .definitionList(let list):
        definitionList(list)
      case .preformatted(let content):
        preformatted(content)
      case .figure(let figure):
        open("figure", id: figure.anchor)
        blocks(figure.blocks)
        if let caption = BlockCaption.text("Figure", number: figure.number, title: figure.title) {
          output += "<figcaption>\(Self.escaped(caption))</figcaption>\n"
        }
        output += "</figure>\n"
      case .table(let table):
        self.table(table)
      case .blockQuote(let inner):
        open("blockquote")
        blocks(inner)
        output += "</blockquote>\n"
      case .aside(let inner):
        open("aside")
        blocks(inner)
        output += "</aside>\n"
      case .references(let list):
        references(list)
      case .index(let index):
        self.index(index)
      }
    }

    mutating func list(_ list: ListBlock) {
      let compact = list.isCompact ? "compact" : nil
      switch list.style {
      case .bullet:
        items(list.items, in: "ul", class: compact, markers: nil)
      case .bare:
        items(
          list.items, in: "ul", class: ["bare", compact].compactMap { $0 }.joined(separator: " "),
          markers: nil)
      case .numbered(let numbering):
        let markers = list.items.indices.map { numbering.marker(at: $0) }
        items(
          list.items, in: "ol",
          class: ["marked", compact].compactMap { $0 }.joined(separator: " "),
          markers: markers)
      }
    }

    /// A list's items. A numbered list writes each item's marker as the source
    /// numbers it, which no list style can say for `(a)` or `Step 1:`.
    mutating func items(
      _ items: [ListItem], in name: String, class className: String?, markers: [String]?
    ) {
      open(name, class: className)
      for (index, item) in items.enumerated() {
        open("li", id: item.anchor)
        if let markers {
          output += "<span class=\"marker\">\(Self.escaped(markers[index]))</span>"
        }
        blocks(item.blocks)
        output += "</li>\n"
      }
      output += "</\(name)>\n"
    }

    mutating func definitionList(_ list: DefinitionList) {
      let classes = [list.isCompact ? "compact" : nil, list.hangsTerms ? "hanging" : nil]
        .compactMap { $0 }
      open("dl", class: classes.isEmpty ? nil : classes.joined(separator: " "))
      for item in list.items {
        open("dt", id: item.anchor)
        output += inlines(item.term) + "</dt>\n"
        open("dd", id: item.definitionAnchor)
        blocks(item.definition)
        output += "</dd>\n"
      }
      output += "</dl>\n"
    }

    mutating func preformatted(_ content: Preformatted) {
      var text = content.text
      while text.hasSuffix("\n") { text.removeLast() }
      let kind = content.kind == .artwork ? "artwork" : "sourcecode"
      open("pre", id: content.anchor, class: kind)
      output += "<code>\(Self.escaped(text))</code></pre>\n"
    }

    mutating func table(_ table: Table) {
      open("div", class: "table")
      open("table", id: table.anchor)
      if let caption = BlockCaption.text("Table", number: table.number, title: table.title) {
        output += "<caption>\(Self.escaped(caption))</caption>\n"
      }
      for (group, rows, cell) in [("thead", table.header, "th"), ("tbody", table.rows, "td")]
      where !rows.isEmpty {
        output += "<\(group)>\n"
        for row in rows {
          open("tr", id: row.anchor)
          for content in row.cells {
            output += "<\(cell)>" + inlines(content) + "</\(cell)>"
          }
          output += "</tr>\n"
        }
        output += "</\(group)>\n"
      }
      output += "</table>\n</div>\n"
    }

    mutating func references(_ list: ReferenceList) {
      let kind = ExportLinks.kindName(list.kind)
      open("dl", class: "references")
      for entry in list.entries {
        open("dt", id: entry.anchor)
        output += Self.escaped("[\(entry.displayAnchor)]") + "</dt>\n<dd>"
        var parts: [String] = []
        let title = entry.title.isEmpty ? (entry.rawText ?? "") : entry.title
        if !title.isEmpty {
          let escaped = Self.escaped(title)
          if let url = ExportLinks.url(of: entry) {
            parts.append("<a href=\"\(Self.escaped(url.absoluteString))\">\(escaped)</a>.")
          } else {
            parts.append(escaped + ".")
          }
        }
        let authors = entry.authors.map(\.displayName).joined(separator: ", ")
        if !authors.isEmpty { parts.append(Self.escaped(authors) + ".") }
        let provenance = entry.provenance(separator: ", ")
        if !provenance.isEmpty { parts.append(Self.escaped(provenance) + ".") }
        if !entry.annotation.isEmpty { parts.append(inlines(entry.annotation)) }
        if let kind { parts.append("<span class=\"kind\">\(kind).</span>") }
        output += parts.joined(separator: " ") + "</dd>\n"
      }
      output += "</dl>\n"
    }

    mutating func index(_ index: IndexBlock) {
      open("div", id: IndexBlock.anchor, class: "index")
      for group in index.groups {
        open("p", id: group.anchor, class: "letter")
        output += Self.escaped(group.label) + "</p>\n"
        definitionList(IndexBlock.definitionList(group.entries))
      }
      output += "</div>\n"
    }

    // MARK: Inlines

    func inlines(_ inlines: [Inline]) -> String {
      var result = ""
      for inline in inlines {
        switch inline {
        case .text(let text): result += Self.escaped(text)
        case .emphasis(let inner): result += "<em>" + self.inlines(inner) + "</em>"
        case .strong(let inner): result += "<strong>" + self.inlines(inner) + "</strong>"
        case .code(let code): result += "<code>" + Self.escaped(code) + "</code>"
        case .superscript(let text): result += "<sup>" + Self.escaped(text) + "</sup>"
        case .subscript(let text): result += "<sub>" + Self.escaped(text) + "</sub>"
        case .link(let url, let inner):
          let text = self.inlines(inner)
          result +=
            "<a href=\"\(Self.escaped(url.absoluteString))\">"
            + (text.isEmpty ? Self.escaped(url.absoluteString) : text) + "</a>"
        case .crossReference(let reference):
          result +=
            "<a class=\"xref\" href=\"\(Self.escaped(links.href(for: reference)))\">"
            + Self.escaped(reference.display.text) + "</a>"
        case .lineBreak: result += "<br/>"
        }
      }
      return result
    }

    /// `text` as XML character data or an attribute's value: the five characters
    /// markup reads escaped, and the control characters XML 1.0 has no place for
    /// left out.
    static func escaped(_ text: String) -> String {
      var result = ""
      result.reserveCapacity(text.utf8.count)
      for scalar in text.unicodeScalars {
        switch scalar {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        case "'": result += "&#39;"
        case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
        case _ where scalar.value < 0x20 || (0xFFFE...0xFFFF).contains(scalar.value): break
        default: result.unicodeScalars.append(scalar)
        }
      }
      return result
    }
  }
}

extension RFCHTMLSerializer {
  /// The page's look: the reader's system type and measure, cards behind artwork and
  /// tables, and its colors in light and dark. No `<` or `&` in it, so it embeds in
  /// XHTML as it is.
  public static let stylesheet = """
    :root {
      color-scheme: light dark;
      --text: #1d1d1f;
      --secondary: #6e6e73;
      --background: #ffffff;
      --card: #f5f5f7;
      --rule: #d2d2d7;
      --link: #0066cc;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --text: #f5f5f7;
        --secondary: #a1a1a6;
        --background: #1d1d1f;
        --card: #2c2c2e;
        --rule: #424245;
        --link: #4da3ff;
      }
    }
    body {
      margin: 0 auto;
      padding: 2rem 1.25rem 4rem;
      max-width: 42rem;
      font: 17px/1.5 -apple-system, BlinkMacSystemFont, system-ui, "Helvetica Neue", sans-serif;
      color: var(--text);
      background: var(--background);
      -webkit-text-size-adjust: 100%;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; font-weight: 600; margin: 2em 0 0.5em; }
    h1 { font-size: 1.75rem; margin-top: 0; }
    h2 { font-size: 1.35rem; }
    h3 { font-size: 1.15rem; }
    h4, h5, h6 { font-size: 1rem; }
    .byline { color: var(--secondary); font-size: 0.9rem; }
    p, ul, ol, dl, figure, blockquote, aside, pre, .table { margin: 0 0 1em; }
    p.indented { margin-left: 2em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 0.88em; }
    pre {
      background: var(--card);
      border-radius: 8px;
      padding: 0.75em 1em;
      overflow-x: auto;
      line-height: 1.35;
    }
    pre code { font-size: inherit; }
    figure { margin-left: 0; margin-right: 0; }
    figcaption, caption { color: var(--secondary); font-size: 0.85rem; text-align: center; padding-top: 0.4em; }
    caption { caption-side: bottom; }
    .table { overflow-x: auto; background: var(--card); border-radius: 8px; padding: 0.5em 0.75em; }
    table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
    th, td { text-align: left; vertical-align: top; padding: 0.35em 0.6em; border-bottom: 1px solid var(--rule); }
    tbody tr:last-child td { border-bottom: none; }
    blockquote, aside { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--secondary); }
    ul.bare, ol.marked { list-style: none; }
    ul.bare { padding-left: 1.5em; }
    ol.marked { padding-left: 2.5em; }
    ol.marked li { position: relative; }
    ol.marked .marker { position: absolute; left: -2.5em; width: 2.2em; text-align: right; }
    li p, dd p { margin-bottom: 0.5em; }
    .compact li p, dl.compact dd p { margin-bottom: 0.15em; }
    dt { font-weight: 600; }
    dd { margin: 0 0 0.75em 2em; }
    dl.references dt { font-weight: 600; }
    dl.references .kind { color: var(--secondary); }
    .index .letter { font-weight: 600; margin-top: 1.5em; }
    """
}
