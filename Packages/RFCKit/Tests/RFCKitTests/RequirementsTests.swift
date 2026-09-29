import Foundation
import Testing

@testable import RFCKit

/// Every BCP 14 requirement a document states (#180): the sentence, its keywords,
/// and where it is.
@Suite("Requirements")
struct RequirementsTests {
  // MARK: - Keywords

  @Test func `a negated keyword is read whole, before the one it contains`() {
    #expect(
      Requirements.keywords(in: "A client MUST NOT retry, and MUST close.") == [.mustNot, .must])
    #expect(Requirements.keywords(in: "It is NOT RECOMMENDED to cache.") == [.notRecommended])
    #expect(
      Requirements.keywords(in: "Servers SHOULD NOT, and SHALL NOT.") == [.shouldNot, .shallNot])
  }

  /// RFC 8174: only the uppercase words are the keywords.
  @Test func `only uppercase whole words are keywords`() {
    #expect(Requirements.keywords(in: "A server must reply.") == [])
    #expect(Requirements.keywords(in: "MUSTARD and MAYBE are not keywords.") == [])
    #expect(Requirements.keywords(in: "REQUIRED; OPTIONAL. MAY") == [.required, .optional, .may])
  }

  // MARK: - Sentences

  @Test func `sentences end at a stop followed by a capital or a digit`() {
    #expect(
      Requirements.sentences(in: "The client MUST send it. The server MAY drop it! 2 bytes follow.")
        == ["The client MUST send it.", "The server MAY drop it!", "2 bytes follow."])
  }

  @Test func `an abbreviation or a number does not end a sentence`() {
    #expect(
      Requirements.sentences(in: "Use a token, e.g. The One. Versions such as 1.1 and 4.2.1 apply.")
        == ["Use a token, e.g. The One.", "Versions such as 1.1 and 4.2.1 apply."])
    #expect(
      Requirements.sentences(in: "Fields, i.e. Headers, are sent. See Sec. 4 for more.")
        == ["Fields, i.e. Headers, are sent.", "See Sec. 4 for more."])
  }

  /// "etc." ends the list and, followed by a capital, nearly always the sentence.
  @Test func `etc. ends a sentence`() {
    #expect(
      Requirements.sentences(in: "Send A, B, etc. The server MUST reply.")
        == ["Send A, B, etc.", "The server MUST reply."])
  }

  /// A sentence can open on a quoted name or a citation as well as on a capital.
  @Test func `a sentence may begin with an opening quote or bracket`() {
    #expect(
      Requirements.sentences(in: #"The flag MUST be zero. "len" MUST be set. [KEYWORDS] applies."#)
        == ["The flag MUST be zero.", #""len" MUST be set."#, "[KEYWORDS] applies."])
  }

  @Test func `a stop inside quotes or parentheses ends the sentence after them`() {
    #expect(
      Requirements.sentences(in: #"It is called "done." Then it MUST stop (as below.) Next."#)
        == [#"It is called "done.""#, "Then it MUST stop (as below.)", "Next."])
  }

  // MARK: - The declaration

  /// However the key words are declared, the declaration is not a requirement.
  @Test(arguments: [
    #"In this memo "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY" and "OPTIONAL" carry the meanings BCP 14 gives them."#,
    #"The key words "MUST", "SHOULD", and "MAY" are to be interpreted as defined in RFC 2119."#,
    #"The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are used as specified in [KEYWORDS]."#,
    // Fewer than five, and not "interpreted": known by the key words being quoted.
    "This memo uses the terms 'MUST', 'SHOULD' and 'MAY' in the sense given in [KEYWORDS].",
  ])
  func `the declaration of the key words is recognized however it is worded`(sentence: String) {
    #expect(Requirements.declaresKeywords(sentence))
  }

  @Test func `a requirement citing RFC 2119 is still a requirement`() {
    #expect(!Requirements.declaresKeywords("Implementations MUST follow RFC 2119 conventions."))
  }

  /// BCP 14 is cited as the group of RFC 2119 and RFC 8174 as often as by either.
  @Test func `a document citing BCP 14 itself has requirements`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "S",
          blocks: [
            .paragraph(Paragraph(text: "A client MUST retry.")),
            .references(
              ReferenceList(
                title: "Normative References",
                entries: [
                  Reference(
                    anchor: "BCP14", title: "BCP14 consists of RFC 2119, RFC 8174",
                    seriesInfo: [SeriesInfo(name: "BCP", value: "14")])
                ])),
          ])
      ],
      source: .xml)
    #expect(Requirements.extract(from: document).map(\.sentence) == ["A client MUST retry."])
  }

  /// RFC 2119 is BCP 14, so its own key words are used in their BCP 14 sense, and
  /// it names no other part of BCP 14 to say so. It used to qualify by citing
  /// itself, which `referencedDocuments` no longer counts (#279).
  @Test func `a document that is part of BCP 14 has requirements`() throws {
    let document = try Fixtures.document("rfc2119.txt")
    #expect(!Requirements.extract(from: document).isEmpty)
  }

  // MARK: - Where a requirement lands

  /// A requirement lands on the nearest anchor around it: its paragraph's, else its
  /// list item's or definition's, else its section's.
  @Test func `a requirement lands on its list item or definition`() {
    let item = ListItem(
      blocks: [.paragraph(Paragraph(text: "A client MUST retry."))], anchor: "item-1")
    let definition = DefinitionItem(
      term: [.text("Retry")], definition: [.paragraph(Paragraph(text: "A server MAY refuse."))],
      anchor: "term-retry", definitionAnchor: "def-retry")
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "S",
          blocks: [
            .list(ListBlock(style: .bullet, items: [item])),
            .definitionList([definition]),
            .references(
              ReferenceList(
                title: "Normative References",
                entries: [
                  Reference(
                    anchor: "RFC2119", title: "Key words",
                    seriesInfo: [SeriesInfo(name: "RFC", value: "2119")])
                ])),
          ])
      ],
      source: .xml)
    #expect(Requirements.extract(from: document).map(\.anchor) == ["item-1", "def-retry"])
  }

  /// A cell of key words alone says nothing without the row it is in, so the row
  /// is one requirement; a cell that is a sentence of its own stays one.
  @Test func `a table row whose cell is only key words is one requirement`() {
    let table = Table(
      title: nil, header: [Table.Row(cells: [[.text("Algorithm")], [.text("Status")]])],
      rows: [
        Table.Row(cells: [[.text("alg-one")], [.text("MUST")]]),
        Table.Row(cells: [[.text("alg-two")], [.text("SHOULD NOT")]]),
        Table.Row(cells: [[.text("Field")], [.text("It MAY be empty.")]]),
      ])
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "S",
          blocks: [
            .table(table),
            .references(
              ReferenceList(
                title: "Normative References",
                entries: [
                  Reference(
                    anchor: "RFC2119", title: "Key words",
                    seriesInfo: [SeriesInfo(name: "RFC", value: "2119")])
                ])),
          ])
      ],
      source: .xml)
    #expect(
      Requirements.extract(from: document).map(\.sentence)
        == ["alg-one | MUST", "alg-two | SHOULD NOT", "It MAY be empty."])
  }

  // MARK: - Through parse

  /// The author tagged every keyword with `<bcp14>`: the extractor, which reads
  /// uppercase words, finds as many in the requirements as the author tagged
  /// outside the boilerplate that declares them.
  @Test(arguments: ["rfc9197.xml", "rfc9783.xml"])
  func `every keyword the author tagged is found`(fixture: String) throws {
    let xml = try Fixtures.string(fixture)
    let tagged = xml.matches(of: /<bcp14>/).count
    let document = try RFCXMLParser.parse(try Fixtures.data(fixture))
    let requirements = Requirements.extract(from: document)
    let boilerplate = BCP14Keyword.allCases.count
    #expect(requirements.flatMap(\.keywords).count == tagged - boilerplate)
    #expect(!requirements.contains { $0.sentence.contains("interpreted as described in BCP") })
    #expect(requirements.allSatisfy { !$0.isHeuristic })
  }

  @Test func `a requirement knows its section and lands on its paragraph`() throws {
    let document = try RFCXMLParser.parse(try Fixtures.data("rfc9197.xml"))
    let requirement = try #require(Requirements.extract(from: document).first)
    let section = try #require(document.section(anchor: requirement.sectionAnchor))
    #expect(requirement.sectionTitle == section.titleText)
    #expect(requirement.sectionNumber == section.number)
    #expect(!requirement.anchor.isEmpty)
    #expect(!requirement.keywords.isEmpty)
  }

  /// A document that never invokes BCP 14 states no requirements, however it
  /// capitalizes its words.
  @Test func `a document that does not cite BCP 14 has no requirements`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc793.txt"))
    #expect(!document.referencedDocuments.contains(.rfc(2119)))
    #expect(Requirements.extract(from: document).isEmpty)
  }

  @Test func `requirements read from legacy text are marked heuristic`() throws {
    var found: [Requirement] = []
    for name in try Fixtures.legacyTexts() where found.isEmpty {
      found = Requirements.extract(from: LegacyTextParser.parse(try Fixtures.data(name)))
    }
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { $0.isHeuristic })
  }
}
