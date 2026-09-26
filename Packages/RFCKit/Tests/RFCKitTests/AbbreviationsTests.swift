import Foundation
import Testing

@testable import RFCKit

/// The abbreviations a document expands itself (issue #67). Through the parsers,
/// against real documents: a legacy one (RFC 4801), a modern one with a glossary
/// section (RFC 8761), and one whose first expansion sits in a bibliography entry
/// that must not count (RFC 8999). At the guard, the matching itself, on lines
/// taken from those documents.
@Suite("Abbreviations")
struct AbbreviationsTests {
  private static func xml(_ name: String) throws -> RFCDocument {
    try RFCXMLParser.parse(try Fixtures.data(name))
  }

  private static func text(_ name: String) throws -> RFCDocument {
    LegacyTextParser.parse(try Fixtures.data(name))
  }

  // MARK: Through the parsers

  @Test func aLegacyDocumentExpandsAtFirstUse() throws {
    let abbreviations = try Self.text("rfc4801.txt").abbreviations
    #expect(abbreviations["GMPLS"]?.expansion == "Generalized Multiprotocol Label Switching")
    #expect(abbreviations["SNMP"]?.expansion == "Simple Network Management Protocol")
    #expect(abbreviations["MIB"]?.expansion == "Management Information Base")
  }

  /// The expansion is the author's words, as written, capitals or not.
  @Test func aLowercaseExpansionIsTheAuthors() throws {
    let abbreviations = try Self.text("rfc4801.txt").abbreviations
    #expect(abbreviations["TCs"]?.expansion == "textual conventions")
  }

  /// Where it was expanded: the abstract has no section, and a later first use
  /// names its own.
  @Test func eachExpansionKnowsItsSection() throws {
    let abbreviations = try Self.text("rfc4801.txt").abbreviations
    #expect(abbreviations["GMPLS"]?.sectionAnchor == nil)
    #expect(abbreviations["SNMP"]?.sectionAnchor == "section-2")
  }

  /// RFC 8761 section 2.2 is an abbreviations list: terms whose definition opens
  /// with the expansion, sometimes followed by an explanation that is not part of it.
  @Test func aGlossaryIsRead() throws {
    let abbreviations = try Self.xml("rfc8761.xml").abbreviations
    #expect(abbreviations["BD-Rate"]?.expansion == "Bjontegaard Delta Rate")
    #expect(abbreviations["GPU"]?.expansion == "Graphics Processing Unit")
    #expect(abbreviations["AI"]?.expansion == "All-Intra")
    #expect(abbreviations["BD-Rate"]?.sectionAnchor == "abbr")
  }

  /// `FIZD` is defined as `just the First picture is Intra-coded, Zero structural
  /// Delay`: prose about the term, not letter for letter its expansion.
  @Test func aGlossaryDefinitionThatIsProseIsNotAnExpansion() throws {
    #expect(try Self.xml("rfc8761.xml").abbreviations["FIZD"] == nil)
  }

  /// `576p (EDTV), 720x576` in a table cell: the letters of `EDTV` are nowhere
  /// before it, so there is nothing to show rather than something wrong.
  @Test func anAbbreviationWithNoExpansionBeforeItHasNone() throws {
    let abbreviations = try Self.xml("rfc8761.xml").abbreviations
    #expect(abbreviations["EDTV"] == nil)
    #expect(abbreviations["SDTV"] == nil)
  }

  /// RFC 8999 expands AEAD first inside a bibliography entry's abstract, which is
  /// another document's text; the document's own first expansion is in its appendix.
  @Test func bibliographyEntriesAreNotTheDocumentsWords() throws {
    let abbreviation = try #require(try Self.xml("rfc8999.xml").abbreviations["AEAD"])
    #expect(abbreviation.expansion == "Authenticated Encryption with Associated Data")
    #expect(abbreviation.sectionAnchor == "bad-assumptions")
  }

  // MARK: The matching itself

  private func pairs(_ text: String) -> [String] {
    Abbreviations.expansions(in: text).map { "\($0.short)=\($0.long)" }
  }

  /// The long form starts at the word the short form's first letter begins, so
  /// the article in front of it is not part of it.
  @Test func theLongFormStartsWhereItsFirstLetterDoes() {
    #expect(
      pairs("approved by the Internet Engineering Steering Group (IESG).")
        == ["IESG=Internet Engineering Steering Group"])
  }

  @Test func severalInOneSentenceAreEachFound() {
    #expect(
      pairs("High Dynamic Range (HDR), Wide Color Gamut (WCG), high-resolution")
        == ["HDR=High Dynamic Range", "WCG=Wide Color Gamut"])
  }

  /// A parenthesis that is not set off by a space, or holds words, is not a
  /// definition.
  @Test func notEveryParenthesisIsADefinition() {
    #expect(pairs("the key(s) to use").isEmpty)
    #expect(pairs("Hash Function (see Section 3)").isEmpty)
    #expect(pairs("Transport Layer Security (TLS 1.3)").isEmpty)
  }

  @Test func theLongFormDoesNotReachPastTheSentence() {
    #expect(pairs("It ends in Security. Then Layer (SL).").isEmpty)
  }

  @Test func whatAShortFormLooksLike() {
    for short in ["TLS", "IPv6", "TCs", "BD-Rate", "QoS"] {
      #expect(Abbreviations.isShortForm(short), "\(short)")
    }
    for short in ["s", "Ed", "42", "see below", "x", "ABCDEFGHIJK"] {
      #expect(!Abbreviations.isShortForm(short), "\(short)")
    }
  }

  @Test func aGlossaryEntryIsItsWholeOpeningPhrase() {
    let definition: [Block] = [
      .paragraph(Paragraph(text: "Transport Layer Security, as defined in the references."))
    ]
    #expect(
      Abbreviations.glossaryEntry(term: "TLS:", definition: definition)?.long
        == "Transport Layer Security")
    let prose: [Block] = [.paragraph(Paragraph(text: "The round-trip time of a probe."))]
    #expect(Abbreviations.glossaryEntry(term: "RTT", definition: prose) == nil)
  }
}
