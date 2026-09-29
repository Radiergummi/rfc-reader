import Foundation
import Testing

@testable import RFCKit

/// What is a heading, how sections nest, and the layouts that decide it.
@Suite("Legacy text parser: headings")
struct LegacyTextParserHeadingsTests {
  @Test func `unnumbered headings`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
    let titles = document.sections.map(\.titleText)
    #expect(
      titles == [
        "Overview and Rational", "Frame Format", "Discussion", "Security Considerations",
        "Author's Address",
      ])
    #expect(document.header.abstract.isEmpty, "RFC 1149 has no abstract")
    #expect(document.sections.allSatisfy { $0.number == nil })
  }

  @Test func `numbered sections nest`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    #expect(document.sections.map(\.number) == ["1", "2", "3", "4", "5", "6", "A", "B", nil])
    #expect(document.sections.last?.titleText == "Authors' Addresses")
    let operators = try #require(document.section(number: "3"))
    #expect(operators.subsections.count == 10)
    #expect(operators.subsections.last?.titleText == "Operator Precedence")
    #expect(document.section(number: "2.3")?.titleText == "Terminal Values")
    #expect(document.section(number: "3.1")?.titleText == "Concatenation: Rule1 Rule2")
    let appendixB = try #require(document.section(number: "B"))
    #expect(appendixB.isAppendix)
    #expect(appendixB.subsections.map(\.number) == ["B.1", "B.2"])
    #expect(!document.sections.contains { $0.titleText == "Table of Contents" })
  }

  /// `Section.title` was a `String`, so a heading that named a document -- 3,471 of
  /// them across the corpus, "Changes from RFC 3066" among them -- could not carry
  /// the link even in principle. RFC 21 heads a section "Revisions to NWG/RFC 11".
  @Test func `headings carry their cross references`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc21.txt"))
    let heading = try #require(document.allSections.first { $0.titleText.contains("Revisions to") })
    let targets = heading.title.compactMap(\.crossReference?.target)
    #expect(targets == [.document(.rfc(11), section: nil)])
    #expect(heading.titleText == "Revisions to NWG/RFC\u{00A0}11")

    // The number belongs to the section, not to the words, so the reader composes
    // it around whatever the heading links to.
    let number = try #require(heading.number)
    #expect(heading.displayTitle == "\(number). Revisions to NWG/RFC\u{00A0}11")
    if case .text(let prefix)? = heading.displayTitleInlines.first {
      #expect(prefix == "\(number). ")
    } else {
      Issue.record("the number should lead the heading as its own run")
    }
  }

  /// RFC 1245 sets its body at column 0, so every prose line looks like an unnumbered
  /// heading. The first full corpus run turned it into 262 sections; documents of this
  /// shape reached 10,000 (RFC 1142).
  @Test func `unindented body does not turn every line into a heading`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1245.txt"))
    #expect(document.header.id == .rfc(1245))
    #expect(document.header.title == "OSPF protocol analysis")

    #expect(document.allSections.count < 40, "got \(document.allSections.count) sections")
    #expect(document.section(number: "1.0")?.titleText == "Introduction")
    #expect(document.section(number: "3.1")?.titleText == "Operational data")
    #expect(document.section(number: "6.0")?.titleText == "Reference Documents")
    #expect(document.sections.contains { $0.titleText == "Author's Address" })

    // Lines from the middle of a paragraph must not become sections.
    let titles = document.allSections.map(\.titleText)
    #expect(!titles.contains { $0.hasPrefix("The changes between version 1") })
    #expect(!titles.contains { $0.hasPrefix("This report attempts to summarize") })

    // The abstract is still recognised, and its paragraphs stay whole.
    guard case .paragraph(let abstract)? = document.header.abstract.first else {
      Issue.record("abstract missing")
      return
    }
    #expect(abstract.plainText.hasPrefix("This is the first of two reports"))
    #expect(abstract.plainText.hasSuffix("OSPF is an Interior Gateway Protocol)."))
  }

  /// Where a document sets as much text at column 0 as at its body indent, column 0
  /// says nothing about what is a heading, and a heading has to stand alone between
  /// blank lines to be read as one (#56). RFC 1540 lists the protocol standards one
  /// per line at column 0 against a body indented three, 395 lines each way: the tie
  /// used to resolve to an indented body and every row became a section.
  @Test func `a column zero table is not a stack of headings`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1540.txt"))
    let titles = document.allSections.map(\.titleText)
    #expect(!titles.contains { $0.hasPrefix("IP ") || $0.hasPrefix("TCP ") })
    #expect(document.allSections.count < 60, "\(document.allSections.count) sections")

    // The numbered headings it does set are still headings, and the table is a block.
    #expect(titles.contains("The Standardization Process"))
    #expect(titles.contains("The Request for Comments Documents"))
    let artwork = document.artworkText
    #expect(artwork.contains { $0.contains("Internet Protocol") && $0.contains("791") })
  }

  /// A heading was refused if its first word was `network`, `internet` or `request`,
  /// to keep `Network Working Group` and `Request for Comments: 796` out of the body --
  /// but the rule held anywhere in a document, and refused about 120 real headings with
  /// those two, RFC 796's only one among them: `Internet to Local Net Address Mappings`.
  @Test func `a heading may start with a word the front matter uses`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc796.txt"))
    let mappings = try #require(
      document.allSections.first { $0.titleText == "Internet to Local Net Address Mappings" })
    #expect(mappings.blocks.count > 10, "\(mappings.blocks.count) blocks")
    #expect(document.header.id == .rfc(796))
    #expect(!document.allSections.contains { $0.titleText.hasPrefix("Network Working Group") })
  }

  /// RFC 2078 numbers its headings `1:` and `2.4.12:`, a shape the heading pattern did
  /// not know, so the body came out as one untitled run: no table of contents, and
  /// `Section 2.2.8` resolving to nothing (#71). RFC 2743 and 2130 are set the same way.
  @Test func `headings numbered with a colon are headings`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2078.txt"))
    #expect(document.allSections.filter { $0.number != nil }.count == 76)
    #expect(document.section(number: "2.4.12")?.titleText == "GSS_Release_OID call")
    #expect(document.section(number: "2.2.8")?.anchor == "section-2.2.8")
    #expect(document.section(number: "2.4")?.subsections.count == 19)
    #expect(document.crossReferences.contains { $0.target == .anchor("section-2.2.8") })
  }

  /// The same shape is a second numbering where a document already has the first: RFC
  /// 705 lists its commands as `1.  BEGIN Command` and describes each again under `1:
  /// BEGIN   4b`, and the colon form read the descriptions as seven more sections 1-7.
  @Test func `a colon number repeating a heading number is not a heading`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc705.txt"))
    let numbered = document.allSections.filter { $0.number != nil }
    #expect(
      numbered.map(\.titleText)
        == ["BEGIN", "LISTEN", "RESPONSE", "MESSAGE", "INTERRUPT", "END", "REPLY"].map {
          "\($0) Command"
        })
  }

  /// `Appendix A: Title` is how about 150 legacy RFCs head an appendix (#200). The
  /// `Appendix` has to be there: without it a letter and a colon at column 0 is as
  /// often a question and its answer, and a title-less or lower-case line is not an
  /// appendix heading: it stays the unnumbered heading it was. The shapes the parser
  /// already knew keep reading as before.
  @Test func `an appendix may be headed with a colon after its letter`() {
    let colon = LegacyTextParser.appendixHeading(in: "Appendix A: Protocol State Tables")
    #expect(colon?.number == "A")
    #expect(colon?.title == "Protocol State Tables")
    #expect(LegacyTextParser.appendixHeading(in: "Appendix E.1: Timer Details")?.number == "E.1")

    #expect(LegacyTextParser.appendixHeading(in: "A: Only when the sender asks.") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix A:") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix A: examples follow") == nil)

    #expect(LegacyTextParser.appendixHeading(in: "Appendix B. Examples")?.number == "B")
    #expect(LegacyTextParser.appendixHeading(in: "Appendix C Change Log")?.number == "C")
    #expect(LegacyTextParser.appendixHeading(in: "D.2. Second Example")?.number == "D.2")
  }

  /// A colon number counts only where the number before it, or the one it is under, is
  /// a heading number too: without that, a document with one stray `11:` and no `11.`
  /// to repeat passed the gate. RFC 526's agenda sets a time that way, and only the
  /// next line not being blank kept it from becoming section 11.
  @Test func `a colon number has to follow from another`() throws {
    #expect(
      !LegacyTextParser.numbersHeadingsWithAColon(
        try Fixtures.string("rfc526.txt").components(separatedBy: "\n")))
    #expect(
      LegacyTextParser.numbersHeadingsWithAColon(
        try Fixtures.string("rfc2078.txt").components(separatedBy: "\n")))

    #expect(LegacyTextParser.numbersHeadingsWithAColon(["0: Summary"]))
    #expect(LegacyTextParser.numbersHeadingsWithAColon(["1: One", "2: Two"]))
    #expect(!LegacyTextParser.numbersHeadingsWithAColon(["2: Two"]))
    #expect(
      LegacyTextParser.numbersHeadingsWithAColon(["1. One", "2: Two"]),
      "a predecessor of either kind")
    #expect(LegacyTextParser.numbersHeadingsWithAColon(["2. Two", "2.1: Under it"]), "or a parent")
    #expect(
      LegacyTextParser.numbersHeadingsWithAColon(["2.4. Calls", "2.4.11. One", "2.4.12: Next"]))
    #expect(
      LegacyTextParser.numbersHeadingsWithAColon(["1: Model", "1.1: Segments", "1.1.1.1: Layout"]),
      "a level skipped, as in RFC 2130")
    #expect(
      LegacyTextParser.numbersHeadingsWithAColon(["2  Models", "3: X.500"]),
      "no separator, as in RFC 1309")
    #expect(!LegacyTextParser.numbersHeadingsWithAColon(["3. Three", "2.4.12: Orphan"]))
  }

  /// The stricter rule applies only to documents whose body is not indented: where the
  /// body *is* indented, a heading followed immediately by text is still a heading.
  @Test func `a heading in an indented body needs no blank line after it`() {
    let lines: [LegacyTextParser.Line] = [
      .text("1.  Introduction"),
      .text("   Text that follows the heading directly, with no blank line between."),
    ]
    let indented = LegacyTextParser.heading(
      at: 0, in: lines, bodyIsIndented: true, colonNumbered: false, startsBlock: true)
    #expect(indented?.title == "Introduction")
    #expect(
      LegacyTextParser.heading(
        at: 0, in: lines, bodyIsIndented: false, colonNumbered: false, startsBlock: true) == nil)
  }

  /// A tab is indentation too: a contents listing indented with tabs (RFC 1142's) had
  /// every entry match the numbered-heading pattern at column 0.
  @Test func `a tab indented line is not at column zero`() {
    let lines = LegacyTextParser.depaginate("\t1 \tScope of This Document\t1\n")
    #expect(
      LegacyTextParser.heading(
        at: 0, in: lines, bodyIsIndented: true, colonNumbered: false, startsBlock: true) == nil)
  }

  /// A couple of dozen documents (RFC 817, 813, 888) are typeset double spaced: a
  /// single blank line is a wrapped line and two or more are the real break. No
  /// paragraph ever formed and every line stood alone, so RFC 817 produced 577
  /// sections for 658 lines of text.
  @Test func `double spacing is collapsed and the wider gaps are kept`() {
    func paragraph(_ number: Int) -> [LegacyTextParser.Line] {
      (1...6).flatMap { line -> [LegacyTextParser.Line] in
        [.text("   Paragraph \(number) goes on at line \(line) of its text"), .text("")]
      }
    }
    let doubleSpaced =
      paragraph(1) + [.text("")] + paragraph(2) + [.text("")] + paragraph(3)
      + [.text("")] + paragraph(4)
    let collapsed = LegacyTextParser.collapsingDoubleSpacing(doubleSpaced)
    let gaps = collapsed.split { line in
      if case .text(let string) = line { return string.isEmpty }
      return false
    }
    #expect(gaps.map(\.count) == [6, 6, 6, 6])

    let tooShortToTell = paragraph(1) + paragraph(2)
    #expect(LegacyTextParser.collapsingDoubleSpacing(tooShortToTell).count == tooShortToTell.count)
  }
}
