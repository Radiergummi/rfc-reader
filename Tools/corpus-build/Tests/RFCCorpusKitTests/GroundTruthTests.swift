import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// Scoring `LegacyTextParser` against the RFCs whose text xml2rfc generated from
/// their XML (#42): the same blocks are pulled out of both documents, normalised so
/// that xml2rfc's rendering of a block and the block itself compare equal, and
/// matched as multisets per kind. Guard-level: hand-built documents, no RFC text.
@Suite("Ground truth")
struct GroundTruthTests {
  private func document(_ sections: [Section], abstract: [Block] = []) -> RFCDocument {
    RFCDocument(
      header: DocumentHeader(title: "A Protocol", abstract: abstract), sections: sections,
      source: .xml)
  }

  private func artwork(_ text: String) -> Block {
    .preformatted(Preformatted(kind: .artwork, text: text))
  }

  private func sourceCode(_ text: String) -> Block {
    .preformatted(Preformatted(kind: .sourceCode, text: text, type: "abnf"))
  }

  // MARK: - Extraction

  @Test func `every heading, artwork and source code is extracted in document order`() {
    let blocks = GroundTruth.blocks(
      of: document([
        Section(
          anchor: "s1", number: "1", title: "Introduction",
          blocks: [.paragraph(Paragraph(text: "Prose is not scored.")), artwork("+--+")],
          subsections: [
            Section(anchor: "s1.1", number: "1.1", title: "Syntax", blocks: [sourceCode("a = b")])
          ])
      ]))
    #expect(
      blocks == [
        GroundTruth.Block(kind: .heading, content: "1 Introduction"),
        GroundTruth.Block(kind: .artwork, content: "+--+"),
        GroundTruth.Block(kind: .heading, content: "1.1 Syntax"),
        GroundTruth.Block(kind: .sourceCode, content: "a = b"),
      ])
  }

  /// xml2rfc wraps artwork in a figure, and the parser may too.
  @Test func `artwork inside a figure or a list is extracted`() {
    let figure = Block.figure(Figure(title: "A Diagram", blocks: [artwork("[ A ]")]))
    let list = Block.list(ListBlock(style: .bullet, items: [ListItem(blocks: [artwork("[ B ]")])]))
    let blocks = GroundTruth.blocks(
      of: document([Section(anchor: "s1", number: "1", title: "Figures", blocks: [figure, list])]))
    #expect(blocks.filter { $0.kind == .artwork }.map(\.content) == ["[ A ]", "[ B ]"])
  }

  @Test func `an unnumbered heading is its title alone`() {
    let blocks = GroundTruth.blocks(
      of: document([Section(anchor: "ack", title: "Acknowledgements")]))
    #expect(blocks == [GroundTruth.Block(kind: .heading, content: "Acknowledgements")])
  }

  // MARK: - Normalisation

  /// xml2rfc indents artwork by three, the legacy text by whatever the author used,
  /// and a page break leaves blank lines inside a figure.
  @Test func `verbatim text loses its indentation, trailing space and blank lines`() {
    #expect(
      GroundTruth.normalize(verbatim: "      +---+   \n\n      | A |\n      +---+\n")
        == "+---+\n| A |\n+---+")
  }

  /// Only the common indentation goes: the shape of a diagram is its content.
  @Test func `verbatim text keeps its relative indentation`() {
    #expect(GroundTruth.normalize(verbatim: "   a\n     b\n   c") == "a\n  b\nc")
  }

  @Test func `a heading's number loses its trailing dot and its spacing collapses`() {
    #expect(
      GroundTruth.normalize(number: "3.2.", title: "Message   Format ") == "3.2 Message Format")
  }

  // MARK: - Scoring

  @Test func `blocks are matched as multisets of each kind`() {
    let expected = [
      GroundTruth.Block(kind: .artwork, content: "x"),
      GroundTruth.Block(kind: .artwork, content: "x"),
      GroundTruth.Block(kind: .heading, content: "1 Intro"),
    ]
    let found = [
      GroundTruth.Block(kind: .artwork, content: "x"),
      GroundTruth.Block(kind: .artwork, content: "y"),
      GroundTruth.Block(kind: .heading, content: "1 Intro"),
    ]
    let score = GroundTruth.score(found: found, expected: expected)
    #expect(
      score[.artwork] == GroundTruth.Counts(truePositives: 1, falsePositives: 1, falseNegatives: 1))
    #expect(
      score[.heading] == GroundTruth.Counts(truePositives: 1, falsePositives: 0, falseNegatives: 0))
    #expect(
      score[.sourceCode]
        == GroundTruth.Counts(truePositives: 0, falsePositives: 0, falseNegatives: 0))
  }

  /// Source code the parser calls artwork is missed as source code and invented as
  /// artwork: the kind is part of what is scored.
  @Test func `the same content under another kind is a miss and an invention`() {
    let score = GroundTruth.score(
      found: [GroundTruth.Block(kind: .artwork, content: "a = b")],
      expected: [GroundTruth.Block(kind: .sourceCode, content: "a = b")])
    #expect(score[.artwork]?.falsePositives == 1)
    #expect(score[.sourceCode]?.falseNegatives == 1)
  }

  @Test func `precision and recall are undefined with nothing to divide by`() {
    let none = GroundTruth.Counts(truePositives: 0, falsePositives: 0, falseNegatives: 0)
    #expect(none.precision == nil)
    #expect(none.recall == nil)
    let some = GroundTruth.Counts(truePositives: 3, falsePositives: 1, falseNegatives: 2)
    #expect(some.precision == 0.75)
    #expect(some.recall == 0.6)
  }

  @Test func `counts add up across documents`() {
    let a = GroundTruth.Counts(truePositives: 1, falsePositives: 2, falseNegatives: 3)
    let b = GroundTruth.Counts(truePositives: 4, falsePositives: 5, falseNegatives: 6)
    #expect(a + b == GroundTruth.Counts(truePositives: 5, falsePositives: 7, falseNegatives: 9))
  }

  // MARK: - Fetching the pairs

  /// The text of the RFCs that have XML: the half the ordinary text fetch skips,
  /// because xml2rfc generated it.
  @Test func `the paired text is the text of every RFC with XML`() throws {
    let index = try RFCIndexParser.parse(contentsOf: Fixtures.url("rfc-index-sample.xml"))
    #expect(FetchPlan.pairedText(in: index, limit: nil).map(\.number) == [8999, 9000, 9110])
  }
}
