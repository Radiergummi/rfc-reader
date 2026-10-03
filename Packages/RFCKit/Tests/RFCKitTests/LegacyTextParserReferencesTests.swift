import Foundation
import Testing

@testable import RFCKit

/// References sections: their entries, and what each names.
@Suite("Legacy text parser: references")
struct LegacyTextParserReferencesTests {
  @Test func `references and links`() throws {
    let document = try Fixtures.document("rfc5234.txt")
    let informative = try #require(document.section(number: "6.2"))
    let list = try #require(informative.blocks.first?.references, "expected reference list")
    #expect(list.entries.map(\.anchor) == ["RFC733", "RFC822"])
    #expect(list.entries[1].documentID == .rfc(822))
    #expect(list.entries[1].title == "Standard for the format of ARPA Internet text messages")
    #expect(list.entries[1].date == PublicationDate(year: 1982, month: 8))
    #expect(list.entries[1].seriesInfo.contains { $0.name == "STD" && $0.value == "11" })

    // [US-ASCII] in prose links to the reference entry; RFC mentions link to documents.
    let terminals = try #require(document.section(number: "2.3"))
    let xrefs = terminals.blocks.flatMap { block -> [CrossReference] in
      guard case .paragraph(let paragraph) = block else { return [] }
      return paragraph.inlines.compactMap(\.crossReference)
    }
    #expect(xrefs.contains { $0.target == .anchor("US-ASCII") && $0.text == "[US-ASCII]" })
    #expect(document.referencedDocuments.contains(.rfc(822)))
  }

  /// An entry's title is its words, as reading it back from the XML gives, not the line
  /// breaks and spaces inside the quotes; and an entry with no text has no raw text
  /// either, rather than an empty one (#683).
  @Test func `an entry's title is collapsed, and an empty entry has no raw text`() {
    let spaced = LegacyTextParser.reference(
      anchor: "EXAMPLE", text: "Writer, A., \" A   Spaced Title \", March 1990.")
    #expect(spaced.title == "A Spaced Title")
    #expect(LegacyTextParser.reference(anchor: "EMPTY", text: "").rawText == nil)
  }

  /// The reference list sets its anchors the way the prose cites them, and a
  /// seventh of the corpus puts a space in: `[RFC 1034]`. `referenceStartPattern`
  /// admitted no whitespace in an anchor, so those lines started no entry and were
  /// swallowed as continuation text of whatever came before -- RFC 2290 and RFC
  /// 2535 produced no bibliography at all. 782 entries across 205 documents.
  @Test func `reference anchors may hold spaces`() throws {
    let document = try Fixtures.document("rfc2606.txt")
    let lists = document.referenceLists
    let list = try #require(lists.first, "the bibliography is lost entirely without this")
    #expect(list.entries.map(\.displayAnchor) == ["RFC 1034", "RFC 1035", "RFC 1591"])
    #expect(
      list.entries.map(\.anchor) == ["RFC1034", "RFC1035", "RFC1591"],
      "the anchor has to be an XML name")
    #expect(list.entries[0].documentID == .rfc(1034))
    // And the prose citation finds the entry it names, spaces and all.
    #expect(document.referencedDocuments.contains(.rfc(1034)))
  }

  /// A references entry may put its label alone on a line and its text on the lines
  /// under it, as RFC 2049 does, the label spelled `RFC-822` (September 2026's first
  /// full corpus run).
  @Test func `a label alone on its line opens an entry`() throws {
    let document = try Fixtures.document("rfc2049.txt")
    let entries = document.referenceLists.flatMap(\.entries)
    let entry = try #require(entries.first { $0.anchor == "RFC-822" })
    #expect(entry.documentID == .rfc(822))
    #expect(entry.title == "Standard for the Format of ARPA Internet Text Messages")
    #expect(document.referencedDocuments.contains(.rfc(822)))
  }

  /// A numbered entry whose text names no RFC was recorded as the RFC its number
  /// happened to be: RFC 2013's `[1]` is ISO 8824, and it and its citation became RFC 1.
  /// 6,887 entries in 1,381 converted documents. `[2]`, which says RFC 1902, still is.
  @Test func `a numbered entry is not the RFC of its number`() throws {
    let document = try Fixtures.document("rfc2013.txt")
    let entries = document.referenceLists.flatMap(\.entries)
    let asn1 = try #require(entries.first { $0.displayAnchor == "1" })
    #expect(asn1.documentID == nil)
    #expect(asn1.anchor == "ref-1")
    #expect(document.crossReferences.contains { $0.target == .anchor("ref-1") && $0.text == "[1]" })
    #expect(!document.referencedDocuments.contains(.rfc(1)))
    #expect(entries.first { $0.displayAnchor == "2" }?.documentID == .rfc(1902))
  }

  /// An entry names its RFC however the document spells it. RFC 1041 writes every entry
  /// `[1] RFC-854, ...`; read as no RFC, its numbered entries named nothing at all.
  @Test func `an entry names an RFC written with a hyphen`() throws {
    let document = try Fixtures.document("rfc1041.txt")
    let entries = document.referenceLists.flatMap(\.entries)
    #expect(entries.first { $0.displayAnchor == "1" }?.documentID == .rfc(854))
    #expect(entries.first { $0.displayAnchor == "3" }?.documentID == .rfc(885))
    #expect(
      entries.first { $0.displayAnchor == "5" }?.documentID == nil, "the IBM manual names no RFC")
    #expect(document.referencedDocuments.contains(.rfc(856)))

    // But a title names RFCs too, and the hyphenated spelling is only the fallback:
    // RFC 1494's `[1]` is "Mapping between X.400 and RFC-822 Message Bodies", RFC 1495.
    let mapping = try Fixtures.document("rfc1494.txt").referenceLists.flatMap(
      \.entries)
    #expect(mapping.first { $0.displayAnchor == "1" }?.documentID == .rfc(1495))
  }

  /// And in the series' earliest spellings: RFC 338 cites `RFC #189` and `RFC #183`,
  /// RFC 1275 `Request for Comments 1006`, RFC 1005 `Request For Comments 990`, broken
  /// across a line.
  @Test func `an entry names an RFC in the series earliest spellings`() throws {
    let rfc338 = try Fixtures.document("rfc338.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc338.first { $0.displayAnchor == "1" }?.documentID == .rfc(189))
    #expect(rfc338.first { $0.displayAnchor == "4" }?.documentID == .rfc(183))
    #expect(rfc338.first { $0.displayAnchor == "2" }?.documentID == nil, "a note names no RFC")

    let rfc1275 = try Fixtures.document("rfc1275.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc1275.first { $0.displayAnchor == "RC87" }?.documentID == .rfc(1006))

    let rfc1005 = try Fixtures.document("rfc1005.txt").referenceLists.flatMap(
      \.entries)
    #expect(rfc1005.first { $0.displayAnchor == "3" }?.documentID == .rfc(990))
    #expect(rfc1005.first { $0.displayAnchor == "5" }?.documentID == .rfc(796))
  }

  /// A label listed twice is cited as its first entry, whether that names a document or
  /// not: RFC 2023 lists RFCs 1883 and 1884 both as `[2]`.
  @Test func `a repeated label is cited as its first entry`() throws {
    let document = try Fixtures.document("rfc2023.txt")
    let cited = document.everyCrossReference.filter { $0.text == "[2]" || $0.label == "[2]" }.map(
      \.target)
    #expect(!cited.isEmpty)
    #expect(
      cited.allSatisfy { $0 == .document(.rfc(1883), section: nil, entry: "RFC1883") }, "\(cited)")
  }

  @Test func `a references heading names references as a word`() {
    for title in [
      "References", "REFERENCES", "Normative References", "References:",
      "Acknowledgments and References", "References and Bibliography",
    ] {
      #expect(LegacyTextParser.isReferencesTitle(title), "\(title)")
    }
    for title in [
      "Router Preferences", "Priority for Domain Preferences", "Conferences",
      "Example Message (Headers, Body, and References)",
    ] {
      #expect(!LegacyTextParser.isReferencesTitle(title), "\(title)")
    }
  }

  /// A plain references title is a bibliography whatever the parser finds in it; a
  /// title that only mentions references -- a style guide's section on writing one, a
  /// protocol's object references -- is one only when its entries outnumber the blocks
  /// before them, or its prose is read as one entry's text (#686).
  @Test func `a title that mentions references is a bibliography only by its entries`() {
    for title in ["References", "Normative References", "INFORMATIVE REFERENCES:", "References."] {
      #expect(
        LegacyTextParser.isBibliography(title: title, entries: 1, blocksBefore: 4), "\(title)")
    }
    for title in [
      "Writing the References Section", "Following Object References in Replies",
      "Remote References",
    ] {
      #expect(
        !LegacyTextParser.isBibliography(title: title, entries: 1, blocksBefore: 1), "\(title)")
      #expect(
        LegacyTextParser.isBibliography(title: title, entries: 3, blocksBefore: 1), "\(title)")
    }
  }

  /// A references section's own text before its first entry, in the shape of a
  /// bibliography's opening note: kept as its own blocks, split from the entry's
  /// block where the entry starts inside it.
  @Test func `what precedes a references section's first entry is its own`() {
    let note = LegacyTextParser.RawBlock(lines: [
      "   The documents below are listed for background only."
    ])
    let entries = LegacyTextParser.RawBlock(lines: [
      "   Documents marked with a star are drafts.",
      "   [ONE]  Someone, \"A Title\", May 1990.",
      "   [TWO]  Someone Else, \"Another Title\", June 1991.",
    ])
    let leading = LegacyTextParser.blocksBeforeFirstEntry([note, entries])
    #expect(leading.map(\.lines) == [note.lines, ["   Documents marked with a star are drafts."]])
    #expect(
      LegacyTextParser.parseReferences([note, entries]).map(\.displayAnchor) == ["ONE", "TWO"])
    #expect(LegacyTextParser.blocksBeforeFirstEntry([entries]).map(\.lines) == [[entries.lines[0]]])
  }

  /// An entry's document is the one its own series info or label names, never an RFC
  /// its title mentions: an entry whose title is about RFC 2119's keywords resolved to
  /// RFC 2119, and its citations became chips for RFC 2119 that linked there (#424).
  @Test func `an entry is not the RFC its title names`() {
    let entries = LegacyTextParser.parseReferences([
      LegacyTextParser.RawBlock(lines: [
        "   [RFC9990]  Someone, A., \"Revisiting the Keywords of RFC 2119\",",
        "              BCP 14, RFC 9990, May 2031.",
        "   [4]        Someone, B., \"Notes on RFC 822 Headers\", RFC 9991,",
        "              June 2031.",
        "   [5]        Someone, C., \"Replacing RFC 1234 and BCP 12\", Work in",
        "              Progress, July 2031.",
      ])
    ])
    #expect(entries.map(\.documentID) == [.rfc(9990), .rfc(9991), nil])
    #expect(entries[0].seriesInfo.contains(SeriesInfo(name: "BCP", value: "14")))
    #expect(
      !entries[2].seriesInfo.contains { $0.name == "BCP" }, "the title's BCP is not the entry's")
  }

  private static func bibliography(_ number: String, _ anchors: [String]) -> Section {
    Section(
      anchor: "section-\(number)", number: number, title: "References \(number)",
      blocks: [
        .references(
          ReferenceList(
            title: "References", entries: anchors.map { Reference(anchor: $0, title: $0) }))
      ])
  }

  private static func prose(_ number: String) -> Section {
    Section(
      anchor: "section-\(number)", number: number, title: "Section \(number)",
      blocks: [.paragraph(Paragraph([.text("Text of \(number).")]))])
  }

  private static func outline(_ sections: [Section]) -> [String] {
    sections.flatMap { section in
      [section.number ?? "-"] + outline(section.subsections).map { "  \($0)" }
    }
  }

  /// `<references>` holds bibliographies and nothing else, so a section numbered under
  /// one lost its text in the XML (#686): an appendix whose own heading was missing,
  /// `A.1` after `9 References`, or the authors' addresses numbered under it. Such a
  /// subsection, and those after it, follow the bibliography instead; a bibliography
  /// before them stays under it.
  @Test func `a bibliography adopts no section that is not one`() {
    let appendix = LegacyTextParser.nest([
      Self.prose("8"), Self.bibliography("9", ["ONE"]), Self.prose("A.1"), Self.prose("A.1.1"),
      Self.prose("A.2"),
    ])
    #expect(Self.outline(appendix) == ["8", "9", "A.1", "  A.1.1", "A.2"])

    let addresses = LegacyTextParser.nest([
      Self.bibliography("4", ["ONE"]), Self.bibliography("4.1", ["TWO"]), Self.prose("4.2"),
      Self.prose("5"),
    ])
    #expect(Self.outline(addresses) == ["4", "  4.1", "4.2", "5"])

    let nested = LegacyTextParser.nest([
      Self.prose("6"), Self.bibliography("6.1", ["ONE"]), Self.prose("6.1.1"), Self.prose("6.2"),
    ])
    #expect(Self.outline(nested) == ["6", "  6.1", "  6.1.1", "  6.2"])
  }

  /// A references section with no entries of its own only groups its lists, and is
  /// written as a section when anything else is numbered under it, so it keeps that.
  @Test func `a section that only groups bibliographies keeps its subsections`() {
    let grouping = Section(anchor: "section-10", number: "10", title: "References")
    let sections = LegacyTextParser.nest([
      grouping, Self.bibliography("10.1", ["ONE"]), Self.bibliography("10.2", ["TWO"]),
      Self.prose("10.3"),
    ])
    #expect(Self.outline(sections) == ["10", "  10.1", "  10.2", "  10.3"])
  }
}
