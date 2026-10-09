import Foundation
import Testing

@testable import RFCKit

/// An appendix's `(Normative)` or `(Informative)`, taken out of its title by both
/// parsers and written back by the serializer (#428). Guard-level, over hand-written
/// titles in the shape of a heading.
@Suite("Heading qualifiers")
struct HeadingQualifierTests {
  @Test(arguments: [
    ("(Normative) Definitions", Section.Qualifier.normative, "Definitions"),
    ("(informative): Background", .informative, "Background"),
    ("(INFORMATIVE) - Background", .informative, "Background"),
    ("(Normative)", .normative, ""),
  ])
  func `a leading qualifier is taken out`(
    title: String, qualifier: Section.Qualifier, rest: String
  ) {
    let split = HeadingQualifier.split(title)
    #expect(split.qualifier == qualifier)
    #expect(split.title == rest)
  }

  /// Only a qualifier in parentheses at the start is one: a title that mentions the
  /// word is a title.
  @Test(arguments: [
    "Normative References", "Informative Notes (Normative)", "Background (informative)",
    "(Normally) Empty",
  ])
  func `anything else is left alone`(title: String) {
    let split = HeadingQualifier.split(title)
    #expect(split.qualifier == nil)
    #expect(split.title == title)
  }

  /// In inlines, the qualifier is in the first run of text, and a link after it stays.
  @Test func `a qualifier is taken out of a heading's inlines`() {
    let link = Inline.crossReference(
      CrossReference(target: .document(.rfc(9000), section: nil)))
    let split = HeadingQualifier.split([.text("(Informative) Notes on "), link])
    #expect(split.qualifier == .informative)
    #expect(split.title == [.text("Notes on "), link])
  }

  /// An annex's part number is an appendix's with its word, and reads back as one.
  @Test func `an annex's part number reads back as an annex`() {
    let annex = PartNumber(sectionNumber: "B.1", isAppendix: true, word: .annex)
    #expect(annex.attribute == "section-annex.b.1")
    #expect(PartNumber("section-annex.b.1") == .annex("B.1"))
    #expect(PartNumber(sectionNumber: "B.1", isAppendix: true) == .appendix("B.1"))
  }

  /// The word and the qualifier survive the XML: the serializer writes the word into
  /// the part number and the qualifier into the name, and the parser reads both back.
  @Test func `an annex and its qualifier survive a round trip`() throws {
    let child = Section(
      anchor: "appendix-B.1", number: "B.1", title: "Details", isAppendix: true,
      appendixWord: .annex)
    let annex = Section(
      anchor: "appendix-B", number: "B", title: "Background", subsections: [child],
      isAppendix: true, appendixWord: .annex, qualifier: .informative)
    let bare = Section(
      anchor: "appendix-C", number: "C", title: "", isAppendix: true, qualifier: .normative)
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(9999), title: "Annexes"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Introduction",
          blocks: [.paragraph(Paragraph(text: "Prose."))]),
        annex, bare,
      ],
      source: .text)
    let xml = RFCXMLSerializer().serialize(document)
    #expect(xml.contains(#"pn="section-annex.b""#))
    #expect(xml.contains("<name>(Informative) Background</name>"))
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    let readAnnex = try #require(reparsed.section(anchor: "appendix-B"))
    #expect(readAnnex.appendixWord == .annex)
    #expect(readAnnex.qualifier == .informative)
    #expect(readAnnex.titleText == "Background")
    #expect(readAnnex.subsections.first?.appendixWord == .annex)
    let readBare = try #require(reparsed.section(anchor: "appendix-C"))
    #expect(readBare.qualifier == .normative)
    #expect(readBare.titleText == "")
    #expect(readBare.displayTitle == "Appendix C. (Normative)")
  }

  /// A heading reads with its qualifier wherever it is shown: the reader, a PDF, the
  /// contents list. Only the title, the words the document gave the appendix, is
  /// without it.
  @Test func `a heading reads with its qualifier`() {
    let annex = Section(
      anchor: "appendix-B", number: "B", title: "Background", isAppendix: true,
      appendixWord: .annex, qualifier: .informative)
    #expect(annex.displayTitle == "Annex B. (Informative) Background")
    #expect(annex.titleText == "Background")
    #expect(annex.headingWords == [.text("(Informative) "), .text("Background")])
  }

  /// An annex that is a bibliography keeps its word and its qualifier through the XML,
  /// as any annex does, and its paragraphs count from its own part number.
  @Test func `a bibliography annex survives a round trip`() throws {
    let references = Section(
      anchor: "appendix-C", number: "C", title: "Bibliography",
      blocks: [
        .references(
          ReferenceList(
            title: "Bibliography",
            entries: [
              Reference(anchor: "one", title: "One")
            ]))
      ],
      isAppendix: true, appendixWord: .annex, qualifier: .informative)
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(9999), title: "Annexes"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Introduction",
          blocks: [.paragraph(Paragraph(text: "Prose."))]),
        references,
      ],
      source: .text)
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    let read = try #require(reparsed.section(anchor: "appendix-C"))
    #expect(read.appendixWord == .annex)
    #expect(read.qualifier == .informative)
    #expect(read.titleText == "Bibliography")
  }

  /// An annex's paragraphs count from the part number it is written with.
  @Test func `an annex's paragraphs count from its part number`() throws {
    let annex = Section(
      anchor: "appendix-B", number: "B", title: "Background",
      blocks: [.paragraph(Paragraph(text: "Prose."))], isAppendix: true, appendixWord: .annex)
    let numbered = LegacyTextParser.numberingParagraphs([annex], avoiding: [])
    guard case .paragraph(let paragraph)? = numbered.first?.blocks.first else {
      Issue.record("no paragraph")
      return
    }
    #expect(paragraph.anchor?.hasPrefix("section-annex.b-") == true)
  }
}
