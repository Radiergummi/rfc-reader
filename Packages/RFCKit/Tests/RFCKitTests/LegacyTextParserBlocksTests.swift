import Foundation
import Testing

@testable import RFCKit

/// Blocks: prose against artwork, lists, catalogues, and paragraphs across pages.
@Suite("Legacy text parser: blocks")
struct LegacyTextParserBlocksTests {
  @Test func `paragraphs split across pages are rejoined`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
    let discussion = try #require(document.sections.first { $0.titleText == "Discussion" })
    let paragraphs = discussion.blocks.compactMap(\.paragraph?.plainText)
    #expect(paragraphs.count == 1)
    #expect(
      paragraphs[0].contains("the carriers are self-regenerating."),
      "hyphenated word rejoined across the page break")
    #expect(paragraphs[0].hasSuffix("cable trays."))
  }

  @Test func `prose versus artwork`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let terminals = try #require(document.section(number: "2.3"))
    var paragraphs: [String] = []
    var artworks: [String] = []
    for block in terminals.blocks {
      switch block {
      case .paragraph(let paragraph):
        paragraphs.append(paragraph.plainText)
        #expect(!paragraph.plainText.contains("  "), "prose is reflowed: \(paragraph.plainText)")
      case .preformatted(let artwork):
        artworks.append(artwork.text)
      default:
        break
      }
    }
    #expect(paragraphs.first?.hasPrefix("Rules resolve into a string of terminal values") == true)
    #expect(artworks.contains { $0.contains("=  binary") })
    #expect(
      artworks.contains { $0.contains("CR          =  %d13") },
      "column alignment inside artwork is preserved")

    let grammar = try #require(document.section(number: "4"))
    let artwork = grammar.blocks.compactMap(\.preformatted)
    #expect(artwork.contains { $0.text.contains("rulelist       =  1*( rule / (*c-wsp c-nl) )") })
  }

  @Test func `lists are detected`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let grammar = try #require(document.section(number: "4"))
    let lists = grammar.blocks.compactMap(\.list)
    #expect(lists.count == 1)
    #expect(lists[0].items.count == 2)
    if case .paragraph(let paragraph)? = lists[0].items[1].blocks.first {
      #expect(paragraph.plainText == "This syntax uses the rules provided in Appendix B.")
    } else {
      Issue.record("list item should contain a paragraph")
    }
  }

  /// A hanging list whose items carry continuation paragraphs -- the shape RFC 3712
  /// sets its Introduction in, and the reason `[RFC3066]` sat unlinked there. Each
  /// paragraph arrives as its own block, indented past the marker and carrying no
  /// marker of its own, so it used to fail the prose test's indent guard and be
  /// preserved as artwork. Artwork is never linkified, and the list was shredded
  /// into one single-item list per item.
  @Test func `list continuation paragraphs stay prose`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc234.txt"))
    let lists = document.lists
    let carrying = try #require(
      lists.first { $0.items.contains { $0.blocks.count > 1 } },
      "an item's second paragraph belongs to the item")
    let item = try #require(carrying.items.first { $0.blocks.count > 1 })
    #expect(
      item.blocks.allSatisfy {
        if case .paragraph = $0 { return true }
        return false
      },
      "the continuation is prose, not artwork")
    let continuation = try #require(item.blocks.dropFirst().first)
    guard case .paragraph(let paragraph) = continuation else {
      Issue.record("expected a paragraph")
      return
    }
    #expect(paragraph.plainText.contains("Commences at"))
  }

  /// A catalogue entry is a number, a dash and the entry, with anything further hung
  /// past the number (#204): the RFC index of RFC 1012, the standards summaries'
  /// `2352 - A Convention ...`, numbered steps, value tables. The lines here are
  /// written in that shape, not quoted.
  @Test func `a numbered catalogue entry is split into its number and its text`() throws {
    let one = try #require(
      LegacyTextParser.catalogueEntries([
        "   7   - Someone, A., \"A Title\", RFC 7 (NIC 101),",
        "         Somewhere, 1 April 1969.",
      ]))
    #expect(one.map(\.term) == ["7"])
    #expect(
      one.first?.text == "Someone, A., \"A Title\", RFC 7 (NIC 101), Somewhere, 1 April 1969.")

    let two = try #require(
      LegacyTextParser.catalogueEntries([
        "      0 - Reserved",
        "      1 - First Value",
      ]))
    #expect(two.map(\.term) == ["0", "1"])
    #expect(two.map(\.text) == ["Reserved", "First Value"])
  }

  @Test func `lines that only look like catalogue entries are not`() {
    // Arithmetic, not an entry.
    #expect(LegacyTextParser.catalogueEntries(["   3 - 2 leaves one"]) == nil)
    // A continuation must hang past the number.
    #expect(LegacyTextParser.catalogueEntries(["   1 - Title", "back at the margin"]) == nil)
    // Nothing after the dash.
    #expect(LegacyTextParser.catalogueEntries(["   1 -"]) == nil)
    // Prose that mentions a number and a dash.
    #expect(LegacyTextParser.catalogueEntries(["   The value 1 - the default - is kept."]) == nil)
    // Entries at two different indents.
    #expect(LegacyTextParser.catalogueEntries(["   1 - One", "      2 - Two"]) == nil)
    // A table with a column of its own after the name: joining it would run the
    // columns together into one sentence.
    #expect(
      LegacyTextParser.catalogueEntries([
        "      1 - query      A request for the whole table.",
        "      2 - answer     The table itself.",
      ]) == nil)
  }

  @Test func `a lettered catalogue number keeps its letter`() {
    #expect(LegacyTextParser.catalogueEntries(["   17a - Amended Entry"])?.first?.term == "17a")
  }

  /// A formula set on a line of its own opens with a number and a minus too.
  @Test func `a formula is not a catalogue entry`() {
    #expect(LegacyTextParser.catalogueEntries(["   1 - (1 - a / b) ^ 2 == c"]) == nil)
    #expect(LegacyTextParser.catalogueEntries(["   1 - (a + b) == c"]) == nil)
    // A parenthesis alone is no formula: a reserved value is written that way.
    #expect(
      LegacyTextParser.catalogueEntries(["      0 - (reserved)"])?.first?.text == "(reserved)")
  }

  /// Two values on one line: the second is not the first one's text.
  @Test func `two entries on one line are not a catalogue`() {
    #expect(LegacyTextParser.catalogueEntries(["   1 - FIRST, 2 - SECOND"]) == nil)
  }

  /// After a colon, spaces align the descriptions of a name and its description,
  /// however many there are; after a word they are a column of their own.
  @Test func `a gap after a colon is not a column in a catalogue`() {
    #expect(LegacyTextParser.catalogueEntries(["      3 - STOPPING:   It is stopping."]) != nil)
    #expect(LegacyTextParser.catalogueEntries(["      3 - STOPPING:      It is stopping."]) != nil)
    #expect(LegacyTextParser.catalogueEntries(["      3 - stopping   It is stopping."]) == nil)
  }

  /// Where an entry's text starts: the column a description under it stands in.
  @Test func `a catalogue entry's text column is past its number and dash`() {
    #expect(LegacyTextParser.catalogueTextColumn(of: "   7   - Someone") == 9)
    #expect(LegacyTextParser.catalogueTextColumn(of: "      2349 - A Title") == 13)
    #expect(LegacyTextParser.catalogueTextColumn(of: "not an entry") == nil)
  }

  /// A description stands at the entry's text column, give or take a column; a
  /// caption centred under a legend stands far past it, and is not the last entry's
  /// second paragraph.
  @Test func `a continuation stands at the entry's text column, not past it`() {
    let description = ["             A Short Title In Title Case."]
    #expect(
      LegacyTextParser.continuesCatalogueEntry(description, numberIndent: 6, textColumn: 13))
    let nearly = ["           A description set two columns short."]
    #expect(LegacyTextParser.continuesCatalogueEntry(nearly, numberIndent: 6, textColumn: 13))
    let caption = ["                          Figure 9."]
    #expect(!LegacyTextParser.continuesCatalogueEntry(caption, numberIndent: 8, textColumn: 12))
    // At the number or before it is a new paragraph, not a continuation.
    let atNumber = ["      Back at the number."]
    #expect(!LegacyTextParser.continuesCatalogueEntry(atNumber, numberIndent: 6, textColumn: 13))
  }

  /// RFC 757 is typeset justified: every line is padded with extra spaces between words
  /// to reach a common right margin. Those runs of spaces are what tells prose from
  /// artwork everywhere else, so all 60-odd of its paragraphs were preformatted blocks.
  @Test func `justified prose is not artwork`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc757.txt"))
    #expect(
      document.header.title
        == "A Suggested Solution to the Naming, Addressing, and Delivery Problem for ARPAnet Message Systems"
    )

    var paragraphs = 0
    var artwork = 0
    for block in document.everyBlock {
      switch block {
      case .paragraph: paragraphs += 1
      case .preformatted: artwork += 1
      default: break
      }
    }
    // What is left as artwork is genuine: diagrams, and the paragraphs whose footnote
    // markers sit on a line of their own.
    #expect(paragraphs > artwork, "got \(paragraphs) paragraphs against \(artwork) artwork blocks")

    // The padding is collapsed on reflow, so the text reads normally.
    let introduction = try #require(document.section(number: "1"))
    guard case .paragraph(let first)? = introduction.blocks.first else {
      Issue.record("expected the introduction to start with a paragraph")
      return
    }
    #expect(
      first.plainText
        // swiftlint:disable:next line_length - one reflowed paragraph, asserted whole
        == "The current ARPAnet message handling scheme has evolved from rather informal, decentralized beginnings. Early developers took advantage of pre-existing tools -- TECO, FTP -- in order to implement their first systems. Later, protocols were developed to codify the conventions already in use. While these conventions have been able to support an amazing variety and amount of service, they have a number of shortcomings."
    )
  }

  /// The prose cap was six columns everywhere: a body at column 3, plus three. RFC 1178
  /// sets its headings at 6 and its body at 9, so every paragraph it has failed the cap
  /// and was kept as artwork, and none of it was linked (#55). The cap follows the
  /// body now, and a body at column 3 keeps the classic one.
  @Test func `a body set deeper than column three is still prose`() {
    let paragraph = [
      "         Using a word that has strong semantic implications in the",
      "         current context will cause confusion.  This is especially true",
      "         in conversation where punctuation is not obvious and grammar is",
      "         often incorrect.",
    ]
    let deeper = (["      Don't overload other terms already in common use.", ""] + paragraph)
      .map(LegacyTextParser.Line.text)
    let cap = LegacyTextParser.proseIndent(deeper)
    #expect(cap == 9)
    #expect(LegacyTextParser.diagnose(paragraph, maxIndent: cap).isProse)

    let classic = [
      "   As soon as you deal with more than one computer, you need to",
      "   distinguish between them.  For example, to tell your system",
      "   administrator that your computer is busted, you might say, \"Hey Ken.",
    ].map(LegacyTextParser.Line.text)
    #expect(LegacyTextParser.proseIndent(classic) == LegacyTextParser.classicProseIndent)
  }

  /// A paragraph cut by a page break is rejoined when the next page opens lower case,
  /// as the rest of a sentence does. An `o` bullet opens lower case too: RFC 1581's
  /// `it is assumed that:` ends a page, the list under it starts the next, and its
  /// first item was read into the sentence as `that: o The most recently ...`.
  @Test func `a bullet at the top of a page is not the rest of a sentence`() {
    let endOfPage = LegacyTextParser.RawBlock(lines: [
      "   In a stable network there is no requirement to propagate routing",
      "   information on a circuit, so if no routing information is (being)",
      "   received on a circuit it is assumed that:",
    ])
    let bullet = LegacyTextParser.RawBlock(lines: [
      "   o  The most recently received information is accurate."
    ])
    #expect(!LegacyTextParser.shouldJoinAcrossPage(endOfPage, bullet, proseIndent: 6))

    let restOfSentence = LegacyTextParser.RawBlock(lines: [
      "   operational routing information previously received on that circuit"
    ])
    #expect(LegacyTextParser.shouldJoinAcrossPage(endOfPage, restOfSentence, proseIndent: 6))
  }

  /// Nor is it the rest of a sentence when the line above it has no final punctuation,
  /// which is the other reason a page join is made: RFC 6614's `For example, they send`
  /// ends a page, and its list of packet types, which starts the next, was read into it
  /// as `they send o Access-Request o Accounting-Request ...`.
  @Test func `a bullet after an unfinished sentence is not its rest`() {
    let endOfPage = LegacyTextParser.RawBlock(lines: [
      "   RADIUS/TLS clients transmit the same packet types on the connection",
      "   they initiated as a RADIUS/UDP client would (see Section 3.4 (3) and",
      "   (4)).  For example, they send",
    ])
    let bullet = LegacyTextParser.RawBlock(lines: ["   o  Access-Request"])
    #expect(!LegacyTextParser.shouldJoinAcrossPage(endOfPage, bullet, proseIndent: 6))

    let restOfSentence = LegacyTextParser.RawBlock(lines: [
      "   Access-Request, Accounting-Request and Status-Server packets."
    ])
    #expect(LegacyTextParser.shouldJoinAcrossPage(endOfPage, restOfSentence, proseIndent: 6))
  }
}
