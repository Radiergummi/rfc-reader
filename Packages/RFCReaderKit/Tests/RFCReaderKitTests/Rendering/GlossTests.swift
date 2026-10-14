import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a gloss's card says, and where Go to Definition takes the reader (#396).
struct GlossTests {
  @Test func `a term's card is titled with the term and says its definition`() {
    let gloss = Gloss.term(
      DefinedTerm(
        term: "relay", anchor: "def-relay",
        definition: [
          .paragraph(Paragraph(text: "A relay forwards.")),
          .list(ListBlock(style: .bullet, items: [ListItem(text: "It keeps nothing.")])),
        ]))
    #expect(gloss.title == "relay")
    #expect(gloss.text == "A relay forwards.\nIt keeps nothing.")
    #expect(gloss.anchor == "def-relay")
  }

  /// An abbreviation's card is its short form and the document's own words for it,
  /// and Go to Expansion goes to the section that expands it (#67).
  @Test func `an abbreviation's card is its short form and its expansion`() {
    let gloss = Gloss.abbreviation(
      Abbreviation(short: "TLS", expansion: "Transport Layer Security", sectionAnchor: "intro"))
    #expect(gloss.title == "TLS")
    #expect(gloss.text == "Transport Layer Security")
    #expect(gloss.anchor == "intro")
  }

  /// One the abstract expands has no section to go to.
  @Test func `an abbreviation expanded in the abstract has nowhere to go`() {
    let gloss = Gloss.abbreviation(
      Abbreviation(short: "TLS", expansion: "Transport Layer Security"))
    #expect(gloss.anchor == nil)
  }

  @Test func `a term defined without an anchor has nowhere to go`() {
    let gloss = Gloss.term(DefinedTerm(term: "relay", anchor: nil, definition: []))
    #expect(gloss.anchor == nil)
  }
}
