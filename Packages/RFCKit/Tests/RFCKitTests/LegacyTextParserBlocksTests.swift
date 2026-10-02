import Foundation
import Testing

@testable import RFCKit

/// Blocks: prose against artwork, lists, catalogs, and paragraphs across pages.
@Suite("Legacy text parser: blocks")
struct LegacyTextParserBlocksTests {
  @Test func `paragraphs split across pages are rejoined`() throws {
    let document = try Fixtures.document("rfc1149.txt")
    let discussion = try #require(document.sections.first { $0.titleText == "Discussion" })
    let paragraphs = discussion.blocks.compactMap(\.paragraph?.plainText)
    #expect(paragraphs.count == 1)
    #expect(
      paragraphs[0].contains("self-regenerating"),
      "hyphenated word rejoined across the page break")
    #expect(paragraphs[0].hasSuffix("cable trays."))
  }

  @Test func `prose versus artwork`() throws {
    let document = try Fixtures.document("rfc5234.txt")
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
    #expect(paragraphs.first?.hasPrefix("Rules resolve") == true)
    #expect(artworks.contains { $0.contains("=  binary") })
    #expect(
      artworks.contains { $0.contains("CR          =  %d13") },
      "column alignment inside artwork is preserved")

    let grammar = try #require(document.section(number: "4"))
    let artwork = grammar.blocks.compactMap(\.preformatted)
    #expect(artwork.contains { $0.text.contains("rulelist       =  1*( rule / (*c-wsp c-nl) )") })
  }

  @Test func `lists are detected`() throws {
    let document = try Fixtures.document("rfc5234.txt")
    let grammar = try #require(document.section(number: "4"))
    let lists = grammar.blocks.compactMap(\.list)
    #expect(lists.count == 1)
    #expect(lists[0].items.count == 2)
    if case .paragraph(let paragraph)? = lists[0].items[1].blocks.first {
      #expect(paragraph.plainText.hasPrefix("This syntax"))
      #expect(paragraph.plainText.hasSuffix("Appendix B."))
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
    let document = try Fixtures.document("rfc234.txt")
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
    let paragraph = try #require(continuation.paragraph, "expected a paragraph")
    #expect(paragraph.plainText.contains("Commences at"))
  }

  /// A catalog entry is a number, a dash and the entry, with anything further hung
  /// past the number (#204): the RFC index of RFC 1012, the standards summaries'
  /// `2352 - A Convention ...`, numbered steps, value tables. The lines here are
  /// written in that shape, not quoted.
  @Test func `a numbered catalog entry is split into its number and its text`() throws {
    let one = try #require(
      LegacyTextParser.catalogEntries([
        "   7   - Someone, A., \"A Title\", RFC 7 (NIC 101),",
        "         Somewhere, 1 April 1969.",
      ]))
    #expect(one.map(\.term) == ["7"])
    #expect(
      one.first?.text == "Someone, A., \"A Title\", RFC 7 (NIC 101), Somewhere, 1 April 1969.")

    let two = try #require(
      LegacyTextParser.catalogEntries([
        "      0 - Reserved",
        "      1 - First Value",
      ]))
    #expect(two.map(\.term) == ["0", "1"])
    #expect(two.map(\.text) == ["Reserved", "First Value"])
  }

  /// A catalog is set as the document sets it, each number beside its text and no
  /// space between the entries; a hanging-indent definition keeps its term on a line
  /// of its own, as every definition list was set before (#352).
  @Test func `a catalog is compact and hangs its numbers, a hanging definition does not`() throws {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let catalog = LegacyTextParser.RawBlock(lines: [
      "      0 - Reserved",
      "      1 - First Value",
    ])
    let catalogList = try #require(
      LegacyTextParser.blocks(from: [catalog], proseIndent: 6, linker: linker).first?
        .definitionList)
    #expect(catalogList.items.map(\.term.plainText) == ["0", "1"])
    #expect(catalogList.isCompact)
    #expect(catalogList.hangsTerms)

    let hanging = LegacyTextParser.RawBlock(lines: [
      "   Widget:  A part that is carried over a link",
      "      from one end to the other.",
    ])
    let hangingList = try #require(
      LegacyTextParser.blocks(from: [hanging], proseIndent: 6, linker: linker).first?
        .definitionList)
    #expect(hangingList.items.map(\.term.plainText) == ["Widget:"])
    #expect(!hangingList.isCompact)
    #expect(!hangingList.hangsTerms)
  }

  /// The same through a whole document: RFC 1540's standards summaries are catalogs,
  /// and every one of them is compact and hangs its numbers, merged entries included.
  @Test func `a document's catalogs are compact and hang their numbers`() throws {
    let document = try Fixtures.document("rfc1540.txt")
    let catalogs = document.everyBlock.compactMap(\.definitionList)
    #expect(catalogs.count > 1)
    #expect(catalogs.allSatisfy { $0.isCompact && $0.hangsTerms })
  }

  @Test func `lines that only look like catalog entries are not`() {
    // Arithmetic, not an entry.
    #expect(LegacyTextParser.catalogEntries(["   3 - 2 leaves one"]) == nil)
    // A continuation must hang past the number.
    #expect(LegacyTextParser.catalogEntries(["   1 - Title", "back at the margin"]) == nil)
    // Nothing after the dash.
    #expect(LegacyTextParser.catalogEntries(["   1 -"]) == nil)
    // Prose that mentions a number and a dash.
    #expect(LegacyTextParser.catalogEntries(["   The value 1 - the default - is kept."]) == nil)
    // Entries at two different indents.
    #expect(LegacyTextParser.catalogEntries(["   1 - One", "      2 - Two"]) == nil)
    // A table with a column of its own after the name: joining it would run the
    // columns together into one sentence.
    #expect(
      LegacyTextParser.catalogEntries([
        "      1 - query      A request for the whole table.",
        "      2 - answer     The table itself.",
      ]) == nil)
  }

  @Test func `a lettered catalog number keeps its letter`() {
    #expect(LegacyTextParser.catalogEntries(["   17a - Amended Entry"])?.first?.term == "17a")
  }

  /// A formula set on a line of its own opens with a number and a minus too.
  @Test func `a formula is not a catalog entry`() {
    #expect(LegacyTextParser.catalogEntries(["   1 - (1 - a / b) ^ 2 == c"]) == nil)
    #expect(LegacyTextParser.catalogEntries(["   1 - (a + b) == c"]) == nil)
    // A parenthesis alone is no formula: a reserved value is written that way.
    #expect(
      LegacyTextParser.catalogEntries(["      0 - (reserved)"])?.first?.text == "(reserved)")
  }

  /// Two values on one line: the second is not the first one's text.
  @Test func `two entries on one line are not a catalog`() {
    #expect(LegacyTextParser.catalogEntries(["   1 - FIRST, 2 - SECOND"]) == nil)
  }

  /// After a colon, spaces align the descriptions of a name and its description,
  /// however many there are; after a word they are a column of their own.
  @Test func `a gap after a colon is not a column in a catalog`() {
    #expect(LegacyTextParser.catalogEntries(["      3 - STOPPING:   It is stopping."]) != nil)
    #expect(LegacyTextParser.catalogEntries(["      3 - STOPPING:      It is stopping."]) != nil)
    #expect(LegacyTextParser.catalogEntries(["      3 - stopping   It is stopping."]) == nil)
  }

  /// Where an entry's text starts: the column a description under it stands in.
  @Test func `a catalog entry's text column is past its number and dash`() {
    #expect(LegacyTextParser.catalogTextColumn(of: "   7   - Someone") == 9)
    #expect(LegacyTextParser.catalogTextColumn(of: "      2349 - A Title") == 13)
    #expect(LegacyTextParser.catalogTextColumn(of: "not an entry") == nil)
  }

  /// A description stands at the entry's text column, give or take a column; a
  /// caption centered under a legend stands far past it, and is not the last entry's
  /// second paragraph.
  @Test func `a continuation stands at the entry's text column, not past it`() {
    let description = ["             A Short Title In Title Case."]
    #expect(
      LegacyTextParser.continuesCatalogEntry(description, numberIndent: 6, textColumn: 13))
    let nearly = ["           A description set two columns short."]
    #expect(LegacyTextParser.continuesCatalogEntry(nearly, numberIndent: 6, textColumn: 13))
    let caption = ["                          Figure 9."]
    #expect(!LegacyTextParser.continuesCatalogEntry(caption, numberIndent: 8, textColumn: 12))
    // At the number or before it is a new paragraph, not a continuation.
    let atNumber = ["      Back at the number."]
    #expect(!LegacyTextParser.continuesCatalogEntry(atNumber, numberIndent: 6, textColumn: 13))
  }

  /// xml2rfc sets a `<dl>` entry as its term, two spaces and the definition, with
  /// the rest of the definition hung three columns in (#436). The lines here are
  /// written in that shape, not quoted.
  @Test func `a hanging-indent definition is split into its term and its text`() throws {
    let entry = try #require(
      LegacyTextParser.hangingDefinitions([
        "   Widget:  A part that is set on the term's line and",
        "      goes on under it, three columns in.",
      ]))
    #expect(entry.indent == 3)
    #expect(entry.continuationColumn == 6)
    #expect(entry.entries.map(\.term) == ["Widget:"])
    #expect(
      entry.entries.map(\.text) == [
        "A part that is set on the term's line and goes on under it, three columns in."
      ])
  }

  /// A term short enough for the hang sets its definition in the hang's column, and
  /// the lines under it stand there too; with no blank line between them, several
  /// entries arrive as one block.
  @Test func `aligned and compact hanging definitions are split per term`() throws {
    let aligned = try #require(
      LegacyTextParser.hangingDefinitions([
        "   Gadget Name:  A part whose text keeps to its",
        "                 own column under the term.",
        "   Other Name:   Another part, the same column.",
      ]))
    #expect(aligned.continuationColumn == 17)
    #expect(aligned.entries.map(\.term) == ["Gadget Name:", "Other Name:"])
    #expect(aligned.entries.last?.text == "Another part, the same column.")

    let oneLine = try #require(LegacyTextParser.hangingDefinitions(["   Short:  One line only."]))
    #expect(oneLine.continuationColumn == nil)
    #expect(oneLine.entries.map(\.term) == ["Short:"])
    // A one-line entry need not read as words; one that hangs does.
    #expect(LegacyTextParser.hangingDefinitions(["   Field Name:  VALUE"]) != nil)
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Maintainer:  J. Doe",
        "      <mailto:jdoe@example.org>",
      ]) == nil)
  }

  /// A definition's next paragraph stands in the column its lines hang in; an
  /// example set a column or two past it is the definition's artwork, and a line
  /// back at the terms is not under the definition at all.
  @Test func `a definition's next paragraph stands in its column, exactly`() {
    let paragraph = ["      A second paragraph of the same", "      definition, in its column."]
    #expect(LegacyTextParser.continuesHangingDefinition(paragraph, column: 6))
    let example = ["        EXAMPLE:value/one"]
    #expect(!LegacyTextParser.continuesHangingDefinition(example, column: 6))
    let atTerms = ["   Back where the terms are."]
    #expect(!LegacyTextParser.continuesHangingDefinition(atTerms, column: 6))
  }

  /// A page break cuts a hanging definition as it cuts any paragraph, in its first
  /// paragraph or in one after it. The halves are joined as lines, before linking,
  /// so a compound word broken at its hyphen is one word again and a cross reference
  /// that runs over the break is still linked.
  @Test func `a definition cut by a page break is rejoined as lines`() throws {
    let linker = InlineLinker(sectionNumbers: ["3.2"], referenceTargets: [:])
    let endOfPage = LegacyTextParser.RawBlock(
      lines: [
        "   Widget:  A part that is carried over a point-",
        "      to-point link, as set out in Section",
      ],
      followedByPageBreak: true)
    let nextPage = LegacyTextParser.RawBlock(lines: ["      3.2 and in the rest of the text."])
    let first = try #require(
      LegacyTextParser.blocks(from: [endOfPage, nextPage], proseIndent: 6, linker: linker)
        .first?.definitionItems?.first)
    let paragraph = try #require(first.definition.first?.paragraph)
    #expect(first.definition.count == 1)
    #expect(paragraph.plainText.contains("point-to-point"))
    #expect(paragraph.inlines.contains { $0.crossReference != nil })

    let definition = LegacyTextParser.RawBlock(lines: [
      "   Widget:  A part that is set on the term's line and",
      "      goes on under it.",
    ])
    let secondParagraph = LegacyTextParser.RawBlock(
      lines: ["      Its second paragraph runs to the foot of the media-"],
      followedByPageBreak: true)
    let rest = LegacyTextParser.RawBlock(lines: ["      independent page, and ends there."])
    let second = try #require(
      LegacyTextParser.blocks(
        from: [definition, secondParagraph, rest], proseIndent: 6, linker: linker
      ).first?.definitionItems?.first)
    #expect(second.definition.count == 2)
    #expect(second.definition.last?.paragraph?.plainText.contains("media-independent") == true)
  }

  /// A definition that ends a sentence at the foot of a page is not continued by the
  /// paragraph at the top of the next.
  @Test func `a finished definition is not joined across a page`() {
    let finished = LegacyTextParser.RawBlock(lines: [
      "   Widget:  A part whose definition ends",
      "      at the foot of the page.",
    ])
    let nextParagraph = LegacyTextParser.RawBlock(lines: [
      "      A second paragraph of the same definition."
    ])
    #expect(
      !LegacyTextParser.continuesDefinitionAcrossPage(finished, nextParagraph, hangColumn: nil))
    let restOfSentence = LegacyTextParser.RawBlock(lines: ["      and its end."])
    #expect(
      LegacyTextParser.continuesDefinitionAcrossPage(finished, restOfSentence, hangColumn: nil))
  }

  /// A catalog entry whose title has a colon and two spaces in it takes a hanging
  /// definition's shape too, but it is the catalog's: its term is its number.
  @Test func `a catalog entry with a colon in its title stays the catalog's`() throws {
    let catalog = LegacyTextParser.RawBlock(lines: [
      "   2063 - Flow Counting:  The part that sets out how the",
      "          counters are kept and read.",
    ])
    let blocks = LegacyTextParser.blocks(
      from: [catalog], proseIndent: 6,
      linker: InlineLinker(sectionNumbers: [], referenceTargets: [:]))
    let items = try #require(blocks.first?.definitionItems)
    #expect(items.map(\.term.plainText) == ["2063"])
  }

  @Test func `lines that only look like hanging definitions are not`() {
    // An exchange in a protocol trace: the arrow is a drawing's.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   A->B:  HELLO part/1",
        "      Part-Name: first",
      ]) == nil)
    // One space after the colon: a label, not xml2rfc's term.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Label: some text that runs on and",
        "      is indented under it.",
      ]) == nil)
    // A sentence, then two spaces: no term ends in a full stop.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   It ends here.  Then it goes on",
        "      under it.",
      ]) == nil)
    // Hung past where the definition starts.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Part:  Text that is set",
        "                  far past it.",
      ]) == nil)
    // Back at the margin.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Part:  Text that is set",
        "back at the margin.",
      ]) == nil)
    // Hung at two different columns.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Part:  Text that is set at",
        "      one column and then",
        "        at another.",
      ]) == nil)
    // Terms aligned at their colons: the second is not the first one's text.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   n=1:  The first value.",
        "     2:  The second value.",
      ]) == nil)
    // A sentence's end in the term: a bibliography entry, its title ending in a colon.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   [4] Writer, B. Some Title:  A subtitle that",
        "       runs on under it.",
      ]) == nil)
    // A column gap in the definition is a table's.
    #expect(
      LegacyTextParser.hangingDefinitions([
        "   Part:  first     second",
        "      third     fourth",
      ]) == nil)
  }

  /// RFC 757 is typeset justified: every line is padded with extra spaces between words
  /// to reach a common right margin. Those runs of spaces are what tells prose from
  /// artwork everywhere else, so all 60-odd of its paragraphs were preformatted blocks.
  @Test func `justified prose is not artwork`() throws {
    let document = try Fixtures.document("rfc757.txt")
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
    let first = try #require(
      introduction.blocks.first?.paragraph, "expected the introduction to start with a paragraph")
    #expect(!first.plainText.contains("  "), "the padding is collapsed")
    #expect(first.plainText.hasPrefix("The current ARPAnet"))
    #expect(first.plainText.hasSuffix("shortcomings."))
    #expect(
      first.plainText.split(separator: " ").count == 63,
      "every word of the paragraph, and nothing after it")
  }

  /// The prose cap was six columns everywhere: a body at column 3, plus three. RFC 1178
  /// sets its headings at 6 and its body at 9, so every paragraph it has failed the cap
  /// and was kept as artwork, and none of it was linked (#55). The cap follows the
  /// body now, and a body at column 3 keeps the classic one.
  @Test func `a body set deeper than column three is still prose`() {
    let paragraph = [
      "         A name that already means something on the network will be",
      "         misread the first time someone says it aloud.  This is worse",
      "         in a hurried conversation, where nobody stops to ask which",
      "         was meant.",
    ]
    let deeper = (["      Avoid names that are already in common use.", ""] + paragraph)
      .map(LegacyTextParser.Line.text)
    let cap = LegacyTextParser.proseIndent(deeper)
    #expect(cap == 9)
    #expect(LegacyTextParser.diagnose(paragraph, maxIndent: cap).isProse)

    let classic = [
      "   Once a site has more than one machine, each of them needs a",
      "   name of its own.  For example, to report that one of them is",
      "   down, you might tell the operator, \"The one by the window stopped.",
    ].map(LegacyTextParser.Line.text)
    #expect(LegacyTextParser.proseIndent(classic) == LegacyTextParser.classicProseIndent)
  }

  /// A paragraph cut by a page break is rejoined when the next page opens lower case,
  /// as the rest of a sentence does. An `o` bullet opens lower case too: RFC 1581's
  /// `it is assumed that:` ends a page, the list under it starts the next, and its
  /// first item was read into the sentence as `that: o The most recently ...`.
  @Test func `a bullet at the top of a page is not the rest of a sentence`() {
    let endOfPage = LegacyTextParser.RawBlock(lines: [
      "   When a link has been quiet for a while, a router has heard nothing",
      "   new about the neighbor at its far end, so if nothing has arrived",
      "   on the link recently it is taken that:",
    ])
    let bullet = LegacyTextParser.RawBlock(lines: [
      "   o  The last information heard from the neighbor still holds."
    ])
    #expect(!LegacyTextParser.shouldJoinAcrossPage(endOfPage, bullet, proseIndent: 6))

    let restOfSentence = LegacyTextParser.RawBlock(lines: [
      "   the last information heard from the neighbor on that link still"
    ])
    #expect(LegacyTextParser.shouldJoinAcrossPage(endOfPage, restOfSentence, proseIndent: 6))
  }

  /// Nor is it the rest of a sentence when the line above it has no final punctuation,
  /// which is the other reason a page join is made: RFC 6614's `For example, they send`
  /// ends a page, and its list of packet types, which starts the next, was read into it
  /// as `they send o Access-Request o Accounting-Request ...`.
  @Test func `a bullet after an unfinished sentence is not its rest`() {
    let endOfPage = LegacyTextParser.RawBlock(lines: [
      "   Clients over the secure transport send the same messages on a",
      "   connection they opened as they would over the plain one (see",
      "   Section 3.2 (1) and (2)).  For example, they send",
    ])
    let bullet = LegacyTextParser.RawBlock(lines: ["   o  Access-Request"])
    #expect(!LegacyTextParser.shouldJoinAcrossPage(endOfPage, bullet, proseIndent: 6))

    let restOfSentence = LegacyTextParser.RawBlock(lines: [
      "   Access-Request, Accounting-Request and Status-Server packets."
    ])
    #expect(LegacyTextParser.shouldJoinAcrossPage(endOfPage, restOfSentence, proseIndent: 6))
  }

  /// A drawing with blank lines inside it, such as a message ladder, arrives as one
  /// raw block per stretch between them. It is one artwork, with its blank lines and
  /// its pieces where they stand against each other, not a card per stretch, each
  /// moved to the margin (#437).
  @Test func `artwork that blank lines cut is one artwork`() throws {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let pieces = [
      ["      Sender                              Receiver"],
      ["      Hello(1) ------>"],
      ["                          <------ Ack(1)"],
    ].map { LegacyTextParser.RawBlock(lines: $0) }
    let blocks = LegacyTextParser.blocks(from: pieces, proseIndent: 3, linker: linker)
    #expect(blocks.count == 1)
    let artwork = try #require(blocks.first?.preformatted)
    #expect(artwork.kind == .artwork)
    #expect(
      artwork.text == """
        Sender                              Receiver

        Hello(1) ------>

                            <------ Ack(1)
        """)
  }

  /// Prose between two pieces of artwork ends the first: they are two.
  @Test func `artwork with prose between is two artworks`() {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let blocks = LegacyTextParser.blocks(
      from: [
        LegacyTextParser.RawBlock(lines: ["      +-------+", "      | Front |", "      +-------+"]),
        LegacyTextParser.RawBlock(lines: [
          "   The box above stands for the sender, and the one below for the",
          "   receiver of every message in this section.",
        ]),
        LegacyTextParser.RawBlock(lines: ["      +------+", "      | Back |", "      +------+"]),
      ], proseIndent: 3, linker: linker)
    #expect(blocks.map { $0.preformatted != nil } == [true, false, true])
  }

  /// Prose the prose test refused, and a title underlined with dashes, are set as
  /// artwork in a document indented deeper than its body, and are not one with the
  /// drawings beside them: joined, a section's drawings and text were one block.
  @Test(arguments: [
    ["      Frame", "      -----"],
    [
      "         Each frame carries a sixteen bit tag that the sender chooses",
      "         and the receiver echoes back in its reply to the frame.",
    ],
  ])
  func `a title or prose set as artwork is not joined to a drawing`(lines: [String]) {
    #expect(!LegacyTextParser.joinsArtwork(lines))
    #expect(LegacyTextParser.joinsArtwork(["      Hello(1) ------>"]))
  }

  /// A page break ends a drawing: what starts the next page is as often a heading.
  @Test func `artwork is not joined across a page break`() {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let blocks = LegacyTextParser.blocks(
      from: [
        LegacyTextParser.RawBlock(
          lines: ["      +-------+", "      | Front |", "      +-------+"],
          followedByPageBreak: true),
        LegacyTextParser.RawBlock(lines: ["      +------+", "      | Back |", "      +------+"]),
      ], proseIndent: 3, linker: linker)
    #expect(blocks.count == 2)
  }

  /// One-line definitions a blank line apart are set as artwork until a hanging
  /// one below says they are a list, and it takes them back as the blocks they
  /// made: joined as artwork, they were left out of it (#437).
  @Test func `one-line definitions are not joined as artwork`() throws {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let entry = { (name: String) in
      LegacyTextParser.RawBlock(lines: [
        "   Field label:     \(name)",
        "   Value kind:      Text only.",
      ])
    }
    let hanging = LegacyTextParser.RawBlock(lines: [
      "   Field label:     gamma, which this entry goes on to explain over",
      "                    a second line under the first.",
    ])
    let blocks = LegacyTextParser.blocks(
      from: [entry("alpha"), entry("beta"), hanging], proseIndent: 3, linker: linker)
    #expect(blocks.count == 1)
    #expect(try #require(blocks.first?.definitionItems).count == 5)
  }
}
