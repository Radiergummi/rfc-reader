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

  // MARK: Cleaning a term (#396)

  /// The spellings a term as written stands for: the term itself, trimmed of what
  /// its list or entry carried with it, each spelling prose would use on its own.
  /// Hand-written terms in the shapes the corpus run found, none quoted from an RFC.
  @Test(arguments: spellingCases)
  func `a term as written stands for these spellings`(written: String, spellings: [String]) {
    #expect(DefinedTerms.spellings(of: written) == spellings, "\(written)")
  }

  private static let spellingCases: [(String, [String])] = [
    ("Widget Gateway", ["Widget Gateway"]),
    // An abbreviation and its expansion, either way round: both are spellings.
    ("WGW (Widget Gateway)", ["WGW", "Widget Gateway"]),
    ("Widget Gateway (WGW)", ["Widget Gateway", "WGW"]),
    ("Point of Widget (PoW)", ["Point of Widget", "PoW"]),
    // A parenthetical that qualifies the term is not a spelling of it.
    ("parent (of a widget)", ["parent"]),
    ("599 Widget Unavailable (status code)", ["599 Widget Unavailable"]),
    // A citation, or the start of the definition, carried in the term.
    ("Widget datagram [RFC9999] RFC\u{00A0}9998", ["Widget datagram"]),
    ("Widget Route RFC\u{00A0}9999", ["Widget Route"]),
    ("WGW: Widget Gateway.", ["WGW"]),
    ("Encoding Widget: (ADDED)", ["Encoding Widget"]),
    ("WAIT-STATE -", ["WAIT-STATE"]),
    (#""Widget Policy""#, ["Widget Policy"]),
    ("\u{201C}Widget Policy\u{201D}", ["Widget Policy"]),
    // Two names for one thing.
    ("Widget, wdgWidget", ["Widget", "wdgWidget"]),
    (
      "Intermediate Widget, Waypoint, or Next Widget",
      [
        "Intermediate Widget", "Waypoint", "Next Widget",
      ]
    ),
    // Notation is the term as it is: a colon or a bracket with no space before it.
    ("widget:port", ["widget:port"]),
    ("W[i..j]", ["W[i..j]"]),
    ("(w_S^i, q_S^i)", ["(w_S^i, q_S^i)"]),
    // A short form only when the other side expands it: a qualifier otherwise.
    ("Content-Type (header field)", ["Content-Type"]),
    ("Widget Route BCP 99", ["Widget Route"]),
    ("Widget Route RFC9999", ["Widget Route"]),
    // Quotes come off before anything is cut, and off each item of a list.
    (#""Widget", "Gadget""#, ["Widget", "Gadget"]),
    (#""Widget: Gateway""#, ["Widget"]),
    // Nothing left, or a list of letters, is no term.
    ("", []),
    ("I, p, q, R", []),
  ]

  /// An index entry's comma inverts a name, and is no list.
  @Test func `an index entry's comma is kept`() {
    #expect(
      DefinedTerms.spellings(of: "cache, private", splittingLists: false) == ["cache, private"])
  }

  /// A term a list names without a definition is defined by a later list that has one.
  @Test func `a later definition replaces an entry without one`() throws {
    let bare = DefinitionItem(term: [.text("Widget:")], definition: [], anchor: "bare")
    let defined = DefinitionItem(
      term: [.text("Widget:")], definition: [.paragraph(Paragraph(text: "A part."))],
      anchor: "defined")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "terms", title: "Terminology",
          blocks: [
            .definitionList(DefinitionList([bare])), .definitionList(DefinitionList([defined])),
          ])
      ],
      source: .xml)
    let term = try #require(DefinedTerms.defined(in: document)["Widget"])
    #expect(term.anchor == "defined")
  }

  /// A term with no definition to show is no term a reader can be shown: an index
  /// entry nothing else supplies a definition for.
  @Test func `a term without a definition is dropped`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [Section(anchor: "terms", title: "Terminology", blocks: [Self.list("Widget")])],
      source: .xml)
    let found = DefinedTerms.defined(
      in: document,
      indexed: [DefinedTerm(term: "Gadget", anchor: "section-3", definition: [])])
    #expect(Set(found.keys) == ["Widget"])
  }

  /// Every spelling of a term opens the same definition.
  @Test func `every spelling of a term shares its definition`() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(anchor: "terms", title: "Terminology", blocks: [Self.list("WGW (Widget Gateway)")])
      ],
      source: .xml)
    let found = DefinedTerms.defined(in: document)
    #expect(Set(found.keys) == ["WGW", "Widget Gateway"])
    #expect(found["WGW"]?.definition == found["Widget Gateway"]?.definition)
    #expect(found["WGW"]?.term == "WGW")
  }

  // MARK: Which lists define terms

  /// A one-item definition list for `term`, as a terminology list sets it.
  private static func list(_ term: String) -> Block {
    .definitionList(
      DefinitionList([
        DefinitionItem(
          term: [.text("\(term):")], definition: [.paragraph(Paragraph(text: "A part."))])
      ]))
  }

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
        .paragraph(Paragraph(text: "The unit a sender emits.")),
        .definitionList(DefinitionList([nested])),
      ],
      anchor: "widget")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "terms", title: "Terminology", blocks: [.definitionList(DefinitionList([outer]))])
      ],
      source: .xml)
    #expect(Array(DefinedTerms.defined(in: document).keys) == ["Widget"])
  }

  /// A Terminology section can hold its lists in subsections of their own, titled for
  /// what they hold rather than for terms; a subsection of any other section is still
  /// read only when its own title names terms.
  @Test func `a subsection of a section titled for its terms defines terms`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "terms", title: "Terminology", blocks: [],
          subsections: [
            Section(
              anchor: "core", title: "Core Concepts", blocks: [Self.list("Widget")],
              subsections: [
                Section(anchor: "deeper", title: "Details", blocks: [Self.list("Gadget")])
              ])
          ]),
        Section(
          anchor: "format", title: "Message Format", blocks: [],
          subsections: [Section(anchor: "header", title: "Header", blocks: [Self.list("Flags")])]),
      ],
      source: .xml)
    #expect(Set(DefinedTerms.defined(in: document).keys) == ["Widget", "Gadget"])
  }

  /// A section titled only `Definitions` can cover a specification's body, its
  /// subsections the protocol's variables or commands: its own lists define terms, and
  /// its subsections' only when their own titles name terms.
  @Test func `a section that only opens with Definitions passes nothing to its subsections`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "definitions", title: "Definitions", blocks: [Self.list("Widget")],
          subsections: [
            Section(
              anchor: "variables", title: "Per-Widget Variables", blocks: [Self.list("Count")]),
            Section(anchor: "terms", title: "Other Terms", blocks: [Self.list("Gadget")]),
          ]),
        Section(
          anchor: "conventions", title: "Conventions and Definitions", blocks: [],
          subsections: [Section(anchor: "roles", title: "Roles", blocks: [Self.list("Sender")])]),
      ],
      source: .xml)
    #expect(Set(DefinedTerms.defined(in: document).keys) == ["Widget", "Gadget", "Sender"])
  }

  /// A document can indent its terminology by setting the list in a list item.
  @Test func `a definition list set in a list item still defines terms`() {
    let item = DefinitionItem(
      term: [.text("Widget:")],
      definition: [.paragraph(Paragraph(text: "The unit a sender emits."))])
    let indented = ListBlock(
      style: .bare, items: [ListItem(blocks: [.definitionList(DefinitionList([item]))])])
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
        Section(
          anchor: "terms", title: "Terminology", blocks: [.definitionList(DefinitionList([listed]))]
        )
      ],
      source: .xml)
    let indexed = DefinedTerm(term: "widget", anchor: "terms", definition: [])
    let term = try #require(DefinedTerms.defined(in: document, indexed: [indexed])["widget"])
    #expect(term.anchor == "widget")
    #expect(term.definition == listed.definition)
  }

  /// A term with no description gives no definition either, so an index entry without
  /// one keeps waiting for an entry that has one.
  @Test func `a definition list entry without a definition does not replace an index entry`()
    throws
  {
    let bare = DefinitionItem(term: [.text("widget")], definition: [], anchor: "widget-bare")
    let listed = DefinitionItem(
      term: [.text("widget")],
      definition: [.paragraph(Paragraph(text: "The unit a sender emits."))],
      anchor: "widget")
    let document = RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [
        Section(
          anchor: "terms", title: "Terminology",
          blocks: [
            .definitionList(DefinitionList([bare])), .definitionList(DefinitionList([listed])),
          ])
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
        Section(
          anchor: "terms", title: "Terminology", blocks: [.definitionList(DefinitionList([listed]))]
        )
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
    let document = try Fixtures.document("rfc9985.xml")
    let term = try #require(document.definedTerms["significant change"])
    #expect(term.term == "significant change", "the list's trailing colon is not the term's")
    #expect(!term.definition.isEmpty)
    #expect(term.anchor != nil)
    #expect(document.definedTerms.count == 4)
  }

  @Test func `a definition list elsewhere defines nothing`() throws {
    // RFC 8999's only definition list is its notation, under Notational Conventions.
    let document = try Fixtures.document("rfc8999.xml")
    #expect(document.definedTerms.isEmpty)
  }

  /// RFC 2013 §2 is titled Definitions and holds a MIB module, no definition list.
  @Test func `a definitions section without a definition list defines nothing`() throws {
    let document = try Fixtures.document("rfc2013.txt")
    #expect(document.definedTerms.isEmpty)
  }

  // MARK: Primary index entries

  /// `<iref primary="true">` marks where a document defines a term. The XML says only
  /// which anchors it may be at, innermost first; the model says which of them it
  /// holds (#455). Each half is a pure function, tested over a hand-written XML tree
  /// or model; no committed fixture has an index entry. Written in RFCXML's shape,
  /// quoted from none.
  @Test func `a primary index entry may be defined at its element or any around it`() throws {
    let xml = """
      <rfc><middle>
        <section anchor="terms" pn="section-2"><name>Terms</name>
          <t anchor="widget-def" pn="section-2-1"><iref primary="true" item="widget"/>A widget
          is the unit a sender emits.</t>
          <t><iref item="widget"/>A widget is mentioned here, but not defined.</t>
          <t><iref primary="true" item="Grammar" subitem="ALPHA"/>An index group.</t>
        </section>
        <section anchor="gadgets"><name>Gadgets</name>
          <iref primary="true" item="gadget"/>
          <t>A gadget holds widgets.</t>
        </section>
      </middle></rfc>
      """
    let terms = RFCXMLParser.primaryIndexTerms(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(terms.map(\.term) == ["widget", "gadget"])
    #expect(terms.first?.anchors == ["widget-def", "section-2-1", "terms", "section-2"])
    #expect(terms.last?.anchors == ["gadgets"])
  }

  /// An entry is the block's it sits in, even inside emphasis, and one in a `<dt>` may
  /// be defined at the term's anchors, then the description's after it.
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
    let terms = RFCXMLParser.primaryIndexTerms(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(terms.map(\.term) == ["widget", "gadget"])
    #expect(terms.first?.anchors == ["section-2-1", "section-2"])
    #expect(terms.last?.anchors == ["section-2-2.1", "section-2-2.2", "section-2-2", "section-2"])
  }

  /// A paragraph the entry sits in is its definition, at the paragraph's anchor.
  @Test func `an index entry is defined by the paragraph the model holds it at`() throws {
    let paragraph = Paragraph(text: "A widget is the unit a sender emits.", anchor: "widget-def")
    let document = Self.model([.paragraph(paragraph)])
    let term = try #require(
      DefinedTerms.lookUp(
        [IndexedTerm(term: "widget", anchors: ["widget-def", "section-2-1", "terms"])],
        in: document
      ).first)
    #expect(term.anchor == "widget-def")
    #expect(term.definition == [.paragraph(paragraph)])
  }

  /// An anchor the model doesn't hold is passed over for the next: a table's part
  /// number, which the model doesn't keep, gives way to the section's.
  @Test func `an index entry takes only an anchor the model holds`() throws {
    let document = Self.model([
      .table(Table(title: nil, header: [], rows: [Table.Row(cells: [[.text("A teapot.")]])]))
    ])
    let term = try #require(
      DefinedTerms.lookUp(
        [IndexedTerm(term: "teapot", anchors: ["table-1", "terms"])], in: document
      ).first)
    #expect(term.anchor == "terms")
    #expect(term.definition.isEmpty, "a section marked by an entry is no definition")
  }

  /// Where the anchor the model holds defines nothing itself, a section around a table
  /// cell, the entry is defined by the block it sits in, as the XML reads it.
  @Test func `an entry in a block without an anchor is defined by that block`() throws {
    let cell = [Block.paragraph(Paragraph(text: "A teapot."))]
    let document = Self.model([
      .table(Table(title: nil, header: [], rows: [Table.Row(cells: [[.text("A teapot.")]])]))
    ])
    let term = try #require(
      DefinedTerms.lookUp(
        [IndexedTerm(term: "teapot", anchors: ["table-1", "terms"], definition: cell)],
        in: document
      ).first)
    #expect(term.anchor == "terms")
    #expect(term.definition == cell)
  }

  /// The model keeps a table row's author anchor, so an entry in that row lands on it.
  @Test func `an index entry in an anchored table row lands on the row`() throws {
    let table = Table(
      title: nil, header: [], rows: [Table.Row(cells: [[.text("A teapot.")]], anchor: "code.418")])
    let document = Self.model([.table(table)])
    let cell = [Block.paragraph(Paragraph(text: "A teapot."))]
    let term = try #require(
      DefinedTerms.lookUp(
        [IndexedTerm(term: "teapot", anchors: ["code.418", "table-1", "terms"], definition: cell)],
        in: document
      ).first)
    #expect(term.anchor == "code.418")
    #expect(term.definition == cell, "the cell, not the whole table")
  }

  /// A term in a definition list is defined by its description, at either anchor.
  @Test func `an index entry in a definition list is defined by its description`() throws {
    let item = DefinitionItem(
      term: [.text("Gadget:")],
      definition: [.paragraph(Paragraph(text: "A gadget holds widgets."))],
      anchor: "gadget")
    let document = Self.model([.definitionList(DefinitionList([item]))])
    let term = try #require(
      DefinedTerms.lookUp(
        [IndexedTerm(term: "gadget", anchors: ["gadget", "terms"])], in: document
      )
      .first)
    #expect(term.anchor == "gadget")
    #expect(term.definition == item.definition)
  }

  @Test func `an index entry at no anchor the model holds is dropped`() {
    let document = Self.model([])
    #expect(
      DefinedTerms.lookUp([IndexedTerm(term: "widget", anchors: ["elsewhere"])], in: document)
        .isEmpty)
  }

  /// A model of one section, `terms`, holding `blocks`.
  private static func model(_ blocks: [Block]) -> RFCDocument {
    RFCDocument(
      header: DocumentHeader(title: "Widgets"),
      sections: [Section(anchor: "terms", title: "Terms", blocks: blocks)], source: .xml)
  }
}
