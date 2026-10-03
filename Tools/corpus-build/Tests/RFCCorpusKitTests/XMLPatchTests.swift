import Foundation
import RFCCorpusKit
import RFCKit
import Testing

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// RFC 5261 patches, applied to what the converter makes of a committed fixture, so
/// no RFC text is added. RFC 2119 converts with its keyword definitions read as
/// headings, the kind of correction a patch exists for.
@Suite("XML patch")
struct XMLPatchTests {
  /// Converted once; each test patches a tree of its own.
  private static let xml: Data? = try? DocumentConverter().convert(
    text: Fixtures.text("rfc2119.txt"), stem: "rfc2119", metadata: nil
  ).xml

  private static func converted() throws -> XMLDocument {
    try XMLDocument(data: try #require(xml), options: .nodePreserveWhitespace)
  }

  private static func patch(_ operations: String) throws -> XMLPatch {
    try XMLPatch(parsing: Data("<diff>\(operations)</diff>".utf8), name: "rfc2119.xml")
  }

  /// The document after `operations`, read as the app reads it.
  private static func patched(_ operations: String) throws -> RFCDocument {
    let document = try converted()
    try patch(operations).apply(to: document)
    return try RFCXMLParser.parse(document.xmlData)
  }

  /// The failure `operations` end in.
  private static func failure(_ operations: String) throws -> XMLPatch.Failure {
    let document = try converted()
    let patch = try patch(operations)
    return try #require(throws: XMLPatch.Failure.self) { try patch.apply(to: document) }
  }

  // MARK: Operations

  @Test func `replace swaps an element for another`() throws {
    let document = try Self.patched(
      "<replace sel=\"//section[@pn='section-7']/name\"><name>Security</name></replace>")
    #expect(document.section(anchor: "section-7")?.titleText == "Security")
  }

  @Test func `replace sets an attribute's value`() throws {
    let document = try Self.patched("<replace sel=\"/rfc/front/date/@year\">1998</replace>")
    #expect(document.header.date?.year == 1998)
  }

  @Test func `replace sets a text node`() throws {
    let document = try Self.patched(
      "<replace sel=\"//section[@pn='section-8']/name/text()\">Thanks</replace>")
    #expect(document.section(anchor: "section-8")?.titleText == "Thanks")
  }

  @Test func `remove takes an element out`() throws {
    let document = try Self.patched("<remove sel=\"//section[@pn='section-9']\"/>")
    #expect(document.section(anchor: "section-9") == nil)
    #expect(document.section(anchor: "section-8") != nil)
  }

  @Test func `remove takes an attribute out`() throws {
    let document = try Self.patched("<remove sel=\"/rfc/@category\"/>")
    #expect(document.header.category == nil)
  }

  /// A heading read out of a definition goes back to being its paragraph: the
  /// definition is added to the section before, and the section removed.
  @Test func `add appends children, and before and after place them beside the target`()
    throws
  {
    let document = try Self.patched(
      """
      <add sel="//section[@pn='section-6']"><t>Appended.</t></add>
      <add sel="//section[@pn='section-6']/t[1]" pos="before"><t>Before.</t></add>
      <add sel="//section[@pn='section-6']/t[last()]" pos="after"><t>After.</t></add>
      <add sel="//section[@pn='section-6']" pos="prepend"><t>Prepended.</t></add>
      """)
    let section = try #require(document.section(anchor: "section-6"))
    let paragraphs = section.blocks.compactMap { block -> String? in
      guard case .paragraph(let paragraph) = block else { return nil }
      return paragraph.plainText
    }
    #expect(paragraphs.first == "Prepended.")
    #expect(paragraphs.dropFirst().first == "Before.")
    #expect(paragraphs.suffix(2) == ["Appended.", "After."])
  }

  /// The space between two inline elements is a text node of its own, and the words
  /// either side run together without it.
  @Test func `added content keeps the space between inline elements`() throws {
    let document = try Self.patched(
      "<add sel=\"//section[@pn='section-6']\"><t>Kept <em>apart</em> <strong>words</strong>.</t></add>"
    )
    let section = try #require(document.section(anchor: "section-6"))
    guard case .paragraph(let paragraph) = section.blocks.last else {
      Issue.record("the section ends with \(String(describing: section.blocks.last))")
      return
    }
    #expect(paragraph.plainText == "Kept apart words.")
  }

  /// Added straight into an element, the space between two inline elements is all
  /// that keeps their words apart; only the space at the edges lays the patch out.
  @Test func `inline elements added straight into an element keep the space between them`()
    throws
  {
    let document = try Self.patched(
      "<add sel=\"//section[@pn='section-6']/t[last()]\">\n  <em>apart</em> <strong>words</strong>\n</add>"
    )
    let section = try #require(document.section(anchor: "section-6"))
    guard case .paragraph(let paragraph) = section.blocks.last else {
      Issue.record("the section ends with \(String(describing: section.blocks.last))")
      return
    }
    #expect(paragraph.plainText.hasSuffix("apart words"), "\(paragraph.plainText)")
  }

  /// Between block elements, the kept whitespace is nothing the document holds.
  @Test func `blocks added laid out over lines are those blocks alone`() throws {
    let unpatched = try RFCXMLParser.parse(try #require(Self.xml))
    let before = try #require(unpatched.section(anchor: "section-6")).blocks.count
    let document = try Self.patched(
      """
      <add sel="//section[@pn='section-6']">
        <t>First.</t>
        <t>Second.</t>
      </add>
      """)
    let section = try #require(document.section(anchor: "section-6"))
    #expect(section.blocks.count == before + 2)
    let paragraphs = section.blocks.suffix(2).compactMap { block -> String? in
      guard case .paragraph(let paragraph) = block else { return nil }
      return paragraph.plainText
    }
    #expect(paragraphs == ["First.", "Second."])
  }

  /// An attribute's value laid out over lines would keep the layout, which the parser
  /// cannot read, and the attribute would be lost without a word said.
  @Test func `an attribute's value laid out over lines is its text alone`() throws {
    let document = try Self.patched(
      """
      <replace sel="/rfc/front/date/@year">
        1998
      </replace>
      <add sel="/rfc/front/date" type="@day">
        7
      </add>
      """)
    #expect(document.header.date?.year == 1998)
    #expect(document.header.date?.day == 7)
  }

  @Test func `add with a type sets an attribute`() throws {
    let document = try Self.patched(
      "<add sel=\"/rfc/front/date\" type=\"@day\">7</add>")
    #expect(document.header.date?.day == 7)
  }

  @Test func `operations apply in order, each to the result of the one before`() throws {
    let document = try Self.patched(
      """
      <!-- A comment says why, and is not an operation. -->
      <replace sel="//section[@pn='section-7']/name"><name>Renamed</name></replace>
      <remove sel="//section[name='Renamed']"/>
      """)
    #expect(document.section(anchor: "section-7") == nil)
  }

  // MARK: Failures

  @Test func `a selector matching nothing fails`() throws {
    let failure = try Self.failure(
      """
      <remove sel="//section[@pn='section-9']"/>
      <remove sel="//section[@pn='section-99']"/>
      """)
    #expect(
      failure.description
        == "rfc2119.xml, operation 2 (remove //section[@pn='section-99']): matched 0 nodes")
  }

  @Test func `a selector matching several nodes fails`() throws {
    let failure = try Self.failure("<remove sel=\"//section\"/>")
    #expect(failure.operation == 1)
    #expect(failure.reason.hasPrefix("matched "), "\(failure)")
    #expect(failure.reason.hasSuffix(" nodes"), "\(failure)")
  }

  @Test(arguments: [
    "<add sel=\"/rfc\" pos=\"before\"><t>No.</t></add>",
    "<replace sel=\"/rfc/@category\"><t>No.</t></replace>",
    "<replace sel=\"//section[@pn='section-7']\">text</replace>",
    "<add sel=\"/rfc/@category\"><t>No.</t></add>",
    // The document node: detaching it would do nothing without a word said.
    "<remove sel=\"/\"/>",
  ])
  func `a target that does not suit the operation fails`(operation: String) throws {
    let failure = try Self.failure(operation)
    #expect(failure.operation == 1)
    #expect(!failure.reason.hasPrefix("matched"), "\(failure)")
  }

  /// A misspelled attribute would otherwise be ignored, and the operation applied
  /// with its default: appended rather than placed.
  @Test(arguments: [
    "<add sel=\"/rfc/front\" postion=\"before\"><t>No.</t></add>",
    "<add sel=\"/rfc/front\" pos=\"inside\"><t>No.</t></add>",
    "<replace sel=\"/rfc/front/title\" ws=\"both\"><title>No.</title></replace>",
    "<rename sel=\"/rfc/front\"/>",
    "<remove/>",
    // An add with nothing to add would change nothing without a word said.
    "<add sel=\"/rfc/front\"/>",
    "<add sel=\"/rfc/front\" pos=\"before\">\n</add>",
    // A patch of no operations would change nothing without a word said.
    "<!-- Only a comment. -->",
    // Not well-formed: libxml2 would drop the bare ampersand and select something else.
    "<remove sel=\"//t[contains(., 'a & b')]\"/>",
  ])
  func `a malformed operation is refused before anything applies`(operation: String) throws {
    #expect(throws: XMLPatch.Failure.self) { try Self.patch(operation) }
  }

  /// A blank line inside an operation only lays the patch out.
  @Test func `a remove laid out over two lines reads`() throws {
    let document = try Self.patched("<remove sel=\"//section[@pn='section-9']\">\n</remove>")
    #expect(document.section(anchor: "section-9") == nil)
  }

  @Test func `a patch file's root is diff`() {
    #expect(throws: XMLPatch.Failure.self) {
      try XMLPatch(parsing: Data("<rfc version=\"3\"/>".utf8), name: "rfc2119.xml")
    }
  }
}
