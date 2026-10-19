import Testing

@testable import RFCKit

/// What changed from one revision to the next (#729), over model values written by
/// hand in the shape of a draft's: no parse is involved, and no draft's text is
/// quoted.
@Suite("Revision diff")
struct RevisionDiffTests {
  private func document(_ sections: [Section]) -> RFCDocument {
    RFCDocument(header: DocumentHeader(title: "An Example"), sections: sections, source: .xml)
  }

  private func paragraph(_ text: String) -> Block {
    .paragraph(Paragraph(text: text))
  }

  private let introduction = "This document describes an example protocol for testing."
  private let terminology = "The key words in this document are to be read as described."

  @Test func `a revision that changed nothing is empty`() {
    let section = Section(
      anchor: "intro", number: "1", title: "Introduction", blocks: [paragraph(introduction)])
    #expect(RevisionDiff(from: document([section]), to: document([section])).isEmpty)
  }

  @Test func `a reworded paragraph carries its word runs`() {
    let old = Section(
      anchor: "intro", number: "1", title: "Introduction",
      blocks: [paragraph(introduction), paragraph("A client MAY retry the request.")])
    let new = Section(
      anchor: "intro", number: "1", title: "Introduction",
      blocks: [paragraph(introduction), paragraph("A client SHOULD retry the request.")])
    let diff = RevisionDiff(from: document([old]), to: document([new]))
    #expect(diff.sections.isEmpty)
    #expect(diff.removedBlocks.isEmpty)
    #expect(
      diff.blocks == [
        RevisionDiff.BlockKey(section: "intro", index: 1): .reworded([
          .same("A client "), .deleted("MAY"), .inserted("SHOULD"), .same(" retry the request."),
        ])
      ])
  }

  @Test func `a block added and one removed are said where they stand`() {
    let figure = Block.preformatted(Preformatted(kind: .artwork, text: "+---+\n| A |\n+---+"))
    let old = Section(
      anchor: "intro", title: "Introduction",
      blocks: [paragraph(introduction), figure, paragraph(terminology)])
    let new = Section(
      anchor: "intro", title: "Introduction",
      blocks: [
        paragraph(introduction), paragraph(terminology),
        paragraph("A new paragraph at the end of the section."),
      ])
    let diff = RevisionDiff(from: document([old]), to: document([new]))
    #expect(diff.blocks == [RevisionDiff.BlockKey(section: "intro", index: 2): .inserted])
    #expect(diff.removedBlocks == [RevisionDiff.BlockKey(section: "intro", index: 1): [figure]])
  }

  /// A figure or code block that changed is shown whole, the old above the new.
  @Test func `a changed figure is replaced, not diffed inside`() {
    let old = Block.preformatted(Preformatted(kind: .sourceCode, text: "{ \"a\": 1 }"))
    let new = Block.preformatted(Preformatted(kind: .sourceCode, text: "{ \"a\": 2 }"))
    let diff = RevisionDiff(
      from: document([
        Section(anchor: "s", title: "Example", blocks: [paragraph(introduction), old])
      ]),
      to: document([Section(anchor: "s", title: "Example", blocks: [paragraph(introduction), new])])
    )
    #expect(diff.blocks == [RevisionDiff.BlockKey(section: "s", index: 1): .replaced(old)])
  }

  @Test func `a section added and one removed are said where they stand`() {
    let intro = Section(anchor: "intro", title: "Introduction", blocks: [paragraph(introduction)])
    let terms = Section(anchor: "terms", title: "Terminology", blocks: [paragraph(terminology)])
    let gone = Section(
      anchor: "history", title: "History",
      blocks: [paragraph("Earlier versions of this protocol were never deployed widely.")])
    let added = Section(
      anchor: "security", title: "Security Considerations",
      blocks: [paragraph("Implementations need to authenticate every peer they accept.")])
    let diff = RevisionDiff(
      from: document([intro, gone, terms]), to: document([intro, terms, added]))
    #expect(diff.sections == ["security": .added])
    #expect(diff.removedSections.map(\.section.anchor) == ["history"])
    #expect(diff.removedSections.first?.after == "intro")
  }

  /// Renumbering is not moving: only a section whose place among the others changed.
  @Test func `a section moved is the one out of the old order`() {
    func section(_ anchor: String, _ number: String, _ text: String) -> Section {
      Section(anchor: anchor, number: number, title: "Section \(number)", blocks: [paragraph(text)])
    }
    let old = [
      section("one", "1", introduction), section("two", "2", terminology),
      section("three", "3", "The third section explains how the protocol recovers."),
    ]
    let new = [
      section("three", "1", "The third section explains how the protocol recovers."),
      section("one", "2", introduction), section("two", "3", terminology),
    ]
    let diff = RevisionDiff(from: document(old), to: document(new))
    #expect(diff.sections == ["three": .moved(from: "3")])
  }

  /// A section renamed and given a new anchor is paired by its prose.
  @Test func `a section with a new anchor is paired by its title and prose`() {
    let prose = "Every message carries a version field that the receiver checks first."
    let old = Section(anchor: "msg-format", title: "Message Format", blocks: [paragraph(prose)])
    let new = Section(anchor: "messages", title: "Message Format", blocks: [paragraph(prose)])
    let diff = RevisionDiff(from: document([old]), to: document([new]))
    #expect(diff.isEmpty)
  }

  @Test func `the longest increasing run`() {
    #expect(RevisionDiff.longestIncreasing([2, 0, 1]).map { [2, 0, 1][$0] } == [0, 1])
    #expect(RevisionDiff.longestIncreasing([0, 1, 2]) == [0, 1, 2])
    #expect(RevisionDiff.longestIncreasing([]).isEmpty)
  }
}
