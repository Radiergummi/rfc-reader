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

  /// A diagram's spacing is what it draws: a field moved along a ruler is a change.
  @Test func `a figure whose spacing changed is replaced`() {
    let old = Block.preformatted(Preformatted(kind: .artwork, text: "|  A  |    B    |"))
    let new = Block.preformatted(Preformatted(kind: .artwork, text: "|    A    |  B  |"))
    let diff = RevisionDiff(
      from: document([Section(anchor: "s", title: "Format", blocks: [old])]),
      to: document([Section(anchor: "s", title: "Format", blocks: [new])]))
    #expect(diff.blocks == [RevisionDiff.BlockKey(section: "s", index: 0): .replaced(old)])
  }

  /// A paragraph edited after a figure inserted before it is still reworded: the
  /// figure is passed over to pair the paragraph with the next one.
  @Test func `a paragraph edited behind a new figure is reworded`() {
    let figure = Block.preformatted(Preformatted(kind: .artwork, text: "+---+\n| A |\n+---+"))
    let old = Section(
      anchor: "s", title: "Overview",
      blocks: [paragraph(introduction), paragraph("A client MAY retry."), paragraph(terminology)])
    let new = Section(
      anchor: "s", title: "Overview",
      blocks: [
        paragraph(introduction), figure, paragraph("A client SHOULD retry."),
        paragraph(terminology),
      ])
    let diff = RevisionDiff(from: document([old]), to: document([new]))
    #expect(diff.removedBlocks.isEmpty)
    #expect(diff.blocks[RevisionDiff.BlockKey(section: "s", index: 1)] == .inserted)
    #expect(
      diff.blocks[RevisionDiff.BlockKey(section: "s", index: 2)]
        == .reworded([.same("A client "), .deleted("MAY"), .inserted("SHOULD"), .same(" retry.")]))
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

  /// A text draft's anchors are its numbers: a section inserted before others moves
  /// their numbers on, and they are paired by what they say, not where they stand.
  @Test func `a section inserted before numbered ones moves no text onto another`() {
    func section(_ number: String, _ title: String, _ text: String) -> Section {
      Section(
        anchor: "section-\(number)", number: number, title: title, blocks: [paragraph(text)])
    }
    let security = "Implementations need to authenticate every peer they accept first."
    let old = [section("1", "Introduction", introduction), section("2", "Security", security)]
    let new = [
      section("1", "Introduction", introduction),
      section("2", "Terminology", terminology), section("3", "Security", security),
    ]
    let diff = RevisionDiff(from: document(old), to: document(new))
    #expect(diff.sections == ["section-2": .added])
    #expect(diff.blocks.isEmpty)
  }

  /// A heading over its subsections has no prose to be paired by: renumbered, it is
  /// paired by its title, and is not removed and added again.
  @Test func `a section of only subsections renumbered keeps its pair`() {
    let operation = "A sender opens a stream for each request it makes of the peer."
    func operations(_ number: String) -> Section {
      Section(
        anchor: "section-\(number)", number: number, title: "Protocol Operation",
        subsections: [
          Section(
            anchor: "section-\(number).1", number: "\(number).1", title: "Streams",
            blocks: [paragraph(operation)])
        ])
    }
    let intro = Section(
      anchor: "section-1", number: "1", title: "Introduction", blocks: [paragraph(introduction)])
    let terms = Section(
      anchor: "section-2", number: "2", title: "Terminology", blocks: [paragraph(terminology)])
    let diff = RevisionDiff(
      from: document([intro, operations("2")]), to: document([intro, terms, operations("3")]))
    #expect(diff.sections == ["section-2": .added])
    #expect(diff.removedSections.isEmpty)
    #expect(diff.blocks.isEmpty)
  }

  /// A text draft's subsection keeps its anchor and its title under another parent
  /// once a section is inserted before it: it is paired where it went, not with the
  /// subsection that now has its number.
  @Test func `a subsection is paired under its own parent, not by its number`() {
    func subsection(_ number: String, _ text: String) -> Section {
      Section(
        anchor: "section-\(number)", number: number, title: "Overview",
        blocks: [paragraph(text)])
    }
    let framing = "Every frame starts with a type and a length that the receiver reads first."
    let errors = "An endpoint that detects an error closes the connection with a code."
    let old = [
      Section(
        anchor: "section-1", number: "1", title: "Framing",
        subsections: [subsection("1.1", framing)])
    ]
    let new = [
      Section(
        anchor: "section-1", number: "1", title: "Errors",
        subsections: [subsection("1.1", errors)]),
      Section(
        anchor: "section-2", number: "2", title: "Framing",
        subsections: [subsection("2.1", framing)]),
    ]
    let diff = RevisionDiff(from: document(old), to: document(new))
    #expect(diff.sections["section-1.1"] == .added)
    #expect(diff.blocks[RevisionDiff.BlockKey(section: "section-2.1", index: 0)] == nil)
    #expect(diff.blocks[RevisionDiff.BlockKey(section: "section-1.1", index: 0)] == nil)
  }

  /// A section retitled changes its subsections' title paths, not them: one with no
  /// prose to be paired by keeps its anchor and its title, and is paired by those.
  @Test func `a section retitled keeps the pairs of its subsections`() {
    func protocolSection(_ title: String) -> Section {
      let types = Section(
        anchor: "frame-types", number: "1.1.1", title: "Frame Types",
        blocks: [
          paragraph("Every frame starts with a type and a length that the receiver reads first.")
        ])
      let framing = Section(
        anchor: "framing", number: "1.1", title: "Framing", subsections: [types])
      return Section(
        anchor: "protocol", number: "1", title: title, blocks: [paragraph(introduction)],
        subsections: [framing])
    }
    let diff = RevisionDiff(
      from: document([protocolSection("Protocol")]),
      to: document([protocolSection("Protocol Operation")]))
    #expect(diff.sections.isEmpty)
    #expect(diff.removedSections.isEmpty)
    #expect(diff.retitled == ["protocol": "1. Protocol"])
  }

  @Test func `a heading reworded and an abstract changed are changes`() {
    let old = RFCDocument(
      header: DocumentHeader(title: "T", abstract: [paragraph("An old abstract of the protocol.")]),
      sections: [Section(anchor: "sec", title: "Security", blocks: [paragraph(introduction)])],
      source: .xml)
    let new = RFCDocument(
      header: DocumentHeader(title: "T", abstract: [paragraph("A new abstract of the protocol.")]),
      sections: [
        Section(anchor: "sec", title: "Security and Privacy", blocks: [paragraph(introduction)])
      ],
      source: .xml)
    let diff = RevisionDiff(from: old, to: new)
    #expect(diff.retitled == ["sec": "Security"])
    let abstract = diff.blocks[RevisionDiff.BlockKey(section: RevisionDiff.abstractKey, index: 0)]
    #expect(abstract.map { if case .reworded = $0 { true } else { false } } == true)
  }
}
