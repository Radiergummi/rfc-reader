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
      Requirements.sentences(in: "Fields, i.e. Headers, etc. Are sent. See Sec. 4 for more.")
        == ["Fields, i.e. Headers, etc. Are sent.", "See Sec. 4 for more."])
  }

  @Test func `a stop inside quotes or parentheses ends the sentence after them`() {
    #expect(
      Requirements.sentences(in: #"It is called "done." Then it MUST stop (as below.) Next."#)
        == [#"It is called "done.""#, "Then it MUST stop (as below.)", "Next."])
  }

  // MARK: - The declaration

  /// However the key words are declared, the declaration is not a requirement.
  @Test(arguments: [
    #"The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14."#,
    #"The key words "MUST", "SHOULD", and "MAY" are to be interpreted as defined in RFC 2119."#,
    #"The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are used as specified in [KEYWORDS]."#,
  ])
  func `the declaration of the key words is recognized however it is worded`(sentence: String) {
    #expect(Requirements.declaresKeywords(sentence))
  }

  @Test func `a requirement citing RFC 2119 is still a requirement`() {
    #expect(!Requirements.declaresKeywords("Implementations MUST follow RFC 2119 conventions."))
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
