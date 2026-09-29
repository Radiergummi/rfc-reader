import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// Scoring `LegacyTextParser` against the RFCs whose text xml2rfc generated from
/// their XML (#42): the same blocks are pulled out of both documents, normalized so
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

  @Test func `every heading is extracted, then every artwork and source code, in document order`() {
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
        GroundTruth.Block(kind: .heading, content: "1.1 Syntax"),
        GroundTruth.Block(kind: .artwork, content: "+--+"),
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

  /// xml2rfc prints a placeholder for artwork it has only as SVG, so the text can
  /// never hold it: expecting it would be a miss the parser cannot avoid.
  @Test func `artwork with no text to find is not expected`() {
    let svg = Block.preformatted(
      Preformatted(kind: .artwork, text: "  <svg> </svg>  ", type: "svg"))
    let blank = artwork("   \n  ")
    let blocks = GroundTruth.blocks(
      of: document([Section(anchor: "s1", number: "1", title: "Art", blocks: [svg, blank])]))
    #expect(blocks == [GroundTruth.Block(kind: .heading, content: "1 Art")])
  }

  /// xml2rfc prints a superscript as `^(8)`, which is the text the parser reads.
  @Test func `a heading's superscript is written as xml2rfc prints it`() {
    let section = Section(
      anchor: "s4", number: "4",
      title: [.text("A Scheme over GF(2"), .superscript("8"), .text(")")])
    #expect(
      GroundTruth.blocks(of: document([section]))
        == [GroundTruth.Block(kind: .heading, content: "4 A Scheme over GF(2^(8))")])
  }

  @Test func `an unnumbered heading is its title alone`() {
    let blocks = GroundTruth.blocks(
      of: document([Section(anchor: "ack", title: "Acknowledgements")]))
    #expect(blocks == [GroundTruth.Block(kind: .heading, content: "Acknowledgements")])
  }

  // MARK: - Normalization

  /// xml2rfc indents artwork by three, the legacy text by whatever the author used,
  /// and a page break leaves blank lines inside a figure.
  @Test func `verbatim text loses its indentation, trailing space and blank lines`() {
    #expect(
      GroundTruth.normalize(verbatim: "      +---+   \n\n      | A |\n      +---+\n")
        == "+---+\n| A |\n+---+")
  }

  /// The parser expands tabs to eight columns before it reads a line, and xml2rfc
  /// prints them expanded, so a tab in the XML is the spaces it stands for.
  @Test func `verbatim text has its tabs expanded to eight columns`() {
    #expect(GroundTruth.normalize(verbatim: "   \t+--+\n  a\tb") == "      +--+\na     b")
  }

  /// Only the common indentation goes: the shape of a diagram is its content.
  @Test func `verbatim text keeps its relative indentation`() {
    #expect(GroundTruth.normalize(verbatim: "   a\n     b\n   c") == "a\n  b\nc")
  }

  /// xml2rfc writes the markers of `<sourcecode markers="true">` into the text; the
  /// element does not hold them.
  @Test func `verbatim text loses the markers around marked code`() {
    #expect(
      GroundTruth.normalize(
        verbatim: "   <CODE BEGINS> file \"ex-a.yang\"\n     module ex-a {\n     }\n   <CODE ENDS>")
        == "module ex-a {\n}")
  }

  @Test func `a heading's number loses its trailing dot and its spacing collapses`() {
    #expect(
      GroundTruth.normalize(number: "3.2.", title: "Message   Format ") == "3.2 Message Format")
  }

  /// xml2rfc prints a non-breaking hyphen as a hyphen and drops the invisible
  /// joiners, so a title holding them compares with the text it printed.
  @Test func `a heading's non-breaking hyphens are hyphens and its joiners go`() {
    #expect(
      GroundTruth.normalize(number: "2", title: "DNS\u{2011}SD over\u{2060} TLS\u{200B}")
        == "2 DNS-SD over TLS")
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

  /// Plain text cannot say what is code, so a grammar kept whole as artwork is a
  /// block the parser got right, and `verbatim` says so while the per-kind scores
  /// say what it was called.
  @Test func `verbatim matches artwork and source code whatever they were called`() {
    let score = GroundTruth.score(
      found: [
        GroundTruth.Block(kind: .artwork, content: "a = b"),
        GroundTruth.Block(kind: .artwork, content: "a piece"),
      ],
      expected: [
        GroundTruth.Block(kind: .sourceCode, content: "a = b"),
        GroundTruth.Block(kind: .artwork, content: "a piece\nand the rest"),
      ])
    #expect(
      score[.verbatim] == GroundTruth.Counts(truePositives: 1, falsePositives: 1, falseNegatives: 1)
    )
  }

  @Test func `precision and recall are undefined with nothing to divide by`() {
    let none = GroundTruth.Counts(truePositives: 0, falsePositives: 0, falseNegatives: 0)
    #expect(none.precision == nil)
    #expect(none.recall == nil)
    let some = GroundTruth.Counts(truePositives: 3, falsePositives: 1, falseNegatives: 2)
    #expect(some.precision == 0.75)
    #expect(some.recall == 0.6)
  }

  /// So score.json can be read without recomputing them.
  @Test func `counts are written with their precision and recall`() throws {
    let counts = GroundTruth.Counts(truePositives: 3, falsePositives: 1, falseNegatives: 0)
    let json =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(counts)) as? [String: Any]
    #expect(json?["precision"] as? Double == 0.75)
    #expect(json?["recall"] as? Double == 1)
    #expect(json?["truePositives"] as? Int == 3)
  }

  @Test func `counts add up across documents`() {
    let first = GroundTruth.Counts(truePositives: 1, falsePositives: 2, falseNegatives: 3)
    let second = GroundTruth.Counts(truePositives: 4, falsePositives: 5, falseNegatives: 6)
    #expect(
      first + second == GroundTruth.Counts(truePositives: 5, falsePositives: 7, falseNegatives: 9))
  }

  // MARK: - The report

  /// Totals per kind over every document, and the documents worst first, so the
  /// ones to read first head the list.
  @Test func `the report totals each kind and ranks the documents by errors`() {
    func counts(_ found: Int, _ invented: Int, _ missed: Int) -> [GroundTruth.Kind: GroundTruth
      .Counts]
    {
      [
        .heading: GroundTruth.Counts(
          truePositives: found, falsePositives: invented, falseNegatives: missed)
      ]
    }
    let report = GroundTruthReport(documents: [
      (.rfc(9000), counts(4, 0, 0)),
      (.rfc(8999), counts(1, 2, 3)),
      (.rfc(9110), counts(2, 1, 0)),
    ])
    #expect(report.documents.map(\.document) == ["rfc8999", "rfc9110", "rfc9000"])
    #expect(report.documents.map(\.errors) == [5, 1, 0])
    let headings = report.kinds["heading"]
    #expect(headings?.truePositives == 7)
    #expect(headings?.falsePositives == 3)
    #expect(headings?.falseNegatives == 3)
    #expect(headings?.precision == 0.7)
    #expect(headings?.recall == 0.7)
    // A kind no document had is reported, with nothing to divide by.
    #expect(report.kinds["artwork"]?.truePositives == 0)
    #expect(report.kinds["artwork"]?.precision == nil)
  }

  /// A grammar the parser kept whole as artwork is one block, not three errors:
  /// a document's errors are its headings' and its verbatim blocks'.
  @Test func `a document's errors count each block once`() {
    let report = GroundTruthReport(documents: [
      (
        .rfc(9110),
        [
          .artwork: GroundTruth.Counts(truePositives: 0, falsePositives: 1, falseNegatives: 0),
          .sourceCode: GroundTruth.Counts(truePositives: 0, falsePositives: 0, falseNegatives: 1),
          .verbatim: GroundTruth.Counts(truePositives: 1, falsePositives: 0, falseNegatives: 0),
          .heading: GroundTruth.Counts(truePositives: 2, falsePositives: 0, falseNegatives: 1),
        ]
      )
    ])
    #expect(report.documents.map(\.errors) == [1])
  }
}
