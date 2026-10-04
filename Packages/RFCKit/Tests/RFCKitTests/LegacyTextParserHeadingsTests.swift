import Foundation
import Testing

@testable import RFCKit

/// What is a heading, how sections nest, and the layouts that decide it.
@Suite("Legacy text parser: headings")
struct LegacyTextParserHeadingsTests {
  @Test func `unnumbered headings`() throws {
    let document = try Fixtures.document("rfc1149.txt")
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
    let document = try Fixtures.document("rfc5234.txt")
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
    let document = try Fixtures.document("rfc21.txt")
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
    let document = try Fixtures.document("rfc1245.txt")
    #expect(document.header.id == .rfc(1245))
    #expect(document.header.title == "OSPF protocol analysis")

    #expect(document.allSections.count < 40, "got \(document.allSections.count) sections")
    #expect(document.section(number: "1.0")?.titleText == "Introduction")
    #expect(document.section(number: "3.1")?.titleText == "Operational data")
    #expect(document.section(number: "6.0")?.titleText == "Reference Documents")
    #expect(document.sections.contains { $0.titleText == "Author's Address" })

    // Lines from the middle of a paragraph must not become sections.
    let titles = document.allSections.map(\.titleText)
    #expect(!titles.contains { $0.hasPrefix("The changes") })
    #expect(!titles.contains { $0.hasPrefix("This report") })

    // The abstract is still recognized, and its paragraphs stay whole.
    let abstract = try #require(document.header.abstract.first?.paragraph, "abstract missing")
    #expect(abstract.plainText.hasPrefix("This is the first"))
    #expect(abstract.plainText.hasSuffix("Interior Gateway Protocol)."))
  }

  /// Where a document sets as much text at column 0 as at its body indent, column 0
  /// says nothing about what is a heading, and a heading has to stand alone between
  /// blank lines to be read as one (#56). RFC 1540 lists the protocol standards one
  /// per line at column 0 against a body indented three, 395 lines each way: the tie
  /// used to resolve to an indented body and every row became a section.
  @Test func `a column zero table is not a stack of headings`() throws {
    let document = try Fixtures.document("rfc1540.txt")
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
    let document = try Fixtures.document("rfc796.txt")
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
    let document = try Fixtures.document("rfc2078.txt")
    #expect(document.allSections.filter { $0.number != nil && !$0.isAppendix }.count == 76)
    #expect(document.section(number: "2.4.12")?.titleText == "GSS_Release_OID call")
    #expect(document.section(number: "2.2.8")?.anchor == "section-2.2.8")
    #expect(document.section(number: "2.4")?.subsections.count == 19)
    #expect(document.crossReferences.contains { $0.target == .anchor("section-2.2.8") })
  }

  /// The same shape is a second numbering where a document already has the first: RFC
  /// 705 lists its commands as `1.  BEGIN Command` and describes each again under `1:
  /// BEGIN   4b`, and the colon form read the descriptions as seven more sections 1-7.
  @Test func `a colon number repeating a heading number is not a heading`() throws {
    let document = try Fixtures.document("rfc705.txt")
    let numbered = document.allSections.filter { $0.number != nil }
    #expect(
      numbered.map(\.titleText)
        == ["BEGIN", "LISTEN", "RESPONSE", "MESSAGE", "INTERRUPT", "END", "REPLY"].map {
          "\($0) Command"
        })
  }

  /// A section's title is the words of its heading, not the columns they were set in,
  /// as reading it back from the XML gives (#683). RFC 757's contents-style headings
  /// end in a page number set far to the right.
  @Test func `a section's title has its whitespace collapsed`() throws {
    let titles = try Fixtures.document("rfc757.txt").allSections.map(\.titleText)
    #expect(!titles.isEmpty)
    #expect(titles.filter { $0 != $0.collapsingWhitespace() } == [])
  }

  /// An appendix numbered like a section, `APPENDIX 3`, is named `appendix-3`, not
  /// `section-3`: a document may have a section 3 as well, and `Section 3` in its
  /// prose cites that one, never the appendix.
  @Test func `an appendix numbered like a section is anchored as an appendix`() throws {
    let heading = try #require(
      LegacyTextParser.heading(from: "APPENDIX 3  Worked Examples", separators: []))
    #expect(heading.isAppendix)
    #expect(heading.anchor == "appendix-3")
    let lettered = try #require(
      LegacyTextParser.heading(from: "Appendix B. Examples", separators: []))
    #expect(lettered.anchor == "appendix-B")
  }

  /// `Appendix A: Title` is how about 150 legacy RFCs head an appendix (#200). The
  /// `Appendix` has to be there: without it a letter and a colon at column 0 is as
  /// often a question and its answer. The shapes the parser already knew keep reading
  /// as before.
  @Test func `an appendix may be headed with a colon after its letter`() {
    let colon = LegacyTextParser.appendixHeading(in: "Appendix A: Protocol State Tables")
    #expect(colon?.number == "A")
    #expect(colon?.title == "Protocol State Tables")
    #expect(LegacyTextParser.appendixHeading(in: "Appendix E.1: Timer Details")?.number == "E.1")

    #expect(LegacyTextParser.appendixHeading(in: "A: Only when the sender asks.") == nil)

    #expect(LegacyTextParser.appendixHeading(in: "Appendix B. Examples")?.number == "B")
    #expect(LegacyTextParser.appendixHeading(in: "Appendix C Change Log")?.number == "C")
    #expect(LegacyTextParser.appendixHeading(in: "D.2. Second Example")?.number == "D.2")
  }

  /// However a legacy RFC names an appendix, it is one (#201): with `Appendix` or
  /// `Annex` in any case, a letter, a Roman or an Arabic numeral, and a title set off by
  /// a full stop, a colon, dashes or spaces, or no title at all. These were unnumbered
  /// headings titled with the whole line, or refused as prose for their full stop.
  @Test func `an appendix is numbered however it names itself`() {
    func heading(_ line: String) -> [String]? {
      LegacyTextParser.appendixHeading(in: line).map { [$0.number, $0.title] }
    }
    #expect(heading("Appendix A.") == ["A", ""])
    #expect(heading("Appendix D:") == ["D", ""])
    #expect(heading("APPENDIX F") == ["F", ""])
    #expect(heading("APPENDIX 2 - COMMAND SYNTAX") == ["2", "COMMAND SYNTAX"])
    #expect(
      heading("Appendix 1.  Session States and the Events That Change Them.")
        == ["1", "Session States and the Events That Change Them."])
    #expect(heading("Appendix IV.  Worked Examples") == ["IV", "Worked Examples"])
    #expect(heading("Appendix B--A Small Translator") == ["B", "A Small Translator"])
    #expect(heading("Appendix E.2 -  Requests") == ["E.2", "Requests"])
    #expect(
      heading("Annex C (informative): Checking a Signature Later")
        == ["C", "(informative): Checking a Signature Later"])
    #expect(heading("Appendix A: examples follow") == ["A", "examples follow"])
  }

  /// A lettered subsection set off like a heading, `B.1.2.  ` or `C.4  `, is an
  /// appendix's whatever its title starts with: a file, a field, an attribute's name.
  @Test func `a lettered subsection is an appendix whatever its title starts with`() {
    let subsection = LegacyTextParser.appendixHeading(
      in: "B.1.2.  successful-ok-with-notes (0x0001)")
    #expect(subsection?.number == "B.1.2")
    #expect(subsection?.title == "successful-ok-with-notes (0x0001)")
    #expect(LegacyTextParser.appendixHeading(in: "C.4  starting over")?.number == "C.4")
  }

  /// What only shares an appendix heading's first letters is not one: prose that names
  /// an appendix, a word after `Appendix` that is not a number, a reference in prose.
  @Test func `a mention of an appendix is not an appendix heading`() {
    #expect(LegacyTextParser.appendixHeading(in: "Appendix A describes the exchange") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix A.12).") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix IANA Considerations") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix: Terms Used") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendixes A and B") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "A.4 for the details of the exchange.") == nil)
    #expect(LegacyTextParser.appendixHeading(in: "Appendix A.........35") == nil)
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

  /// `1)` numbers RFC 1927's sections, and is a list item in most of the forty-odd
  /// documents that set it at column 0 (#199). RFC 234's agenda has the same shape and
  /// no other sign of sections, and stays a list.
  @Test func `a parenthesis numbers headings only in a sectioned document`() throws {
    #expect(
      LegacyTextParser.numbersHeadingsWithAParenthesis(
        try Fixtures.string("rfc1927.txt").components(separatedBy: "\n")))
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(
        try Fixtures.string("rfc234.txt").components(separatedBy: "\n")))

    let sectioned = [
      "Status of this Memo", "", "   Some text.", "",
      "1)  Overview", "", "   Some text.", "",
      "2)  Model", "", "   Some text.",
    ]
    #expect(LegacyTextParser.numbersHeadingsWithAParenthesis(sectioned))
    #expect(
      LegacyTextParser.numbersHeadingsWithAParenthesis(
        ["Status of this Memo", "", "1)  A title that wraps", "    onto a second line"]),
      "a wrapped title")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(Array(sectioned.dropFirst(4))),
      "no other sign of sections")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(
        ["Abstractions come first.", ""] + sectioned.dropFirst(4)),
      "a line that only starts like a section's title")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(sectioned + ["", "1)  Overview again"]),
      "a number repeated")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(sectioned + ["", "2.  Model"]),
      "a number shared with a heading, as in RFC 3116")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis([
        "Status of this Memo", "", "1)  an item that runs on", "    over a second line",
        "    and a third", "", "2)  the next item",
      ]),
      "a list item that runs on")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis([
        "Status of this Memo", "", "   The steps:", "1)  First", "", "2)  Second",
      ]),
      "an item that does not start its block")
    #expect(
      !LegacyTextParser.numbersHeadingsWithAParenthesis(["Status of this Memo", "", "3)  Three"]),
      "a number that follows from none")
  }

  /// RFC 1927 heads its seven sections `1)` to `7)`, and they were list items in the
  /// section before them (#199).
  @Test func `sections numbered with a parenthesis are sections`() throws {
    let document = try Fixtures.document("rfc1927.txt")
    #expect(document.sections.compactMap(\.number) == ["1", "2", "3", "4", "5", "6", "7"])
    #expect(document.section(number: "1")?.titleText.hasPrefix("New MIME Types") == true)
    #expect(document.section(number: "1")?.anchor == "section-1")
  }

  /// The stricter rule applies only to documents whose body is not indented: where the
  /// body *is* indented, a heading followed immediately by text is still a heading.
  @Test func `a heading in an indented body needs no blank line after it`() {
    let lines: [LegacyTextParser.Line] = [
      .text("1.  Introduction"),
      .text("   Text that follows the heading directly, with no blank line between."),
    ]
    let indented = LegacyTextParser.heading(
      at: 0, in: lines, bodyIsIndented: true, separators: [], startsBlock: true)
    #expect(indented?.title == "Introduction")
    #expect(
      LegacyTextParser.heading(
        at: 0, in: lines, bodyIsIndented: false, separators: [], startsBlock: true) == nil)
  }

  /// A tab is indentation too: a contents listing indented with tabs (RFC 1142's) had
  /// every entry match the numbered-heading pattern at column 0.
  @Test func `a tab indented line is not at column zero`() {
    let lines = LegacyTextParser.depaginate("\t1 \tScope of This Document\t1\n")
    #expect(
      LegacyTextParser.heading(
        at: 0, in: lines, bodyIsIndented: true, separators: [], startsBlock: true) == nil)
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

  /// RFC 2049 sets its appendices off with dashes, `Appendix A -- Title`, which the
  /// appendix pattern did not read: they were unnumbered sections titled with the whole
  /// line. They are appendices, lettered, and anchored where a link to one lands (#201).
  @Test func `appendices set off with dashes are appendices`() throws {
    let document = try Fixtures.document("rfc2049.txt")
    let appendix = try #require(document.section(anchor: "appendix-A"))
    #expect(appendix.isAppendix)
    #expect(appendix.number == "A")
    #expect(!appendix.titleText.hasPrefix("Appendix"))
    #expect(document.anchor(forPlace: "B") == "appendix-B")
  }

  // MARK: Contents entries and centered chapters (#403)

  /// A contents entry ends in a leader and a page number, and a heading never does:
  /// dots run on, or are spaced, or meet the number, and the number may be roman. A
  /// range in a title, `0...255`, is no leader.
  @Test func `a leader and a page number make a contents entry`() {
    #expect(LegacyTextParser.isContentsEntry("2.  Widget Overview ............................ 5"))
    #expect(LegacyTextParser.isContentsEntry("FOREWORD .............................. iv"))
    #expect(LegacyTextParser.isContentsEntry("3.1  Frobnication Order. . . . . . . . . . . 12"))
    #expect(LegacyTextParser.isContentsEntry("Widget Notes.......7"))
    #expect(!LegacyTextParser.isContentsEntry("2.  Widget Overview"))
    #expect(!LegacyTextParser.isContentsEntry("4.2  Values 0...255"))
    #expect(!LegacyTextParser.isContentsEntry("Wait for it ......"))
  }

  /// #427: three spaced dots are a leader, which a range never is.
  @Test func `a short spaced leader makes a contents entry`() {
    #expect(LegacyTextParser.isContentsEntry("Appendix B.  Widget Migration Notes  . . . 14"))
    #expect(!LegacyTextParser.isContentsEntry("Widget Notes . . 14"))
  }

  /// #427: a page number in a column of its own, with no leader, is an entry in a run
  /// of entries, blank lines between them or not.
  @Test func `a page column in a run of entries makes a contents entry`() {
    let listing: [String?] = [
      "A   Widget Registry and Frob Allocation         21",
      "B   Frob Tables                                 23",
      "",
      "APPENDIX D                                     vii",
    ]
    for index in [0, 1, 3] {
      #expect(LegacyTextParser.isContentsEntry(at: index, in: listing))
    }
  }

  /// A heading that carries its page number at the margin and stands between
  /// paragraphs is no entry, and neither is a heading whose title is a number, a
  /// status code or a year, which has no word before the gap.
  @Test func `a page column alone or after no word is no contents entry`() {
    let body: [String?] = [
      "   the frob is then handed to the widget layer.",
      "",
      "APPENDIX C:  WIDGET FORMATS                           12",
      "",
      "   Each widget carries its own frob count.",
    ]
    #expect(!LegacyTextParser.isContentsEntry(at: 2, in: body))
    let numbered: [String?] = ["12.4.  299", "", "B.3.  1983", "Widget Overview 5"]
    for index in [0, 2, 3] {
      #expect(!LegacyTextParser.isContentsEntry(at: index, in: numbered))
    }
  }

  /// A column-0 table row that ends in a gap and a number is no heading: RFC 391's
  /// rows each opened a section, named for its host and its figures.
  @Test func `a table row ending in a number column opens no section`() throws {
    let document = try Fixtures.document("rfc391.txt")
    #expect(!document.allSections.contains { $0.titleText.contains("HOST") })
  }

  /// A column-0 contents listing is not a stack of headings: RFC 793's opened sections
  /// 1, 2 and 3 over the listing, with its sub-entries inside them as artwork, and a
  /// `REFERENCES ..... 85` section that took the preface for a bibliography.
  @Test func `a column zero contents listing opens no sections`() throws {
    let document = try Fixtures.document("rfc793.txt")
    #expect(!document.allSections.contains { $0.titleText.contains("....") })
    #expect(!document.artworkText.contains { $0.contains("Motivation ....") })
    #expect(document.nestedParagraphs.contains { $0.plainText.contains("nine earlier editions") })
  }

  /// RFC 791 and 793, and the protocol specifications set like them, center a chapter's
  /// heading, `1.  INTRODUCTION`, and set its subsections at column 0. Centered, it was
  /// a list of one item; it is a heading, because the next heading is its first
  /// subsection.
  @Test func `a centered chapter heading heads its chapter`() throws {
    let document = try Fixtures.document("rfc793.txt")
    let introduction = try #require(document.section(number: "1"))
    #expect(introduction.titleText == "INTRODUCTION")
    #expect(introduction.subsections.first?.number == "1.1")
    #expect(introduction.blocks.first?.paragraph?.plainText.hasPrefix("The Transmission") == true)
    #expect(document.sections.compactMap(\.number) == ["1", "2", "3"])
    #expect(
      !document.lists.contains { list in
        list.items.count == 1 && list.items[0].blocks.first?.paragraph?.plainText == "PHILOSOPHY"
      })
  }

  /// A numbered line on its own is a centered heading only where the next heading is
  /// its first subsection, and no nearer line of its shape has its number.
  @Test func `a numbered line is a centered heading only before its first subsection`() {
    let lines: [LegacyTextParser.Line] = [
      .text(""), .text("                         2.  WIDGET RULES"), .text(""),
      .text("   The text."), .text(""), .text("2.1.  Widget Sizes"), .text(""),
    ]
    func heading(_ lines: [LegacyTextParser.Line], at index: Int = 1) -> String? {
      LegacyTextParser.centeredHeadings(
        in: lines, from: 0, bodyIsIndented: true, separators: [])[index]?.title
    }
    #expect(heading(lines) == "WIDGET RULES")
    var nextIsNotItsSubsection = lines
    nextIsNotItsSubsection[5] = .text("3.1.  Widget Sizes")
    #expect(heading(nextIsNotItsSubsection) == nil)
    var notOnItsOwn = lines
    notOnItsOwn[2] = .text("   The text.")
    #expect(heading(notOnItsOwn) == nil)
    var aContentsEntry = lines
    aContentsEntry[1] = .text("   2.  WIDGET RULES ................ 4")
    #expect(heading(aContentsEntry) == nil)
    var aNearerOne = lines
    aNearerOne[3] = .text("                         2.  WIDGET RULES")
    #expect(heading(aNearerOne) == nil, "a row of the same number sits nearer")
    #expect(heading(aNearerOne, at: 3) == "WIDGET RULES")
  }

  // MARK: Unnumbered headings (#201)

  /// A column-0 line that starts in lower case is a MIB line, wrapped prose or an `o`
  /// list item, never a heading.
  @Test func `a line starting in lower case is not an unnumbered heading`() {
    #expect(LegacyTextParser.refusesUnnumberedHeading("fooTableEntry OBJECT-TYPE"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("continued from the line above it"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("o  An item of a list"))
    #expect(!LegacyTextParser.refusesUnnumberedHeading("Security Considerations"))
  }

  @Test func `code or diagram punctuation is not an unnumbered heading`() {
    #expect(LegacyTextParser.refusesUnnumberedHeading("Example-MIB DEFINITIONS ::= BEGIN"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Message ::= SEQUENCE {"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("}"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Field    | Value"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("+--------+-------+"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Client -> Server"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Totals ======"))
    #expect(!LegacyTextParser.refusesUnnumberedHeading("Appendix -- Examples"))
  }

  @Test func `a sentence's end is not an unnumbered heading`() {
    #expect(LegacyTextParser.refusesUnnumberedHeading("This memo describes nothing new."))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Commands, replies and codes;"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Hosts, gateways,"))
    #expect(!LegacyTextParser.refusesUnnumberedHeading("Commands, Replies, etc."))
  }

  /// Past 50 characters sentence case turns from titles into prose; title case and all
  /// capitals are headings at any length, and short sentence case still is.
  @Test func `long sentence case is not an unnumbered heading`() {
    #expect(
      LegacyTextParser.refusesUnnumberedHeading(
        "This document describes the way hosts exchange their tables"))
    #expect(
      !LegacyTextParser.refusesUnnumberedHeading(
        "Transmission of Datagrams over Networks with Long Headers"))
    #expect(
      !LegacyTextParser.refusesUnnumberedHeading(
        "TRANSMISSION OF DATAGRAMS OVER NETWORKS WITH LONG HEADERS"))
    #expect(
      !LegacyTextParser.refusesUnnumberedHeading(
        "Coexistence of the Relay Agents between Two Neighboring Networks"))
    #expect(!LegacyTextParser.refusesUnnumberedHeading("How to read this memo"))
  }

  /// An appendix heading that names itself as one but has no number is an unnumbered
  /// heading, and keeps passing the unnumbered test with a trailing period, a
  /// lower-case word or its length: what it opens with says heading.
  @Test func `an unnumbered appendix heading is a heading however it is written`() {
    #expect(!LegacyTextParser.refusesUnnumberedHeading("Appendix: Terms Used."))
    #expect(
      !LegacyTextParser.refusesUnnumberedHeading(
        "Appendix - notes on the older versions of this protocol"))
    #expect(!LegacyTextParser.refusesUnnumberedHeading("ANNEX: the registration template"))
  }

  /// The appendix exemption is for a heading's opening, not for any line that shares
  /// its first letters: wrapped prose, a reference to an appendix, an ITU name.
  @Test func `an appendix mentioned in prose is still not an unnumbered heading`() {
    #expect(
      LegacyTextParser.refusesUnnumberedHeading("appendix to the manual, which describes them"))
    #expect(
      LegacyTextParser.refusesUnnumberedHeading("Appendixes are listed at the end of this memo."))
    #expect(LegacyTextParser.refusesUnnumberedHeading("A.4 for the details of the exchange."))
    #expect(
      LegacyTextParser.refusesUnnumberedHeading("X.400 gateways, which the next section covers,"))
    #expect(
      LegacyTextParser.refusesUnnumberedHeading(
        "Appendix B holds the drawings of every transition between the states"))
    #expect(LegacyTextParser.refusesUnnumberedHeading("Appendix C for the list of the codes)."))
  }

  /// Through `parse`: a MIB set at column 0 opens no sections.
  @Test func `MIB lines at column 0 open no sections`() throws {
    let document = try Fixtures.document("rfc2013.txt")
    let titles = document.allSections.map(\.title.plainText)
    #expect(!titles.contains("UDP-MIB DEFINITIONS ::= BEGIN"))
    #expect(!titles.contains("udpMIB MODULE-IDENTITY"))
    #expect(!titles.contains { $0.hasPrefix("udpInDatagrams") })
  }

  @Test func `ASN.1 definitions at column 0 open no sections`() throws {
    let document = try Fixtures.document("rfc2511.txt")
    #expect(!document.allSections.contains { $0.title.plainText.contains("::=") })
  }

  @Test func `wrapped prose at column 0 opens no sections`() throws {
    let document = try Fixtures.document("rfc793.txt")
    let titles = document.allSections.map(\.title.plainText)
    #expect(!titles.contains { $0.first?.isLowercase == true })
    #expect(titles.contains("OPEN Call"))
  }
}
