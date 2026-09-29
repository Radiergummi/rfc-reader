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
    "Definitions of Protocol State",
  ])
  func `a section titled for its terms defines them`(title: String) {
    #expect(DefinedTerms.namesTerms(title), "\(title)")
  }

  /// Most definition lists describe fields or notation, not terms: only a section that
  /// says it defines terms is read.
  @Test(arguments: [
    "Notational Conventions", "Conventions", "Message Format", "Security Considerations",
    "Protocol Overview",
  ])
  func `any other section does not`(title: String) {
    #expect(!DefinedTerms.namesTerms(title), "\(title)")
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
}
