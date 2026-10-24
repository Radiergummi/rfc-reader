import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// The page a document is exported as (#377): well-formed XHTML, the reader's
/// anchors, and nothing of the text lost. Hand-made model values for the markup of
/// each kind, committed fixtures for the guarantees; no serialized fixture is
/// committed, which would be RFC text.
@Suite("HTML serializer")
struct RFCHTMLSerializerTests {
  private static func body(_ blocks: [Block]) -> String {
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(9999), title: "A Protocol"),
      sections: [Section(anchor: "section-1", number: "1", title: "Body", blocks: blocks)],
      source: .xml)
    return RFCHTMLSerializer().body(document)
  }

  @Test func `a section is a section element with its anchor and a heading`() {
    let body = Self.body([.paragraph(Paragraph(text: "Text.", anchor: "section-1-1"))])
    #expect(body.contains("<section id=\"section-1\">\n<h2>1. Body</h2>"))
    #expect(body.contains("<p id=\"section-1-1\">Text.</p>"))
  }

  @Test func `markup in the text is escaped`() {
    let body = Self.body([.paragraph(Paragraph(text: "a < b && \"c\""))])
    #expect(body.contains("a &lt; b &amp;&amp; &quot;c&quot;"))
  }

  @Test func `a control character XML cannot carry is left out`() {
    let body = Self.body([.paragraph(Paragraph(text: "a\u{0C}b"))])
    #expect(body.contains("<p>ab</p>"))
  }

  @Test func `inlines are their elements, and a break is self-closed`() {
    let body = Self.body([
      .paragraph(
        Paragraph([
          .emphasis([.text("e")]), .strong([.text("s")]), .code("c"), .lineBreak,
          .crossReference(CrossReference(target: .anchor("section-1"), text: "here")),
        ]))
    ])
    #expect(
      body.contains(
        "<em>e</em><strong>s</strong><code>c</code><br/><a class=\"xref\" href=\"#section-1\">here</a>"
      ))
  }

  @Test func `a numbered list writes its source markers`() {
    let list = ListBlock(
      style: .numbered(ListNumbering(counter: .lowerAlpha, prefix: "(", suffix: ")")),
      items: [ListItem(text: "first")])
    #expect(
      Self.body([.list(list)]).contains("<li><span class=\"marker\">(a)</span><p>first</p>\n</li>"))
  }

  @Test func `artwork is preformatted, escaped as written`() {
    let body = Self.body([.preformatted(Preformatted(kind: .artwork, text: "<a>\n  b\n"))])
    #expect(body.contains("<pre class=\"artwork\"><code>&lt;a&gt;\n  b</code></pre>"))
  }

  @Test func `a table has its caption, header and rows`() {
    let table = Table(
      title: "Codes", number: 2, header: [Table.Row(cells: [[.text("Code")]])],
      rows: [Table.Row(cells: [[.text("1")]], anchor: "row-1")])
    let body = Self.body([.table(table)])
    #expect(body.contains("<caption>Table 2: Codes</caption>"))
    #expect(body.contains("<thead>\n<tr><th>Code</th></tr>"))
    #expect(body.contains("<tr id=\"row-1\"><td>1</td></tr>"))
  }

  @Test func `an anchor carried twice is an id once`() {
    let body = Self.body([
      .paragraph(Paragraph(text: "One.", anchor: "twice")),
      .paragraph(Paragraph(text: "Two.", anchor: "twice")),
    ])
    #expect(body.components(separatedBy: "id=\"twice\"").count == 2)
  }

  @Test func `the page embeds the stylesheet, in light and dark`() {
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(9999), title: "A Protocol"), sections: [], source: .xml)
    let page = RFCHTMLSerializer().page(document)
    #expect(page.contains("<title>RFC 9999: A Protocol</title>"))
    #expect(page.contains(RFCHTMLSerializer.stylesheet))
    #expect(RFCHTMLSerializer.stylesheet.contains("prefers-color-scheme: dark"))
    #expect(!RFCHTMLSerializer.stylesheet.contains("<"))
    #expect(!RFCHTMLSerializer.stylesheet.contains("&"))
  }

  // MARK: Guarantees, over committed fixtures

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `the page is well-formed XML, and no prose is lost`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let page = RFCHTMLSerializer().page(document)
    let reader = TextCollector()
    let parser = XMLParser(data: Data(page.utf8))
    parser.delegate = reader
    #expect(parser.parse(), "\(fixture): \(String(describing: parser.parserError))")
    let text = SerializedText.normalized(reader.text)
    var cursor = text.startIndex
    for leaf in SerializedText.leaves(of: document) {
      let range = try #require(
        text.range(of: leaf, range: cursor..<text.endIndex), "\(fixture): \(leaf)")
      cursor = range.upperBound
    }
    #expect(reader.duplicateIDs.isEmpty, "\(fixture)")
  }

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `every anchor is an id`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let reader = TextCollector()
    let parser = XMLParser(data: Data(RFCHTMLSerializer().page(document).utf8))
    parser.delegate = reader
    _ = parser.parse()
    let missing = Set(SerializedText.anchorCounts(of: document).keys).subtracting(reader.ids)
    #expect(missing.isEmpty, "\(fixture)")
  }

  @Test(arguments: RFCMarkdownSerializerTests.fixtures)
  func `the same document is written the same way twice`(fixture: String) throws {
    let first = RFCHTMLSerializer().page(try Fixtures.parse(fixture))
    let second = RFCHTMLSerializer().page(try Fixtures.parse(fixture))
    #expect(first == second)
  }
}

/// The character data of a page, as a parser of it reads it, and its ids.
private final class TextCollector: NSObject, XMLParserDelegate {
  var text = ""
  var ids: Set<String> = []
  var duplicateIDs: [String] = []

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String] = [:]
  ) {
    guard let id = attributes["id"] else { return }
    if !ids.insert(id).inserted { duplicateIDs.append(id) }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }
}
