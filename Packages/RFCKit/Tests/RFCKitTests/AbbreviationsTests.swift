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
  // MARK: Through the parsers

  @Test func `a legacy document expands at first use`() throws {
    let abbreviations = try Fixtures.document("rfc4801.txt").abbreviations
    #expect(abbreviations["GMPLS"]?.expansion == "Generalized Multiprotocol Label Switching")
    #expect(abbreviations["SNMP"]?.expansion == "Simple Network Management Protocol")
    #expect(abbreviations["MIB"]?.expansion == "Management Information Base")
  }

  /// The expansion is the author's words, as written, capitals or not.
  @Test func `a lowercase expansion is the authors`() throws {
    let abbreviations = try Fixtures.document("rfc4801.txt").abbreviations
    #expect(abbreviations["TCs"]?.expansion == "textual conventions")
  }

  /// Where it was expanded: the abstract has no section, and a later first use
  /// names its own.
  @Test func `each expansion knows its section`() throws {
    let abbreviations = try Fixtures.document("rfc4801.txt").abbreviations
    #expect(abbreviations["GMPLS"]?.sectionAnchor == nil)
    #expect(abbreviations["SNMP"]?.sectionAnchor == "section-2")
  }

  /// RFC 8761 section 2.2 is an abbreviations list: terms whose definition opens
  /// with the expansion, sometimes followed by an explanation that is not part of it.
  @Test func `a glossary is read`() throws {
    let abbreviations = try Fixtures.document("rfc8761.xml").abbreviations
    #expect(abbreviations["BD-Rate"]?.expansion == "Bjontegaard Delta Rate")
    #expect(abbreviations["GPU"]?.expansion == "Graphics Processing Unit")
    #expect(abbreviations["AI"]?.expansion == "All-Intra")
    #expect(abbreviations["BD-Rate"]?.sectionAnchor == "abbr")
  }

  /// `FIZD` is defined as `just the First picture is Intra-coded, Zero structural
  /// Delay`: prose about the term, not letter for letter its expansion.
  @Test func `a glossary definition that is prose is not an expansion`() throws {
    #expect(try Fixtures.document("rfc8761.xml").abbreviations["FIZD"] == nil)
  }

  /// `576p (EDTV), 720x576` in a table cell: the letters of `EDTV` are nowhere
  /// before it, so there is nothing to show rather than something wrong.
  @Test func `an abbreviation with no expansion before it has none`() throws {
    let abbreviations = try Fixtures.document("rfc8761.xml").abbreviations
    #expect(abbreviations["EDTV"] == nil)
    #expect(abbreviations["SDTV"] == nil)
  }

  /// RFC 8999 expands AEAD first inside a bibliography entry's abstract, which is
  /// another document's text; the document's own first expansion is in its appendix.
  @Test func `bibliography entries are not the documents words`() throws {
    let abbreviation = try #require(try Fixtures.document("rfc8999.xml").abbreviations["AEAD"])
    #expect(abbreviation.expansion == "Authenticated Encryption with Associated Data")
    #expect(abbreviation.sectionAnchor == "bad-assumptions")
  }

  /// An entry's annotation is the citing author's own words about it, but it is
  /// still the bibliography: an expansion there is as likely the cited document's,
  /// copied, and a reader looking up an abbreviation in the body is not helped by
  /// one found in a note on page 40. So it does not count either.
  @Test func `a reference annotation is not the documents words`() {
    let entry = Reference(
      anchor: "TLS13", title: "The Transport Layer Security Protocol Version 1.3",
      annotation: [.text("Specifies Transport Layer Security (TLS).")])
    let document = RFCDocument(
      header: DocumentHeader(title: "Annotated"),
      sections: [
        Section(
          anchor: "references", title: "References",
          blocks: [.references(ReferenceList(title: "References", entries: [entry]))])
      ],
      source: .xml)
    #expect(Abbreviations.defined(in: document)["TLS"] == nil)
  }

  // MARK: The matching itself

  private func pairs(_ text: String) -> [String] {
    Abbreviations.expansions(in: text).map { "\($0.short)=\($0.long)" }
  }

  /// The long form starts at the word the short form's first letter begins, so
  /// the article in front of it is not part of it.
  @Test func `the long form starts where its first letter does`() {
    #expect(
      pairs("approved by the Internet Engineering Steering Group (IESG).")
        == ["IESG=Internet Engineering Steering Group"])
  }

  @Test func `several in one sentence are each found`() {
    #expect(
      pairs("High Dynamic Range (HDR), Wide Color Gamut (WCG), high-resolution")
        == ["HDR=High Dynamic Range", "WCG=Wide Color Gamut"])
  }

  /// A parenthesis that is not set off by a space, or holds words, is not a
  /// definition.
  @Test func `not every parenthesis is a definition`() {
    #expect(pairs("the key(s) to use").isEmpty)
    #expect(pairs("Hash Function (see Section 3)").isEmpty)
    #expect(pairs("Transport Layer Security (TLS 1.3)").isEmpty)
  }

  @Test func `the long form does not reach past the sentence`() {
    #expect(pairs("It ends in Security. Then Layer (SL).").isEmpty)
  }

  @Test func `what a short form looks like`() {
    for short in ["TLS", "IPv6", "TCs", "BD-Rate", "QoS"] {
      #expect(Abbreviations.isShortForm(short), "\(short)")
    }
    for short in ["s", "Ed", "42", "see below", "x", "ABCDEFGHIJK"] {
      #expect(!Abbreviations.isShortForm(short), "\(short)")
    }
  }

  @Test func `a glossary entry is its whole opening phrase`() {
    let definition: [Block] = [
      .paragraph(Paragraph(text: "Transport Layer Security, as defined in the references."))
    ]
    #expect(
      Abbreviations.glossaryEntry(term: "TLS:", definition: definition)?.long
        == "Transport Layer Security")
    let prose: [Block] = [.paragraph(Paragraph(text: "The round-trip time of a probe."))]
    #expect(Abbreviations.glossaryEntry(term: "RTT", definition: prose) == nil)
  }

  // MARK: Precision, from the full corpus

  /// The match takes the nearest word with the right initial, so a lowercase
  /// function word in the expansion stole the start. Measured over the corpus,
  /// 69 expansions began that way; the earlier word with the initial is the start.
  @Test func `an expansion does not start on a function word`() {
    #expect(
      pairs("the Abstraction and Control of TE Networks (ACTN) framework")
        == ["ACTN=Abstraction and Control of TE Networks"])
    #expect(
      pairs("the Access Network Discovery and Selection Function (ANDSF) server")
        == ["ANDSF=Access Network Discovery and Selection Function"])
    #expect(
      pairs("Functional Requirements for Bibliographic Records (FRBR)")
        == ["FRBR=Functional Requirements for Bibliographic Records"])
  }

  /// With no earlier word to start on, the words are not an expansion.
  @Test func `with no content word to start on there is none`() {
    #expect(pairs("Dial the dialed directory number (TN) now").isEmpty)
  }

  /// Moving back is only safe when the words it takes in are the short form's
  /// own. `routers` has no letter of `ABN`, so `all routers in a Border Network`
  /// is not its expansion, and neither is `a Border Network`. (With `AN`, the
  /// window of four words already stops short of `all`.)
  @Test func `moving back does not take in words the short form lacks`() {
    #expect(pairs("applies to all routers in a Border Network (ABN) that").isEmpty)
    #expect(pairs("applies to all routers in a Network (AN) that").isEmpty)
  }

  /// Nor does it land on a function word that opens the sentence: `A` is no
  /// better a start for being capitalized. The first `A` of `ANN` is the `a` of
  /// `and`.
  @Test func `moving back does not land on a capitalized function word`() {
    #expect(pairs("A Network and a Node (ANN) are").isEmpty)
  }

  @Test func `more function words do not start an expansion`() {
    #expect(pairs("support for this Protocol (TP) is optional").isEmpty)
    #expect(pairs("a label is used within Multiprotocol Networks (WMN)").isEmpty)
  }

  /// A hyphenated word is one word, so `on-path` is not the function word `on`.
  @Test func `a hyphenated word is one word`() {
    #expect(pairs("from on-path attackers (OPAs) that") == ["OPAs=on-path attackers"])
  }

  /// Nor does a match start partway into one: `peer` inside `peer-to-peer` is
  /// not a word of its own.
  @Test func `a match does not start inside a hyphenated word`() {
    #expect(pairs("uses a peer-to-peer Transport (PT) for") == ["PT=peer-to-peer Transport"])
    #expect(pairs("a peer-to-peer Overlay (TO) is").isEmpty)
  }

  private func glossary(_ term: String, _ definition: String) -> String? {
    Abbreviations.glossaryEntry(
      term: term, definition: [.paragraph(Paragraph(text: definition))])?.long
  }

  /// An IANA registration's `URI:` field is a value, not an expansion; 115 of them
  /// were read as one across the corpus. The glossary phrase ends at its first `:`,
  /// and what is left, `urn`, does not hold the letters.
  @Test func `a URN is not an expansion`() {
    #expect(glossary("URI:", "urn:ietf:params:xml:ns:yang:ietf-bfd-types") == nil)
  }

  /// Letters matched across an `=`, an `@` or a `<` are code, an address or
  /// markup, not words.
  @Test func `code is not an expansion`() {
    #expect(pairs("the attribute Hash=Algorithm Name (HAN) is").isEmpty)
    #expect(pairs("the From header's user@Host (UH) part").isEmpty)
    #expect(pairs("encoded as Type <Length> Value (TLV) triples").isEmpty)
  }

  /// The citations a definition ends with are its sources.
  @Test func `trailing citations are not part of the expansion`() {
    #expect(glossary("PCE", "Path Computation Element RFC 4655") == "Path Computation Element")
    #expect(
      glossary("NVC", "Number of Virtual Components RFC 4328 RFC 4606")
        == "Number of Virtual Components")
    #expect(glossary("PCE", "Path Computation Element RFC-4655") == "Path Computation Element")
    #expect(glossary("DS", "Differentiated Services BCP 38") == "Differentiated Services")
    #expect(glossary("IP", "Internet Protocol STD 5") == "Internet Protocol")
    #expect(glossary("PCE", "Path Computation Element I-D") == "Path Computation Element")
  }

  /// A citation the parser linked reads `RFC 4655` with a no-break space, which
  /// `CrossReference.nonBreakingLabel` puts there so the label never wraps.
  @Test func `a linked citation is not part of the expansion`() {
    func definition(_ section: String?) -> [Block] {
      [
        .paragraph(
          Paragraph([
            .text("Path Computation Element "),
            .crossReference(CrossReference(target: .document(.rfc(4655), section: section))),
          ]))
      ]
    }
    #expect(
      Abbreviations.glossaryEntry(term: "PCE", definition: definition(nil))?.long
        == "Path Computation Element")
    #expect(
      Abbreviations.glossaryEntry(term: "PCE", definition: definition("4.2"))?.long
        == "Path Computation Element")
  }

  @Test func `a glossary phrase ends at a colon or a dash`() {
    #expect(
      glossary("SR-DB", "Segment Routing Database: the collection of SRGBs")
        == "Segment Routing Database")
    #expect(
      glossary("ASBR", "Autonomous System Border Router -- a router used to connect ASes")
        == "Autonomous System Border Router")
    #expect(
      glossary("ASBR", "Autonomous System Border Router - a router used to connect ASes")
        == "Autonomous System Border Router")
    #expect(
      glossary("ASBR", "Autonomous System Border Router\u{2014}a router used to connect ASes")
        == "Autonomous System Border Router")
  }

  /// A dash with no space around it joins a word, and the phrase keeps it.
  @Test func `a hyphenated term keeps its hyphen`() {
    #expect(glossary("OPA", "On-Path Attacker - an attacker on the path") == "On-Path Attacker")
    #expect(glossary("AI", "All-Intra - every picture is intra-coded") == "All-Intra")
  }

  /// A definition that is a sentence holding the letters is not their expansion.
  /// The letters do match the whole of it; what rules it out is its length, one
  /// word past the cap here and far past it in the second.
  @Test func `a sentence is not a glossary expansion`() {
    let sentence =
      "The legacy Route definition lacks the option to cater for packet-dependent routing"
    #expect(Abbreviations.longForm(of: "Type-P", in: sentence) == sentence)
    #expect(glossary("Type-P", sentence) == nil)
    let long =
      "Round trip time measured by each sender between sending a segment and seeing its acknowledgment"
    #expect(Abbreviations.longForm(of: "RTT", in: long) == long)
    #expect(glossary("RTT", long) == nil)
  }

  /// A first use is not held to a word count: its expansion can have more words
  /// than letters, as long as they fit Schwartz and Hearst's window.
  @Test func `a long first use is kept`() {
    #expect(
      pairs("uses Bottleneck Bandwidth and Round-trip propagation time (BBR) to")
        == ["BBR=Bottleneck Bandwidth and Round-trip propagation time"])
  }
}
