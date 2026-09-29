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
    "Notational Conventions and Definitions", "Symbols, Abbreviations, and Definitions",
    "Conventions, Definitions, and Acronyms", "Notation and Definitions", "Definition of Terms",
    "Definitions of Terms Used Here", "Terms", "New Terms", "Terms Used in This Document",
    "Terms and Abbreviations", "Summary of Terms", "Conventions and Acronyms",
  ])
  func `a section titled for its terms defines them`(title: String) {
    #expect(DefinedTerms.namesTerms(title), "\(title)")
  }

  /// Most definition lists describe fields or notation, not terms: only a section that
  /// says it defines terms is read. Definitions qualified by an adjective are a format's
  /// parts as often as terms, and one definition is not a list.
  @Test(arguments: [
    "Notational Conventions", "Conventions", "Message Format", "Security Considerations",
    "Protocol Overview", "Field Definitions", "Header Option Definitions",
    "Definition of the Header", "Message Definition", "Technical Definitions",
    "Additional Definitions", "Key Definitions", "General Definitions",
    "Message and Option Definitions", "Symbols and Option Definitions",
    "Conventions and Notation", "Conventions and Assumptions", "Conventions and Licenses",
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

  /// A Terminology section can hold its lists in subsections of their own, titled for
  /// what they hold rather than for terms; a subsection of any other section is still
  /// read only when its own title names terms.
  @Test func `a subsection of a section titled for its terms defines terms`() {
    func list(_ term: String) -> Block {
      .definitionList([
        DefinitionItem(
          term: [.text("\(term):")], definition: [.paragraph(Paragraph(text: "A part."))])
      ])
    }
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "terms", title: "Terminology", blocks: [],
          subsections: [
            Section(
              anchor: "core", title: "Core Concepts", blocks: [list("Widget")],
              subsections: [
                Section(anchor: "deeper", title: "Details", blocks: [list("Gadget")])
              ])
          ]),
        Section(
          anchor: "format", title: "Message Format", blocks: [],
          subsections: [Section(anchor: "header", title: "Header", blocks: [list("Flags")])]),
      ],
      source: .xml)
    #expect(Set(DefinedTerms.defined(in: document).keys) == ["Widget", "Gadget"])
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

  /// A primary index entry placed directly in a section gives way to a later one that
  /// sits in the paragraph defining the term.
  @Test func `a later index entry with a definition replaces one without`() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"), sections: [], source: .xml)
    let placed = DefinedTerm(term: "widget", anchor: "section-2", definition: [])
    let defining = DefinedTerm(
      term: "widget", anchor: "section-2-3",
      definition: [.paragraph(Paragraph(text: "A widget is what a sender emits."))])
    let term = try #require(
      DefinedTerms.defined(in: document, indexed: [placed, defining])["widget"])
    #expect(term == defining)
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

  /// An entry is the block's it sits in, even inside emphasis, and one in a `<dt>` is
  /// defined by the `<dd>` after it, at the term's anchor.
  @Test func `a primary index entry in an inline element or a term is its block's`() throws {
    let xml = """
      <rfc><middle>
        <section pn="section-2"><name>Terms</name>
          <t pn="section-2-1">A <em><iref primary="true" item="widget"/>widget</em> is the
          unit a sender emits.</t>
          <dl pn="section-2-2">
            <dt pn="section-2-2.1"><iref primary="true" item="gadget"/>Gadget:</dt>
            <dd pn="section-2-2.2">A gadget holds widgets.</dd>
          </dl>
        </section>
      </middle></rfc>
      """
    let root = try XMLTree.parse(Data(xml.utf8))
    let terms = RFCXMLParser.primaryIndexTerms(in: root)
    #expect(terms.map(\.term) == ["widget", "gadget"])
    #expect(terms.map(\.anchor) == ["section-2-1", "section-2-2.1"])
    let definitions = terms.map { term in
      term.definition.map { block -> String in
        guard case .paragraph(let paragraph) = block else { return "" }
        return paragraph.plainText
      }
    }
    #expect(definitions.first?.first?.hasPrefix("A widget is the") == true)
    #expect(definitions.last == ["A gadget holds widgets."])
  }

  /// The model anchors a table only by its author's anchor, so a part number there
  /// would be an anchor no block holds: the entry lands on the section instead.
  @Test func `a primary index entry takes only an anchor the model holds`() throws {
    let xml = """
      <rfc><middle>
        <section pn="section-4"><name>Codes</name>
          <table pn="table-1">
            <tbody><tr><td><iref primary="true" item="teapot"/>A teapot.</td></tr></tbody>
          </table>
        </section>
      </middle></rfc>
      """
    let root = try XMLTree.parse(Data(xml.utf8))
    let terms = RFCXMLParser.primaryIndexTerms(in: root)
    #expect(terms.map(\.anchor) == ["section-4"])
  }
}
