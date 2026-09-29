import Foundation
import Testing

@testable import RFCKit

/// The terms a document defines, collected at parse time the way abbreviations are
/// (#176): its own definitions, correct for this document, keyed by the term as written.
@Suite("Defined terms")
struct DefinedTermsTests {
  // MARK: Which sections define terms

  @Test(arguments: [
    "Terminology", "Terminology Used in This Document", "Definitions", "Glossary",
    "Conventions and Definitions", "Conventions and Terminology", "TERMINOLOGY",
    "Definitions of Protocol State", "Terms and Definitions",
    "Notational Conventions and Definitions",
  ])
  func `a section titled for its terms defines them`(title: String) {
    #expect(DefinedTerms.namesTerms(title), "\(title)")
  }

  /// Most definition lists describe fields or notation, not terms: only a section that
  /// says it defines terms is read. Definitions anywhere but first, or after `Terms and`
  /// or `Conventions and`, are of a format's parts, and one definition is not a list.
  @Test(arguments: [
    "Notational Conventions", "Conventions", "Message Format", "Security Considerations",
    "Protocol Overview", "Field Definitions", "Header Option Definitions",
    "Definition of the Header", "Message Definition",
  ])
  func `any other section does not`(title: String) {
    #expect(!DefinedTerms.namesTerms(title), "\(title)")
  }

  // MARK: Which lists define terms

  /// A definition list nested in a definition describes a part of that term, not a term
  /// of the document's own. Over a hand-written model: `defined(in:)` is a pure function
  /// of it, and no committed fixture nests a list in a terminology section.
  @Test func `only a section's top-level definition lists define terms`() {
    let nested = DefinitionItem(
      term: [.text("Flags:")], definition: [.paragraph(Paragraph(text: "One bit each."))],
      anchor: "flags")
    let outer = DefinitionItem(
      term: [.text("Widget:")],
      definition: [
        .paragraph(Paragraph(text: "The unit a sender emits.")), .definitionList([nested]),
      ],
      anchor: "widget")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(anchor: "terms", title: "Terminology", blocks: [.definitionList([outer])])
      ],
      source: .xml)
    #expect(Array(DefinedTerms.defined(in: document).keys) == ["Widget"])
  }

  /// A document can indent its terminology by setting the list in a list item.
  @Test func `a definition list set in a list item still defines terms`() {
    let item = DefinitionItem(
      term: [.text("Widget:")],
      definition: [.paragraph(Paragraph(text: "The unit a sender emits."))])
    let indented = ListBlock(style: .bare, items: [ListItem(blocks: [.definitionList([item])])])
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [Section(anchor: "terms", title: "Terminology", blocks: [.list(indented)])],
      source: .xml)
    #expect(Array(DefinedTerms.defined(in: document).keys) == ["Widget"])
  }

  /// A primary index entry placed directly in a section has no definition text; the
  /// section's definition list holds the definition, and the term lands on its item.
  @Test func `a definition list entry replaces an index entry without a definition`() throws {
    let listed = DefinitionItem(
      term: [.text("widget")],
      definition: [.paragraph(Paragraph(text: "The unit a sender emits."))],
      anchor: "widget")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(anchor: "terms", title: "Terminology", blocks: [.definitionList([listed])])
      ],
      source: .xml)
    let indexed = DefinedTerm(term: "widget", anchor: "terms", definition: [])
    let term = try #require(DefinedTerms.defined(in: document, indexed: [indexed])["widget"])
    #expect(term.anchor == "widget")
    #expect(term.definition == listed.definition)
  }

  /// An index entry with a definition of its own is the author's mark, and stays first.
  @Test func `an index entry with a definition keeps it over a definition list entry`() throws {
    let listed = DefinitionItem(
      term: [.text("widget")],
      definition: [.paragraph(Paragraph(text: "The unit a sender emits."))],
      anchor: "widget")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(anchor: "terms", title: "Terminology", blocks: [.definitionList([listed])])
      ],
      source: .xml)
    let indexed = DefinedTerm(
      term: "widget", anchor: "widget-def",
      definition: [.paragraph(Paragraph(text: "A widget is what a sender emits."))])
    let term = try #require(DefinedTerms.defined(in: document, indexed: [indexed])["widget"])
    #expect(term == indexed)
  }

  // MARK: Through parse

  @Test func `a terminology section's definition list defines its terms`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9985.xml"))
    let term = try #require(document.definedTerms["significant change"])
    #expect(term.term == "significant change", "the list's trailing colon is not the term's")
    #expect(!term.definition.isEmpty)
    #expect(term.anchor != nil)
    #expect(document.definedTerms.count == 4)
  }

  @Test func `a definition list elsewhere defines nothing`() throws {
    // RFC 8999's only definition list is its notation, under Notational Conventions.
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
    #expect(document.definedTerms.isEmpty)
  }

  /// RFC 2013 §2 is titled Definitions and holds a MIB module, no definition list.
  @Test func `a definitions section without a definition list defines nothing`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2013.txt"))
    #expect(document.definedTerms.isEmpty)
  }

  // MARK: Primary index entries

  /// `<iref primary="true">` marks where a document defines a term. The collector is
  /// a pure function of the XML tree, so it is tested over a hand-written one; no
  /// committed fixture has an index entry. Written in RFCXML's shape, quoted from none.
  @Test func `a primary index entry defines its term at the element it sits in`() throws {
    let xml = """
      <rfc><middle>
        <section anchor="terms"><name>Terms</name>
          <t anchor="widget-def"><iref primary="true" item="widget"/>A widget is the unit
          a sender emits.</t>
          <t><iref item="widget"/>A widget is mentioned here, but not defined.</t>
          <t><iref primary="true" item="Grammar" subitem="ALPHA"/>An index group.</t>
        </section>
        <section anchor="gadgets"><name>Gadgets</name>
          <t><iref primary="true" item="gadget"/>A gadget holds widgets.</t>
        </section>
      </middle></rfc>
      """
    let root = try XMLTree.parse(Data(xml.utf8))
    let terms = RFCXMLParser.primaryIndexTerms(in: root)
    #expect(terms.map(\.term) == ["widget", "gadget"])
    #expect(
      terms.map(\.anchor) == ["widget-def", "gadgets"], "its element's anchor, or the section's")
    let definition = try #require(terms.first?.definition.first)
    guard case .paragraph(let paragraph) = definition else {
      Issue.record("the definition is the paragraph the entry sits in")
      return
    }
    #expect(paragraph.plainText.hasPrefix("A widget is the unit"))
  }

  /// A prepared document numbers what its author did not anchor, and the parser anchors
  /// a paragraph or a section by that `pn`, so the term lands where its definition does.
  @Test func `a primary index entry takes its element's part number when it has no anchor`()
    throws
  {
    let xml = """
      <rfc><middle>
        <section pn="section-3">
          <name>Intermediaries</name>
          <t pn="section-3-2"><iref primary="true" item="relay"/>A relay passes messages on.</t>
          <section pn="section-3.1">
            <name>Tunnels</name>
            <iref primary="true" item="tunnel"/>
            <t>A tunnel passes them on blindly.</t>
          </section>
        </section>
      </middle></rfc>
      """
    let root = try XMLTree.parse(Data(xml.utf8))
    let terms = RFCXMLParser.primaryIndexTerms(in: root)
    #expect(terms.map(\.term) == ["relay", "tunnel"])
    #expect(terms.map(\.anchor) == ["section-3-2", "section-3.1"])
  }
}
