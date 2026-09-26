import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Builder: document structure")
@MainActor
struct BuilderStructureTests {
  private let style = ReadingStyle()

  /// The bibliography lives in a panel, not in the reading flow, so its sections
  /// are deliberately absent from the storage. Everything else must be there.
  private func bodySections(of document: RFCDocument) -> [Section] {
    document.allSections.filter { !DocumentTextBuilder.holdsOnlyReferences($0) }
  }

  @Test func everySectionAnchorIsIndexed() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    for section in bodySections(of: document) {
      #expect(built.anchors.offset(of: section.anchor) != nil, "missing anchor \(section.anchor)")
    }
  }

  @Test func eachSectionAnchorPointsAtItsHeading() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    let text = built.text.string as NSString
    for section in bodySections(of: document) {
      let offset = try #require(built.anchors.offset(of: section.anchor))
      let length = min((section.displayTitle as NSString).length, text.length - offset)
      let slice = text.substring(with: NSRange(location: offset, length: length))
      #expect(
        slice == section.displayTitle, "anchor \(section.anchor) does not point at its heading")
    }
  }

  /// What an in-document reference's preview names: the heading of the section
  /// it points at, as the reader draws it. "Section 4.2" says where, not what. A
  /// figure is anchored too, but has no heading to name.
  @Test func aSectionAnchorNamesItsHeading() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    for section in bodySections(of: document) {
      #expect(built.anchors.heading(of: section.anchor) == section.displayTitle)
    }
    #expect(built.anchors.offset(of: "fig-long") != nil)
    #expect(built.anchors.heading(of: "fig-long") == nil)
    #expect(built.anchors.heading(of: "no-such-anchor") == nil)
  }

  @Test func theBuilderRecordsAnchorsInDocumentOrder() throws {
    let builder = DocumentTextBuilder(style: style)
    builder.appendDocument(try Fixtures.rfc8999())
    let offsets = builder.entries.map(\.offset)
    #expect(
      offsets == offsets.sorted(),
      "mark() must be called in document order, before the run it names")
  }

  @Test func anchorOffsetsAreInsideTheString() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
    for entry in built.anchors.entries {
      #expect(entry.offset >= 0 && entry.offset <= built.text.length)
    }
  }

  @Test func headingsCarryTheirAnchorForTheVoiceOverRotor() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    let first = try #require(document.sections.first)
    let offset = try #require(built.anchors.offset(of: first.anchor))
    #expect(
      built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String == first.anchor)
  }

  @Test func theAbstractComesBeforeTheFirstSection() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    let abstract = document.header.abstract.compactMap { block -> String? in
      guard case .paragraph(let paragraph) = block else { return nil }
      return paragraph.plainText
    }.first
    let abstractText = try #require(abstract)
    let abstractRange = built.text.string.range(of: abstractText)
    #expect(abstractRange != nil, "the abstract is in the storage, not in the header view")

    let firstSection = try #require(document.sections.first)
    let sectionOffset = try #require(built.anchors.offset(of: firstSection.anchor))
    let abstractOffset = try Fixtures.offset(of: abstractText, in: built.text)
    #expect(abstractOffset < sectionOffset)
  }

  /// Neither parser keeps "Abstract" as a block, and the reader's header view no
  /// longer draws it, so the builder is the only thing left that can.
  @Test func theAbstractIsLabelled() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    let text = built.text.string
    let label = try #require(text.range(of: "Abstract"), "the abstract has no heading")
    #expect(
      try Fixtures.offset(of: "Abstract", in: built.text) == 0,
      "the heading is the first thing in the storage")

    let firstParagraph = try #require(
      document.header.abstract.compactMap { block -> String? in
        guard case .paragraph(let paragraph) = block else { return nil }
        return paragraph.plainText
      }.first)
    let prose = try #require(text.range(of: firstParagraph))
    #expect(
      label.upperBound <= prose.lowerBound,
      "the heading must precede the abstract's first paragraph")

    let offset = try Fixtures.offset(of: "Abstract", in: built.text)
    #expect(
      built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
        == style.headingFont(depth: 1))
    // Anchored like every other heading, so the rotor and `rfc-anchor:` reach it
    // by the general rule — but not a section, so tracking will not report it.
    #expect(built.anchors.offset(of: DocumentTextBuilder.abstractAnchor) == offset)
    #expect(
      built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String
        == DocumentTextBuilder.abstractAnchor)
    #expect(
      built.anchors.sections.offset(of: DocumentTextBuilder.abstractAnchor) == nil,
      "the abstract is not a section")
  }

  @Test func aDocumentWithNoAbstractGetsNoHeading() throws {
    var document = try Fixtures.rfc8999()
    document.header.abstract = []
    let built = DocumentTextBuilder.build(document, style: style)
    #expect(!built.text.string.hasPrefix("Abstract"))
  }

  @Test func headingTextIsTheSectionDisplayTitle() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    for section in bodySections(of: document) {
      // Through `renderedLabel` for the same reason paragraphs are: a heading
      // that cites a document has a chip in it, and a chip is a symbol and a
      // word joiner ahead of its label. The prefix comes from
      // `displayTitleInlines` rather than being composed here, or the appendix
      // branch goes untested -- rfc8999 has one.
      let projection = Self.renderedLabel(section.displayTitleInlines)
      #expect(built.text.string.contains(projection), "missing heading \(section.displayTitle)")
    }
  }

  /// A heading names a document as readily as a paragraph does. Now that
  /// `Section.title` carries inlines, the heading has to be built through the same
  /// inline path as prose, or the reference is drawn as words again.
  @Test func headingsDrawTheirCrossReferences() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "section-8",
          number: "8",
          title: [
            .text("Changes from "),
            .crossReference(CrossReference(target: .document(.rfc(3066), section: nil))),
          ],
          blocks: [.paragraph(Paragraph(text: "Body."))]
        )
      ],
      source: .xml
    )
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try Fixtures.offset(of: "3066", in: built.text)

    #expect(
      built.text.attribute(.link, at: offset, effectiveRange: nil) != nil,
      "the heading's reference is a link")
    #expect(
      built.text.attribute(.rfcChip, at: offset, effectiveRange: nil) != nil,
      "and it is drawn as a chip")
    // The number still comes from `number`, and the heading still reads as one.
    #expect(built.text.string.contains("8. Changes from " + Self.chipPrefix + "RFC\u{00A0}3066"))
    #expect(
      built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String == "section-8")
    let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
    #expect(
      font?.pointSize == style.headingFont(depth: 1).pointSize,
      "a chip in a heading is set at heading size")
  }

  @Test func noParagraphTextIsLost() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    for section in document.allSections {
      for case .paragraph(let paragraph) in section.blocks where !paragraph.plainText.isEmpty {
        let projection = Self.renderedLabel(paragraph.inlines)
        #expect(
          built.text.string.contains(projection),
          "missing paragraph: \(paragraph.plainText.prefix(60))")
      }
    }
  }

  /// The symbol attachment plus the word joiner that stops it wrapping away from
  /// the label it belongs to.
  private static let chipPrefix = "\u{FFFC}\u{2060}"

  /// What the builder should have written for a run of inlines.
  ///
  /// This used to restate the label rules — which brackets come off, how a section
  /// reference is phrased — and had already drifted from them in one place. Those
  /// rules now live on `CrossReference.display`, which `plainText` answers from
  /// too, so the only thing left for the builder to get right is *rendering* them:
  /// the chip's symbol goes in front of the span the model marked, and nothing
  /// else moves.
  private static func renderedLabel(_ inlines: [Inline]) -> String {
    inlines.map { inline -> String in
      switch inline {
      case .text(let text), .code(let text), .superscript(let text), .subscript(let text):
        return text
      case .emphasis(let inner), .strong(let inner), .link(_, let inner):
        return renderedLabel(inner)
      case .crossReference(let xref):
        let display = xref.display
        guard let chip = display.chip else { return display.text }
        return String(display.text[display.text.startIndex..<chip.lowerBound])
          + chipPrefix
          + String(display.text[chip.lowerBound...])
      case .lineBreak:
        return "\n"
      }
    }.joined()
  }

  @Test func theLegacyPathBuildsToo() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc2119(), style: style)
    #expect(built.text.length > 0)
    #expect(!built.anchors.entries.isEmpty)
  }

  /// The abstract introduces the document rather than being part of it, so it is
  /// set smaller and quieter than the body prose that follows.
  @Test func theAbstractIsSetAsAStandfirst() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
    let abstract = try #require(
      try Fixtures.rfc8999().header.abstract.compactMap { block -> String? in
        guard case .paragraph(let paragraph) = block else { return nil }
        return paragraph.plainText
      }.first)
    let abstractOffset = try Fixtures.offset(of: abstract, in: built.text)
    let bodyOffset = try Fixtures.offset(
      of: "QUIC is a connection-oriented protocol", in: built.text)

    let abstractFont = try #require(
      built.text.attribute(.font, at: abstractOffset, effectiveRange: nil) as? PlatformFont)
    let bodyFont = try #require(
      built.text.attribute(.font, at: bodyOffset, effectiveRange: nil) as? PlatformFont)
    #expect(abstractFont.pointSize < bodyFont.pointSize)

    let abstractColour =
      built.text.attribute(.foregroundColor, at: abstractOffset, effectiveRange: nil)
      as? PlatformColor
    #expect(abstractColour == RFCColors.secondaryLabel)
    #expect(
      built.text.attribute(.foregroundColor, at: bodyOffset, effectiveRange: nil) as? PlatformColor
        == RFCColors.label)
  }

  /// The heading stays a heading: full size, anchored, and in the rotor.
  @Test func theAbstractHeadingIsNotDimmed() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
    let offset = try Fixtures.offset(of: "Abstract", in: built.text)
    #expect(
      built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
        == style.headingFont(depth: 1))
    #expect(
      built.text.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? PlatformColor
        == RFCColors.label)
  }

  /// The bibliography leaves the body entirely — heading and all, so no empty
  /// "9. References" is left behind where the rows used to be.
  @Test func theBibliographyIsNotInTheBody() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)
    let skipped = document.allSections.filter { DocumentTextBuilder.holdsOnlyReferences($0) }
    #expect(!skipped.isEmpty, "RFC 8999 has a references section to skip")
    for section in skipped {
      #expect(
        !built.text.string.contains(section.displayTitle),
        "\(section.displayTitle) belongs in the panel")
      #expect(built.anchors.offset(of: section.anchor) == nil)
    }
  }

  /// A section that merely *contains* references alongside prose is still prose.
  @Test func onlyAPureBibliographySectionIsSkipped() {
    let entry = Reference(anchor: "RFC2119", title: "Key words")
    let pure = Section(
      anchor: "s1", title: "References",
      blocks: [.references(ReferenceList(title: "References", entries: [entry]))])
    let mixed = Section(
      anchor: "s2",
      title: "Notes",
      blocks: [
        .paragraph(Paragraph(text: "prose")),
        .references(ReferenceList(title: "Notes", entries: [entry])),
      ]
    )
    let parent = Section(anchor: "s3", title: "References", subsections: [pure])
    let empty = Section(anchor: "s4", title: "Placeholder")

    #expect(DocumentTextBuilder.holdsOnlyReferences(pure))
    #expect(!DocumentTextBuilder.holdsOnlyReferences(mixed))
    #expect(
      DocumentTextBuilder.holdsOnlyReferences(parent),
      "a parent of bibliography subsections goes too")
    #expect(
      !DocumentTextBuilder.holdsOnlyReferences(empty), "an empty section is not a bibliography")
  }
}
