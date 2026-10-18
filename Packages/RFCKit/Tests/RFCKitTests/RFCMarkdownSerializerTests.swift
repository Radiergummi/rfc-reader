import Foundation
import Testing

@testable import RFCKit

/// The Markdown a document or a section is written as (#642, #377): one test per
/// block kind over hand-made model values, which are not RFC text, and the
/// guarantees over committed fixtures. No serialized output of a fixture is
/// committed: it would be RFC text.
@Suite("Markdown serializer")
struct RFCMarkdownSerializerTests {
  private static func markdown(
    _ blocks: [Block], links: InDocumentLinks = .fragments, id: DocumentID? = .rfc(9999)
  ) -> String {
    let document = RFCDocument(
      header: DocumentHeader(id: id, title: "A Protocol"),
      sections: [Section(anchor: "section-1", number: "1", title: "Body", blocks: blocks)],
      source: .xml)
    return RFCMarkdownSerializer(inDocumentLinks: links).serialize(
      document.sections[0], in: document, includingSubsections: false)
  }

  // MARK: Headings

  @Test func `a section's heading is at depth one and its subsections' below it`() {
    let section = Section(
      anchor: "section-4", number: "4", title: "Rules",
      subsections: [
        Section(
          anchor: "section-4.1", number: "4.1", title: "First",
          subsections: [Section(anchor: "section-4.1.1", number: "4.1.1", title: "Deeper")])
      ])
    let document = RFCDocument(
      header: DocumentHeader(title: "A Protocol"), sections: [section], source: .xml)
    let lines = RFCMarkdownSerializer().serialize(section, in: document).split(separator: "\n")
    #expect(lines.contains("# 4. Rules"))
    #expect(lines.contains("## 4.1. First"))
    #expect(lines.contains("### 4.1.1. Deeper"))
  }

  @Test func `a section asked for without its subsections leaves them out`() {
    let section = Section(
      anchor: "section-4", number: "4", title: "Rules",
      subsections: [Section(anchor: "section-4.1", number: "4.1", title: "First")])
    let document = RFCDocument(
      header: DocumentHeader(title: "A Protocol"), sections: [section], source: .xml)
    let markdown = RFCMarkdownSerializer().serialize(
      section, in: document, includingSubsections: false)
    #expect(!markdown.contains("First"))
  }

  @Test func `a whole document opens with its title, and its sections are one level down`() {
    let document = RFCDocument(
      header: DocumentHeader(
        id: .rfc(9999), title: "A Protocol", authors: [Author(name: "A. Writer", role: .editor)],
        date: PublicationDate(year: 2026, month: 6),
        abstract: [.paragraph(Paragraph(text: "What it does."))]),
      sections: [Section(anchor: "section-1", number: "1", title: "Introduction")],
      source: .xml)
    let lines = RFCMarkdownSerializer().serialize(document).split(separator: "\n")
    #expect(lines.first == "# A Protocol")
    #expect(lines.contains("RFC 9999 · June 2026 · A. Writer, Ed."))
    #expect(lines.contains("## Abstract"))
    #expect(lines.contains("What it does."))
    #expect(lines.contains("## 1. Introduction"))
  }

  @Test func `the abstract carries the anchor the reader gives it`() {
    let document = RFCDocument(
      header: DocumentHeader(
        id: .rfc(9999), title: "A Protocol", abstract: [.paragraph(Paragraph(text: "What."))]),
      sections: [], source: .xml)
    let markdown = RFCMarkdownSerializer().serialize(document)
    #expect(markdown.contains("<!-- anchor: abstract --><a id=\"abstract\"></a>\n## Abstract"))
  }

  // MARK: Paragraphs and inlines

  @Test func `a paragraph is reflowed onto one line`() {
    let markdown = Self.markdown([.paragraph(Paragraph(text: "one\n   two\tthree"))])
    #expect(markdown.contains("\none two three\n"))
  }

  @Test func `emphasis, strong text, code and links are marked up`() {
    let inlines: [Inline] = [
      .text("A "), .emphasis([.text("soft")]), .text(" and "), .strong([.text("hard")]),
      .text(" "), .code("x = 1"), .text(" "),
      .link(URL(string: "https://example.com/a")!, [.text("page")]), .text("."),
    ]
    let markdown = Self.markdown([.paragraph(Paragraph(inlines))])
    #expect(markdown.contains("A *soft* and **hard** `x = 1` [page](https://example.com/a)."))
  }

  @Test func `a code span's fence is longer than any backtick run in it`() {
    let markdown = Self.markdown([.paragraph(Paragraph([.code("a `b` c")]))])
    #expect(markdown.contains("``a `b` c``"))
  }

  @Test func `characters Markdown would read as markup are escaped`() {
    let markdown = Self.markdown([.paragraph(Paragraph(text: "a *b* [c] <d> e_f & g|h"))])
    #expect(markdown.contains(#"a \*b\* \[c\] \<d\> e\_f \& g\|h"#))
  }

  @Test func `a line that would open a heading, a list or a quotation is escaped`() {
    for (text, written) in [
      ("# not a heading", ##"\# not a heading"##), ("- not an item", #"\- not an item"#),
      ("1990. A year", #"1990\. A year"#), ("+ plus", #"\+ plus"#),
      ("> not quoted", #"\> not quoted"#),
    ] {
      let markdown = Self.markdown([.paragraph(Paragraph(text: text))])
      #expect(markdown.contains("\n\(written)\n"), "\(text)")
    }
  }

  @Test func `a line break is a hard break`() {
    let markdown = Self.markdown([
      .paragraph(Paragraph([.text("one"), .lineBreak, .text("- two")]))
    ])
    #expect(markdown.contains("one\\\n\\- two"))
  }

  // MARK: Anchors and links

  /// A Markdown renderer makes no target of a comment; an `<a id>` on the comment's
  /// line, which a comment's HTML block passes through as it is, is one, without
  /// taking the line after it into the block, as an element on a line of its own
  /// would.
  @Test func `an anchored block is preceded by its anchor, an id in an export`() {
    let blocks: [Block] = [
      .paragraph(Paragraph(text: "Text.", anchor: "section-1-1")),
      .preformatted(Preformatted(kind: .sourceCode, text: "x", anchor: "section-1-2")),
    ]
    let markdown = Self.markdown(blocks)
    #expect(markdown.hasPrefix("<!-- anchor: section-1 --><a id=\"section-1\"></a>\n# 1. Body"))
    #expect(markdown.contains("<!-- anchor: section-1-1 --><a id=\"section-1-1\"></a>\nText."))
    #expect(markdown.contains("<!-- anchor: section-1-2 --><a id=\"section-1-2\"></a>\n```"))
  }

  /// Text read apart from its document links to rfc-editor.org, not to ids: the
  /// MCP server's, by #642's spec.
  @Test func `text read apart from its document carries its anchors as comments alone`() {
    let markdown = Self.markdown(
      [.paragraph(Paragraph(text: "Text.", anchor: "section-1-1"))], links: .absolute)
    #expect(markdown.contains("<!-- anchor: section-1-1 -->\nText."))
    #expect(!markdown.contains("<a id="))
  }

  @Test func `a reference within the document links to its anchor in an export`() {
    let reference = CrossReference(target: .anchor("section-1"), text: "Section 1")
    let markdown = Self.markdown([.paragraph(Paragraph([.crossReference(reference)]))])
    #expect(markdown.contains("[Section 1](#section-1)"))
  }

  @Test func `a reference within the document links to rfc-editor.org when asked`() {
    let reference = CrossReference(target: .anchor("section-2"), text: "Section 2")
    let markdown = Self.markdown(
      [.paragraph(Paragraph([.crossReference(reference)]))], links: .absolute)
    #expect(markdown.contains("[Section 2](https://www.rfc-editor.org/rfc/rfc9999#section-2)"))
  }

  @Test func `a section number a reference names links to the section's anchor`() {
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(9999), title: "A Protocol"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "One",
          blocks: [
            .paragraph(
              Paragraph([.crossReference(CrossReference(target: .anchor("2"), text: "two"))]))
          ]),
        Section(anchor: "rules", number: "2", title: "Two"),
      ], source: .xml)
    #expect(RFCMarkdownSerializer().serialize(document).contains("[two](#rules)"))
  }

  @Test func `a reference to another document links to its page`() {
    let reference = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    let markdown = Self.markdown([.paragraph(Paragraph([.crossReference(reference)]))])
    let url = CitationFormatter.url(for: .rfc(9110), section: "4.2").absoluteString
    #expect(markdown.contains("[\(reference.display.text)](\(url))"))
  }

  // MARK: Lists

  @Test func `a bulleted list is a list of dashes`() {
    let list = ListBlock(style: .bullet, items: [ListItem(text: "one"), ListItem(text: "two")])
    #expect(Self.markdown([.list(list)]).contains("\n- one\n- two\n"))
  }

  @Test func `a numbered list keeps its source numbering`() {
    let list = ListBlock(
      style: .numbered(ListNumbering(start: 3)),
      items: [ListItem(text: "three"), ListItem(text: "four")])
    #expect(Self.markdown([.list(list)]).contains("\n3. three\n4. four\n"))
  }

  @Test func `a numbering Markdown has no list for keeps its markers`() {
    let list = ListBlock(
      style: .numbered(ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")")),
      items: [ListItem(text: "first"), ListItem(text: "second")])
    #expect(Self.markdown([.list(list)]).contains("\n- (a) first\n- (b) second\n"))
  }

  @Test func `an item's further blocks are indented under its marker`() {
    let item = ListItem(blocks: [
      .paragraph(Paragraph(text: "first")), .paragraph(Paragraph(text: "more")),
    ])
    let list = ListBlock(style: .numbered(ListNumbering()), items: [item])
    #expect(Self.markdown([.list(list)]).contains("\n1. first\n\n   more\n"))
  }

  @Test func `a list whose items carry anchors stays tight`() {
    let list = ListBlock(
      style: .bullet,
      items: [
        ListItem(blocks: [.paragraph(Paragraph(text: "one"))], anchor: "s-1"),
        ListItem(blocks: [.paragraph(Paragraph(text: "two"))], anchor: "s-2"),
      ])
    #expect(
      Self.markdown([.list(list)]).contains(
        "\n- <!-- anchor: s-1 --><a id=\"s-1\"></a>\n  one\n- <!-- anchor: s-2 --><a id=\"s-2\"></a>\n  two\n"
      ))
  }

  /// A marker CommonMark has no list for, ahead of a fence, would stop it being one.
  @Test func `a marker ahead of anything but a paragraph stands on its own line`() {
    let item = ListItem(blocks: [.preformatted(Preformatted(kind: .sourceCode, text: "x = 1"))])
    let list = ListBlock(
      style: .numbered(ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")")),
      items: [item])
    #expect(Self.markdown([.list(list)]).contains("\n- (a)\n\n  ```\n  x = 1\n  ```\n"))
  }

  @Test func `a marker ahead of an empty paragraph and a fence stands on its own line`() {
    let item = ListItem(blocks: [
      .paragraph(Paragraph(text: "")),
      .preformatted(Preformatted(kind: .sourceCode, text: "x = 1")),
    ])
    let list = ListBlock(
      style: .numbered(ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")")),
      items: [item])
    #expect(Self.markdown([.list(list)]).contains("\n- (a)\n\n  ```\n  x = 1\n  ```\n"))
  }

  @Test func `two lists in a row are kept apart`() {
    let first = ListBlock(style: .bullet, items: [ListItem(text: "one")])
    let second = ListBlock(style: .bullet, items: [ListItem(text: "two")])
    #expect(Self.markdown([.list(first), .list(second)]).contains("- one\n\n<!-- -->\n\n- two"))
  }

  @Test func `a list after a block that ends with a list is kept apart from it`() {
    let first = ListBlock(style: .bullet, items: [ListItem(text: "one")])
    let second = ListBlock(style: .bullet, items: [ListItem(text: "two")])
    let figure = Figure(title: nil, blocks: [.paragraph(Paragraph(text: "Fig.")), .list(first)])
    #expect(
      Self.markdown([.figure(figure), .list(second)]).contains("- one\n\n<!-- -->\n\n- two"))
  }

  @Test func `emphasis that opens or closes with punctuation is an element`() {
    let inlines: [Inline] = [.text("RFC"), .emphasis([.text("(opt)")]), .text("s")]
    #expect(Self.markdown([.paragraph(Paragraph(inlines))]).contains("RFC<em>(opt)</em>s"))
  }

  @Test func `a reference's label is reflowed`() {
    let reference = CrossReference(target: .anchor("section-1"), text: "Section 2 of\n   this")
    let markdown = Self.markdown([.paragraph(Paragraph([.crossReference(reference)]))])
    #expect(markdown.contains("[Section 2 of this](#section-1)"))
  }

  @Test func `a break with only spaces after it ends nothing`() {
    let markdown = Self.markdown([.paragraph(Paragraph([.text("a"), .lineBreak, .text("  ")]))])
    #expect(markdown.contains("\na\n"))
    #expect(!markdown.contains("a\\"))
  }

  @Test func `a definition list is a bold term with its definition indented under it`() {
    let list = DefinitionList([
      DefinitionItem(term: [.text("Term")], definition: [.paragraph(Paragraph(text: "Meaning."))])
    ])
    #expect(Self.markdown([.definitionList(list)]).contains("\n- **Term**\n\n  Meaning.\n"))
  }

  // MARK: Tables

  @Test func `a table of one-line cells is a GitHub table`() {
    let table = Table(
      title: "Codes", number: 2,
      header: [Table.Row(cells: [[.text("Code")], [.text("Meaning")]])],
      rows: [Table.Row(cells: [[.text("1")], [.text("a|b")]])])
    let markdown = Self.markdown([.table(table)])
    #expect(markdown.contains("| Code | Meaning |\n| --- | --- |\n| 1 | a\\|b |\n"))
    #expect(markdown.contains("*Table 2: Codes*"))
  }

  @Test func `a pipe in a table cell's code is escaped`() {
    let table = Table(
      title: nil, header: [Table.Row(cells: [[.text("Rule")]])],
      rows: [Table.Row(cells: [[.code("a|b")]])])
    #expect(Self.markdown([.table(table)]).contains("| `a\\|b` |"))
  }

  @Test func `a table with a cell of several lines is stacked`() {
    let table = Table(
      title: nil,
      header: [Table.Row(cells: [[.text("Code")], [.text("Meaning")]])],
      rows: [Table.Row(cells: [[.text("1")], [.text("one"), .lineBreak, .text("two")]])])
    let markdown = Self.markdown([.table(table)])
    #expect(markdown.contains("- **Code**: 1\\\n  **Meaning**: one\\\n  two\n"))
  }

  @Test func `a stacked cell's closing break breaks nothing`() {
    let table = Table(
      title: nil,
      header: [Table.Row(cells: [[.text("Code")], [.text("Meaning")]])],
      rows: [Table.Row(cells: [[.text("1")], [.text("one"), .lineBreak]])])
    #expect(Self.markdown([.table(table)]).contains("- **Code**: 1\\\n  **Meaning**: one\n"))
  }

  @Test func `an empty cell with no header adds no line to a stacked row`() {
    let table = Table(
      title: nil,
      header: [Table.Row(cells: [[.text("Code")]])],
      rows: [Table.Row(cells: [[.text("1")], [], [.text("a"), .lineBreak, .text("b")]])])
    #expect(Self.markdown([.table(table)]).contains("- **Code**: 1\\\n  a\\\n  b\n"))
  }

  // MARK: Verbatim, figures, asides

  @Test func `a preformatted block is fenced, with its type as the info string`() {
    let block = Preformatted(kind: .sourceCode, text: "rule = \"a\"\n", type: "ABNF")
    #expect(Self.markdown([.preformatted(block)]).contains("\n```abnf\nrule = \"a\"\n```\n"))
  }

  @Test func `a drawing has no info string, and a fence longer than any backtick run`() {
    let block = Preformatted(kind: .artwork, text: "+--+\n|```|", type: "ascii-art")
    #expect(Self.markdown([.preformatted(block)]).contains("\n````\n+--+\n|```|\n````\n"))
  }

  @Test func `a figure is its blocks and an italic caption`() {
    let figure = Figure(
      title: "A Box", number: 3, blocks: [.preformatted(Preformatted(kind: .artwork, text: "[]"))])
    #expect(Self.markdown([.figure(figure)]).contains("```\n[]\n```\n\n*Figure 3: A Box*"))
  }

  @Test func `an aside is a block quote`() {
    let aside = Block.aside([.paragraph(Paragraph(text: "Note: careful."))])
    #expect(Self.markdown([aside]).contains("\n> Note: careful.\n"))
  }

  // MARK: References

  @Test func `a reference entry has its tag, title, link and kind`() {
    let entry = Reference(
      anchor: "RFC2119", title: "Key words", authors: [Author(name: "S. Bradner")],
      date: PublicationDate(year: 1997, month: 3),
      seriesInfo: [SeriesInfo(name: "BCP", value: "14"), SeriesInfo(name: "RFC", value: "2119")])
    let list = ReferenceList(title: "Normative References", entries: [entry])
    let markdown = Self.markdown([.references(list)])
    let url = CitationFormatter.url(for: .rfc(2119)).absoluteString
    #expect(markdown.contains("<!-- anchor: RFC2119 -->"))
    #expect(
      markdown.contains(
        "**\\[RFC2119\\]** [Key words](\(url)). S. Bradner. BCP 14, RFC 2119, March 1997. Normative."
      ))
  }

  // MARK: Guarantees, over committed fixtures

  static let fixtures = [
    "rfc8999.xml", "rfc9197.xml", "rfc9290.xml", "rfc9682.xml", "rfc2119.txt", "rfc793.txt",
    "rfc1149.txt", "rfc5234.txt",
  ]

  @Test(arguments: fixtures)
  func `no prose is lost, and it comes in order`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let output = SerializedText.normalized(
      SerializedText.unescapingMarkdown(RFCMarkdownSerializer().serialize(document)))
    var cursor = output.startIndex
    for leaf in SerializedText.leaves(of: document) {
      let range = try #require(
        output.range(of: leaf, range: cursor..<output.endIndex), "\(fixture): \(leaf)")
      cursor = range.upperBound
    }
  }

  @Test(arguments: fixtures)
  func `every anchor appears once`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let markdown = RFCMarkdownSerializer().serialize(document)
    for (anchor, count) in SerializedText.anchorCounts(of: document) {
      #expect(
        markdown.components(separatedBy: "<!-- anchor: \(anchor) -->").count - 1 == count,
        "\(fixture): \(anchor)")
    }
  }

  @Test(arguments: fixtures)
  func `the same document is written the same way twice`(fixture: String) throws {
    let serializer = RFCMarkdownSerializer()
    let first = serializer.serialize(try Fixtures.parse(fixture))
    let second = serializer.serialize(try Fixtures.parse(fixture))
    #expect(first == second)
  }
}

/// What the serializers' guarantee tests compare: the words of a document, in the
/// order a reader meets them, and how many times each anchor is in it.
enum SerializedText {
  /// Every run of words in the document, each as written, in reading order: the
  /// abstract, then each section's heading, its blocks and its subsections. A
  /// table's header cells are left out, which a stacked table repeats per row.
  static func leaves(of document: RFCDocument) -> [String] {
    var leaves: [String] = []
    func add(_ text: String) {
      let normalized = normalized(text)
      if !normalized.isEmpty { leaves.append(normalized) }
    }
    func visit(_ inlines: [Inline]) {
      for inline in inlines {
        switch inline {
        case .text(let text), .code(let text), .superscript(let text), .subscript(let text):
          add(text)
        case .emphasis(let inner), .strong(let inner), .link(_, let inner): visit(inner)
        case .crossReference(let reference): add(reference.display.text)
        case .lineBreak: break
        }
      }
    }
    func visit(_ block: Block) {
      switch block {
      case .paragraph(let paragraph): visit(paragraph.inlines)
      case .list(let list): list.items.flatMap(\.blocks).forEach(visit)
      case .definitionList(let list):
        for item in list.items {
          visit(item.term)
          item.definition.forEach(visit)
        }
      case .preformatted(let content):
        for line in content.text.split(separator: "\n") { add(String(line)) }
      case .figure(let figure): figure.blocks.forEach(visit)
      case .table(let table): table.rows.flatMap(\.cells).forEach(visit)
      case .blockQuote(let blocks), .aside(let blocks): blocks.forEach(visit)
      case .references(let list): list.entries.map(\.annotation).forEach(visit)
      case .index(let index):
        visit(.definitionList(IndexBlock.definitionList(index.groups.flatMap(\.entries))))
      }
    }
    func visit(_ section: Section) {
      visit(section.title)
      section.blocks.forEach(visit)
      section.subsections.forEach(visit)
    }
    document.header.abstract.forEach(visit)
    document.sections.forEach(visit)
    return leaves
  }

  /// How many times each anchor is in the document: its sections' and its blocks'.
  static func anchorCounts(of document: RFCDocument) -> [String: Int] {
    let anchors =
      document.allSections.map(\.anchor)
      + (document.header.abstract + document.allSections.flatMap(\.blocks)).flattened.flatMap(
        \.anchors)
    return anchors.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  /// `text` with each run of spaces, tabs and line breaks made one space.
  static func normalized(_ text: String) -> String {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
      .joined(separator: " ")
  }

  /// Markdown with its backslash escapes taken out, left to right, but for those in
  /// code, which has none.
  static func unescapingMarkdown(_ markdown: String) -> String {
    var inFence = false
    return markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      let opening = line.drop { $0 == " " || $0 == ">" }
      if opening.hasPrefix("```") {
        inFence.toggle()
        return String(line)
      }
      return inFence ? String(line) : unescapingLine(String(line))
    }.joined(separator: "\n")
  }

  private static func unescapingLine(_ line: String) -> String {
    var result = ""
    var escaping = false
    var span: Int?
    var characters = line[...]
    while let character = characters.first {
      if character == "`", !escaping {
        let run = characters.prefix { $0 == "`" }
        result += run
        characters = characters.dropFirst(run.count)
        span = span == nil ? run.count : (span == run.count ? nil : span)
        continue
      }
      characters = characters.dropFirst()
      if span != nil {
        result.append(character)
      } else if escaping {
        if !(character.isASCII && (character.isPunctuation || character.isSymbol)) {
          result.append("\\")
        }
        result.append(character)
        escaping = false
      } else if character == "\\" {
        escaping = true
      } else {
        result.append(character)
      }
    }
    return result
  }
}
