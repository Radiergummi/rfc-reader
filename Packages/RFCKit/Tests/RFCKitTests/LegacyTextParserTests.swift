import Foundation
import Testing

@testable import RFCKit

@Suite("Legacy text parser")
struct LegacyTextParserTests {
  @Test func `strips page furniture`() throws {
    let text = try Fixtures.string("rfc2119.txt")
    let stripped = LegacyTextParser.stripPagination(text)
    #expect(!stripped.contains("[Page 1]"))
    #expect(!stripped.contains("RFC 2119                     RFC Key Words"))
    #expect(!stripped.contains("\u{0C}"))
    #expect(
      stripped.contains("Request for Comments: 2119"),
      "the first-page header block is content, not furniture")
    #expect(stripped.contains("6. Guidance in the use of these Imperatives"))
  }

  @Test func `front matter`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
    #expect(document.source == .text)
    #expect(document.header.id == .rfc(1149))
    #expect(
      document.header.title == "A Standard for the Transmission of IP Datagrams on Avian Carriers")
    #expect(document.header.authors == [Author(name: "D. Waitzman")])
    #expect(document.header.date == PublicationDate(year: 1990, month: 4))

    let abnf = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    #expect(abnf.header.id == .rfc(5234))
    #expect(abnf.header.title == "Augmented BNF for Syntax Specifications: ABNF")
    #expect(abnf.header.obsoletes == [.rfc(4234)])
    #expect(abnf.header.category == "Standards Track")
    #expect(
      abnf.header.authors == [
        Author(name: "D. Crocker", role: "Editor"), Author(name: "P. Overell"),
      ])
    #expect(abnf.header.date == PublicationDate(year: 2008, month: 1))
  }

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

  @Test func `abstract moves to header`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2119.txt"))
    #expect(!document.sections.contains { $0.titleText == "Abstract" })
    #expect(!document.sections.contains { $0.titleText.hasPrefix("Status of") })
    guard case .paragraph(let paragraph)? = document.header.abstract.first else {
      Issue.record("abstract missing")
      return
    }
    #expect(paragraph.plainText.hasPrefix("In many standards track documents"))
  }

  @Test func `paragraphs split across pages are rejoined`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
    let discussion = try #require(document.sections.first { $0.titleText == "Discussion" })
    let paragraphs = discussion.blocks.compactMap { block -> String? in
      if case .paragraph(let paragraph) = block { return paragraph.plainText }
      return nil
    }
    #expect(paragraphs.count == 1)
    #expect(
      paragraphs[0].contains("the carriers are self-regenerating."),
      "hyphenated word rejoined across the page break")
    #expect(paragraphs[0].hasSuffix("cable trays."))
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
    let artwork = grammar.blocks.compactMap { block -> Preformatted? in
      if case .preformatted(let value) = block { return value }
      return nil
    }
    #expect(artwork.contains { $0.text.contains("rulelist       =  1*( rule / (*c-wsp c-nl) )") })
  }

  @Test func `lists are detected`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let grammar = try #require(document.section(number: "4"))
    let lists = grammar.blocks.compactMap { block -> ListBlock? in
      if case .list(let list) = block { return list }
      return nil
    }
    #expect(lists.count == 1)
    #expect(lists[0].items.count == 2)
    if case .paragraph(let paragraph)? = lists[0].items[1].blocks.first {
      #expect(paragraph.plainText == "This syntax uses the rules provided in Appendix B.")
    } else {
      Issue.record("list item should contain a paragraph")
    }
  }

  @Test func `references and links`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let informative = try #require(document.section(number: "6.2"))
    guard case .references(let list)? = informative.blocks.first else {
      Issue.record("expected reference list")
      return
    }
    #expect(list.entries.map(\.anchor) == ["RFC733", "RFC822"])
    #expect(list.entries[1].documentID == .rfc(822))
    #expect(list.entries[1].title == "Standard for the format of ARPA Internet text messages")
    #expect(list.entries[1].date == PublicationDate(year: 1982, month: 8))
    #expect(list.entries[1].seriesInfo.contains { $0.name == "STD" && $0.value == "11" })

    // [US-ASCII] in prose links to the reference entry; RFC mentions link to documents.
    let terminals = try #require(document.section(number: "2.3"))
    let xrefs = terminals.blocks.flatMap { block -> [CrossReference] in
      guard case .paragraph(let paragraph) = block else { return [] }
      return paragraph.inlines.compactMap { inline in
        if case .crossReference(let xref) = inline { return xref }
        return nil
      }
    }
    #expect(xrefs.contains { $0.target == .anchor("US-ASCII") && $0.text == "[US-ASCII]" })
    #expect(document.referencedDocuments.contains(.rfc(822)))
  }

  @Test func `inline linking rules`() {
    let text = """
      Network Working Group                                          A. Person
      Request for Comments: 99999                                  Example Org
      Category: Informational                                     January 2030


                               A Synthetic Test Document

      1. Introduction

         See [RFC2119], RFC 8174 and Section 4.2 of [RFC9110]. Also Section 2
         and https://example.com/spec. Nothing in Section 9 exists.

      2. Details

         Details here.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.header.id == .rfc(99999))
    #expect(document.header.title == "A Synthetic Test Document")
    let intro = document.sections[0]
    guard case .paragraph(let paragraph)? = intro.blocks.first else {
      Issue.record("expected paragraph")
      return
    }
    let targets = paragraph.inlines.compactMap { inline -> CrossReference.Target? in
      if case .crossReference(let xref) = inline { return xref.target }
      return nil
    }
    #expect(
      targets == [
        .document(.rfc(2119), section: nil),
        .document(.rfc(8174), section: nil),
        .document(.rfc(9110), section: "4.2"),
        .anchor("section-2"),
      ])
    #expect(
      paragraph.inlines.contains { inline in
        if case .link(let url, _) = inline {
          return url.absoluteString == "https://example.com/spec"
        }
        return false
      })
    #expect(paragraph.plainText.contains("Nothing in Section 9 exists."))
  }

  /// `[RFC 2211]` matched neither pattern: the bracket pattern's anchor admitted no
  /// space or comma, and the bare pattern discarded anything a `[` preceded.
  /// Between them they dropped 1,606 of the 1,640 unlinked RFC mentions left in the
  /// corpus's prose. RFC 2606 sets its citations `[RFC 1034]`; RFC 2147 writes a
  /// multi-anchor `[RFC1883, Section 4.3]`, where the bracket is not ours to eat.
  @Test func `bracketed RFC mentions link whatever their spacing`() throws {
    let spaced = LegacyTextParser.parse(try Fixtures.string("rfc2606.txt"))
    #expect(spaced.referencedDocuments.contains(.rfc(1034)), "[RFC 1034] names a document")

    let multi = LegacyTextParser.parse(try Fixtures.string("rfc2147.txt"))
    #expect(multi.referencedDocuments.contains(.rfc(1883)))
    let notes = multi.paragraphs.filter { $0.plainText.hasPrefix("Note 2") }
    let note = try #require(notes.first)
    // The tags beside the RFC are the author's, so the brackets stay as text and
    // only the reference inside them is linked.
    #expect(note.plainText.contains(", Section 4.3]"))
  }

  @Test func `legacy bracketed RFC labels are flagged as canonical`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let xrefs = document.crossReferences
    // Measured over 1,200 corpus documents before this rule was fixed: 12,612
    // references, 253 of them chips. The rest were exactly this case.
    let canonical = try #require(
      xrefs.first { xref in
        guard case .document(let id, _) = xref.target, id.series == .rfc else { return false }
        return xref.isCanonicalLabel
      }, "without this, 98% of the library shows no chips")
    #expect(canonical.text == nil)
    #expect(canonical.label.hasPrefix("[RFC"))
    let authored = try #require(xrefs.first { $0.text == "[US-ASCII]" })
    #expect(!authored.isCanonicalLabel, "an author's own tag must survive verbatim")
  }
  /// `link` skips a pattern whose opening literal the fragment lacks. That is only
  /// sound while every match of the pattern holds the literal, so wherever a pattern
  /// matches -- over every line of every fixture, and the shapes a
  /// byte test and a grapheme test could disagree on -- its literal must be set.
  @Test func `the literal gate skips no match`() throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    var fragments = [
      "RFC\u{0301} 1", "\u{FEFF}RFC 1", "ＲＦＣ 1", "rfc 1", "section 2", "HTTP://x", "RFC\r\n1",
      "RFC\u{00A0}1", "Section\u{00A0}2 of RFC 1", "R", "RF", "Sectio", "[", "[RFC1]",
      "RFCs 1, 2 and 3", "",
    ]
    for fixture in try FileManager.default.contentsOfDirectory(atPath: directory.path)
    where fixture.hasSuffix(".txt") {
      fragments += try Fixtures.string(fixture).components(separatedBy: "\n")
    }
    for fragment in fragments {
      let literals = InlineLinker.Literals(in: fragment)
      let label = fragment.prefix(80).debugDescription
      // Each pattern is asked about its own gate: the pairing is the pattern's, not the test's.
      func check<Output>(_ pattern: InlineLinker.Gated<Output>) {
        if fragment.contains(pattern.regex) { #expect(literals[keyPath: pattern.gate], "\(label)") }
      }
      check(InlineLinker.sectionOfRFCPattern)
      check(InlineLinker.bracketPattern)
      check(InlineLinker.bareRFCPattern)
      check(InlineLinker.rfcListPattern)
      check(InlineLinker.sectionPattern)
      check(InlineLinker.urlPattern)
    }
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
    #expect(!LegacyTextParser.refusesUnnumberedHeading("How to use this document"))
  }

  /// Through `parse`: a MIB set at column 0 opens no sections.
  @Test func `MIB lines at column 0 open no sections`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2013.txt"))
    let titles = document.allSections.map(\.title.plainText)
    #expect(!titles.contains("UDP-MIB DEFINITIONS ::= BEGIN"))
    #expect(!titles.contains("udpMIB MODULE-IDENTITY"))
    #expect(!titles.contains { $0.hasPrefix("udpInDatagrams") })
  }

  @Test func `ASN.1 definitions at column 0 open no sections`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2511.txt"))
    #expect(!document.allSections.contains { $0.title.plainText.contains("::=") })
  }

  @Test func `wrapped prose at column 0 opens no sections`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc793.txt"))
    let titles = document.allSections.map(\.title.plainText)
    #expect(!titles.contains { $0.first?.isLowercase == true })
    #expect(titles.contains("INTRODUCTION"))
  }
}

@Suite("Legacy text parser: corpus findings")
struct LegacyTextCorpusFindingsTests {
  /// Two more spellings the linker was blind to, both common in the older half of
  /// the series: `RFC-791`, and a list written once as `RFCs 765, 821 and 854`.
  /// Measured on the corpus, prose held 2,223 of the first and 659 of the second,
  /// against 1,640 of the plain `RFC 791` the linker already knew.
  @Test func `hyphenated and plural mentions link`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc980.txt"))
    let xrefs = document.crossReferences
    let byTarget = Dictionary(
      xrefs.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })

    // The hyphen is the author's, not ours: `isCanonicalTag` does not count it as
    // the series' own spelling, so the words stay exactly as they were set.
    let hyphenated = try #require(byTarget[.document(.rfc(791), section: nil)])
    #expect(hyphenated.text == "RFC-791")
    #expect(byTarget[.document(.rfc(793), section: nil)]?.text == "RFC-793")

    // A number in a list reads as the list wrote it -- composing "RFC 821" over
    // the top of "RFCs 765, 821" would say RFC twice.
    let inList = try #require(byTarget[.document(.rfc(821), section: nil)])
    #expect(inList.text == "821")
    #expect(Set(document.referencedDocuments).isSuperset(of: [.rfc(765), .rfc(821), .rfc(854)]))
  }

  /// The reference list sets its anchors the way the prose cites them, and a
  /// seventh of the corpus puts a space in: `[RFC 1034]`. `referenceStartPattern`
  /// admitted no whitespace in an anchor, so those lines started no entry and were
  /// swallowed as continuation text of whatever came before -- RFC 2290 and RFC
  /// 2535 produced no bibliography at all. 782 entries across 205 documents.
  @Test func `reference anchors may hold spaces`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2606.txt"))
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

  /// `Section.title` was a `String`, so a heading that named a document -- 3,471 of
  /// them across the corpus, "Changes from RFC 3066" among them -- could not carry
  /// the link even in principle. RFC 21 heads a section "Revisions to NWG/RFC 11".
  @Test func `headings carry their cross references`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc21.txt"))
    let heading = try #require(document.allSections.first { $0.titleText.contains("Revisions to") })
    let targets = heading.title.compactMap { inline -> CrossReference.Target? in
      if case .crossReference(let xref) = inline { return xref.target }
      return nil
    }
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

  /// Shapes found in the first full corpus run (September 2026).
  @Test func `column zero title and anchor only references`() {
    let text = """
      Network Working Group                                       P. Jayaraman
      Request for Comments: 5193                                       Net.Com
      Category: Informational                                         R. Lopez
                                                               Univ. of Murcia
                                                                      May 2008

      Protocol for Carrying Authentication for Network Access (PANA) Framework

      Status of This Memo

         This memo provides information for the Internet community.

      1.  Introduction

         See [RFC-822] for details.

      6.  References

         [RFC-822]
              Crocker, D., "Standard for the Format of ARPA Internet
              Text Messages", STD 11, RFC 822, UDEL, August 1982.

         [RFC-1521]
              Borenstein, N. and N. Freed, "MIME", RFC 1521, September, 1993.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.header.id == .rfc(5193))
    #expect(
      document.header.title
        == "Protocol for Carrying Authentication for Network Access (PANA) Framework")
    #expect(document.header.date == PublicationDate(year: 2008, month: 5))
    #expect(document.sections.map(\.number) == ["1", "6"])
    guard case .references(let list)? = document.section(number: "6")?.blocks.first else {
      Issue.record("expected references")
      return
    }
    #expect(list.entries.map(\.anchor) == ["RFC-822", "RFC-1521"])
    #expect(list.entries[0].documentID == .rfc(822))
    #expect(list.entries[0].title == "Standard for the Format of ARPA Internet Text Messages")
    #expect(document.referencedDocuments == [.rfc(822), .rfc(1521)])
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

  /// A tab is eight columns, but `leadingSpaceCount` counted spaces only, so a line
  /// indented with one read as indent 0 (#40). RFC 717 indents a list with tabs
  /// under prose indented six spaces: the block's indent came out as 0, the four
  /// columns its figure shares were never stripped, and the tabs themselves reached
  /// the reader, whose verbatim style sets no tab stops.
  @Test func `tabs are columns before any indent is read`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc717.txt"))
    let artwork = document.artworkText
    #expect(!artwork.contains { $0.contains("\t") }, "a tab survived into artwork")
    #expect(
      !document.allSections.contains { $0.titleText.contains("\t") },
      "a tab survived into a heading")

    let header = try #require(artwork.first { $0.contains("Destination net") })
    let lines = header.split(separator: "\n", omittingEmptySubsequences: false)
    // The block's indent is four, from `    0`, and every line loses exactly that.
    #expect(lines.first == "0           Destination net          (8)")
    #expect(lines.contains("  This field selects the appropriate gateway processing and is used"))
    #expect(lines.contains("    0 -- Escape; protocol is specified by a subsequent field"))
  }

  /// RFC 793 repeats a three-line page header on 62 pages, justified left and right on
  /// facing pages, and it names no RFC, so the running-header pattern never matched it
  /// (#52). Each page then opened with `Transmission Control Protocol` at column 0,
  /// which is a heading: ~33 sections called `Functional Specification`, and every
  /// paragraph that crossed a page break cut in two by one of them.
  @Test func `recurring page headers are furniture not sections`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc793.txt"))
    let furniture = ["Transmission Control Protocol", "Functional Specification", "September 1981"]
    let spurious = document.allSections.filter { furniture.contains($0.titleText) }
    #expect(spurious.isEmpty, "\(spurious.count) sections are page headers")
    // The third line names the section the page is in -- `Introduction` on four
    // pages, `Philosophy` on six -- and each of those sections is already headed
    // `1.  INTRODUCTION`, `2.  PHILOSOPHY`, so none of it is a heading either.
    let unnumbered = document.allSections.filter { $0.number == nil }.map(\.titleText)
    let repeated = Dictionary(grouping: unnumbered, by: \.self).filter { $0.value.count > 1 }.keys
    #expect(repeated.isEmpty, "unnumbered headings that repeat: \(repeated.sorted())")
    #expect(!unnumbered.contains("Philosophy"))

    // With the header gone the page break is only a page break, and the sentence
    // across it is one paragraph again.
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(
      paragraphs.contains { $0.contains("the TCP must tell user to go into \"normal mode\".") })
  }

  /// A section running header is furniture on every page but the first, where it is
  /// the only thing that says a section starts. RFC 770 heads its bibliography with
  /// a centred `REFERENCES` that is no heading, and a running `References` on each of
  /// its pages; dropping every one of those lost all 58 entries.
  @Test func `a section running header still opens its section`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc770.txt"))
    let lists = document.referenceLists
    #expect(lists.flatMap(\.entries).count == 58)
    #expect(document.allSections.filter { $0.titleText == "References" }.count == 1)
  }

  /// A header that alternates between facing pages is on every other page, so it is
  /// on half of them at most, and just under half where the last pages carry none.
  /// RFC 810 sets `RFC 810 ... 1 March 1982` on its even pages, which the running-header
  /// pattern knows, and `1 March 1982 ... RFC 810` on its odd ones, which it does not:
  /// on three of eight, that header was read as a section's, and its first copy
  /// stayed in the body.
  @Test func `a header on alternate pages names the document`() throws {
    let text = try Fixtures.string("rfc810.txt")
    #expect(
      LegacyTextParser.recurringFurniture(in: text).filter { $0.hasPrefix("1 March 1982") }.count
        == 3)
    let body = LegacyTextParser.stripPagination(text).split(separator: "\n")
    #expect(!body.contains { $0.hasPrefix("1 March 1982") && $0.hasSuffix("RFC 810") })
  }

  /// Only a whole number varies from page to page, so only a whole number is masked
  /// when furniture is compared. RFC 2049 sets one-line anchors in its bibliography
  /// and four of them land at a page edge; masking every digit made `[RFC-1522]` and
  /// `[RFC-1524]` the same line recurring across pages, and both were dropped.
  @Test func `numbers inside a word do not make two lines the same`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2049.txt"))
    let anchors = document.referenceLists.flatMap { $0.entries.map(\.anchor) }
    #expect(anchors.contains("RFC-1522"))
    #expect(anchors.contains("RFC-1524"))
    #expect(anchors.count == 42)
  }

  /// A line that recurs at page edges is furniture only if it is not also the body's.
  /// RFC 2013 is a MIB module, where every object ends in `STATUS current` and a
  /// `DESCRIPTION`, and those fall within four lines of the foot of three pages; read
  /// as a section running header, every copy after the first was dropped from the
  /// module. A running header sits at the head of its pages, on every page of its
  /// section, set off by a blank line -- and is rarer anywhere else than at the edge.
  @Test func `a line the body repeats is not furniture`() throws {
    let text = try Fixtures.string("rfc2013.txt")
    let document = LegacyTextParser.parse(text)
    func count(_ line: String, in text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") == line
      }.count
    }
    let artwork = document.artworkText.joined(separator: "\n")
    for line in ["STATUS current", "DESCRIPTION"] {
      #expect(count(line, in: artwork) == count(line, in: text), "\(line)")
    }
  }

  /// A section running header belongs to the block that opens its page, directly under
  /// the document's own header. RFC 6208 registers five media types, and each
  /// registration's `Additional information:` falls at the head of a page -- but below
  /// the blank lines the removed `RFC 6208 ... April 2011` leaves, and every copy but
  /// the first was dropped as the running header of a section.
  @Test func `a line below the page header is not a section running header`() throws {
    let text = try Fixtures.string("rfc6208.txt")
    let body = LegacyTextParser.stripPagination(text)
    func count(_ text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.trimmingCharacters(in: .whitespaces) == "Additional information:"
      }.count
    }
    #expect(count(body) == count(text))
    #expect(
      LegacyTextParser.recurringFurniture(in: text).allSatisfy {
        !$0.contains("Additional information:")
      })
  }

  /// A section the reader omits -- the memo's status, its copyright, its contents -- or
  /// lifts into the header as its abstract is a few paragraphs long, and it ends at the
  /// next heading. Where the document's own headings are of a shape the parser does not
  /// know, no heading ever ends it, and the whole body went with it (#60): RFC 1927's
  /// sections are numbered `1)`, and RFC 509 follows its one-line abstract with two
  /// pages of traffic tables. RFC 1927 kept 3 of its blocks, RFC 509 none.
  @Test func `an omitted section ends where its boilerplate does`() throws {
    func middle(_ name: String) throws -> (document: RFCDocument, middle: Substring) {
      let document = LegacyTextParser.parse(try Fixtures.string(name))
      let xml = RFCXMLSerializer().serialize(document)
      let start = try #require(xml.range(of: "<middle>"))
      let end = try #require(xml.range(of: "</middle>"))
      return (document, xml[start.upperBound..<end.lowerBound])
    }
    let staples = try middle("rfc1927.txt")
    #expect(staples.middle.contains("New MIME Types: Staple"))
    #expect(!staples.middle.contains("This memo provides information for the Internet community"))

    let traffic = try middle("rfc509.txt")
    #expect(traffic.middle.contains("HOST THROUGHPUT SUMMARY"))
    #expect(traffic.document.header.abstract.count == 1)
  }

  /// Under a contents heading an entry needs a dot leader or a page number, not both:
  /// the lead-in's stricter test (#76) is for blocks with no heading to vouch for
  /// them. A listing without leaders, set as more blocks than the gap that tells
  /// boilerplate from a swallowed body, is still omitted whole.
  @Test func `a contents listing without leaders is omitted whole`() {
    let entries = (1...21).map { number in
      LegacyTextParser.RawBlock(lines: [
        "   \(number).  Section title                                      \(number + 2)"
      ])
    }
    #expect(
      LegacyTextParser.boilerplateExtent(of: entries, isContents: true, proseIndent: 6) == 21)
  }

  /// Front matter is the header and the title; a paragraph after them is the body's,
  /// whether or not a heading has come yet. RFC 796 opens with prose under a heading of
  /// a shape the scan does not stop at, and the first column-0 heading it does stop at is
  /// `References`: the front matter ran on to it, and everything before it was lost (#60).
  /// RFC 105 indents the first line of its opening paragraph and sets the second at the
  /// margin, and the second was taken for a heading that ended the front matter, leaving
  /// the first line in it.
  @Test func `the front matter ends at the first paragraph`() throws {
    let addresses = LegacyTextParser.parse(try Fixtures.string("rfc796.txt"))
    #expect(
      addresses.paragraphs.contains {
        $0.plainText.hasPrefix("This memo describes the relationship between address fields")
      })
    #expect(addresses.header.id == .rfc(796))

    let remoteJobs = LegacyTextParser.parse(try Fixtures.string("rfc105.txt"))
    #expect(
      remoteJobs.paragraphs.contains {
        $0.plainText.hasPrefix("In the discussions that follow, 'byte' means 8 bits")
      })
    #expect(!remoteJobs.allSections.contains { $0.titleText.hasPrefix("eight bits numbered") })
  }

  /// Since the front matter ends at the first paragraph (#74), whatever the title page
  /// leaves between it and the body reaches the lead-in, and is taken out of it by what
  /// it is (#76): RFC 757's phone number, and with it the whole lead-in; RFC 674's
  /// header block, under its journal stamp, and the page number after its title; RFC
  /// 1441's centred `Status of this Memo` and its paragraph, and its contents. The
  /// body after them stays.
  @Test func `the title pages leftovers are not the lead in`() throws {
    #expect(
      LegacyTextParser.parse(try Fixtures.string("rfc757.txt")).leadIn.isEmpty,
      "a phone number alone is not a lead-in")

    let procedureCallTitle = [
      "                  Procedure Call Protocol Documents",
      "                              Version 2",
    ]
    let procedureCallBody = [
      "As many of you may know SRI is part of a team working on the National",
      "Software Works project. In the course of our work we have developed a",
      "Procedure Call Protocol to be used between the modules which make up",
      "the NSW. We are interested in your comments on this protocol.",
    ]
    let procedureCall = LegacyTextParser.leadInWithoutFrontMatter(
      [
        LegacyTextParser.RawBlock(lines: [
          "Request for Comments 674                                    Jon Postel",
          "NIC 31484                                                    Jim White",
          "                                                               SRI-ARC",
          "                                                      12 December 1974",
        ]),
        LegacyTextParser.RawBlock(lines: procedureCallTitle),
        LegacyTextParser.RawBlock(lines: [
          "                                                                           1"
        ]),
        LegacyTextParser.RawBlock(lines: procedureCallBody),
      ],
      title: "Procedure Call Protocol Documents",
      proseIndent: 6,
      number: 674)
    #expect(procedureCall.map(\.lines) == [procedureCallTitle, procedureCallBody])

    let introduction = ["          1.  Introduction"]
    let managementBody = [
      "          The purpose of this document is to provide an overview of",
      "          version 2 of the Internet-standard Network Management",
      "          Framework, termed the SNMP version 2 framework (SNMPv2).",
    ]
    let management = LegacyTextParser.leadInWithoutFrontMatter(
      [
        LegacyTextParser.RawBlock(lines: ["          Status of this Memo"]),
        LegacyTextParser.RawBlock(lines: [
          "          This RFC specifes an IAB standards track protocol for the",
          "          Internet community, and requests discussion and suggestions",
          "          for improvements.  Please refer to the current edition of the",
          "          \"IAB Official Protocol Standards\" for the standardization",
          "          state and status of this protocol.  Distribution of this memo",
          "          is unlimited.",
        ]),
        LegacyTextParser.RawBlock(lines: ["          Table of Contents"]),
        LegacyTextParser.RawBlock(lines: [
          "          1 Introduction ..........................................    2",
          "          2 Components of the SNMPv2 Framework ....................    3",
          "          2.1 Structure of Management Information .................    3",
        ]),
        LegacyTextParser.RawBlock(lines: introduction),
        LegacyTextParser.RawBlock(lines: managementBody),
      ],
      title: "Introduction to version 2 of the Internet-standard Network Management Framework",
      proseIndent: 13,
      number: 1441)
    #expect(management.map(\.lines) == [introduction, managementBody])
  }

  /// A contents entry's page number may be roman (RFC 822's `PREFACE .......   ii`),
  /// but a word made of the same letters is not one.
  @Test func `a roman page number is a numeral`() {
    for page in ["i", "ii", "iv", "vi", "ix", "xiv", "xxxix"] {
      #expect(LegacyTextParser.isRomanPageNumber(Substring(page)), "\(page)")
    }
    for word in ["", "ill", "civil", "vix", "iiii", "c", "I"] {
      #expect(!LegacyTextParser.isRomanPageNumber(Substring(word)), "\(word)")
    }
  }

  /// A header block states the document's own number: RFC 674's, under its journal
  /// stamp, goes from the lead-in. A table of other RFCs is two columns stating numbers
  /// too, and stays.
  @Test func `a header block states the documents own number`() {
    let header = [
      "Request for Comments 674                                    Jon Postel",
      "NIC 31484                                                    Jim White",
      "                                                               SRI-ARC",
      "                                                      12 December 1974",
    ]
    #expect(LegacyTextParser.isHeaderBlock(header, number: 674))
    #expect(!LegacyTextParser.isHeaderBlock(header, number: 675))
    let table = [
      "   RFC 791      Internet Protocol",
      "   RFC 792      Internet Control Message Protocol",
      "   RFC 793      Transmission Control Protocol",
    ]
    #expect(!LegacyTextParser.isHeaderBlock(table, number: 1000))
  }

  /// The lead-in drops the paragraphs under a status heading only while they say what
  /// a status paragraph says, so a body that follows with no heading of its own stays.
  @Test func `only boilerplate wording is taken for boilerplate`() {
    #expect(
      LegacyTextParser.readsAsBoilerplate([
        "   This document is distributed as an RFC for information only.  It",
        "   does not specify a standard for the ARPA-Internet.",
      ]))
    #expect(
      LegacyTextParser.readsAsBoilerplate([
        "   This memo provides information for the Internet community.  It does",
        "   not specify an Internet standard.  Distribution of this memo is",
        "   unlimited.",
      ]))
    #expect(
      !LegacyTextParser.readsAsBoilerplate([
        "   The purpose of this document is to provide an overview of version 2",
        "   of the Internet-standard Network Management Framework.",
      ]))
  }

  /// A title page sets a long title over several runs of lines, and the front matter
  /// takes one of them for the title. Given the title the RFC index has, the parser uses
  /// it where its words are not the page's, and the run the front matter left behind
  /// leaves the lead-in: RFC 1343's `For Multimedia Mail Format Information` opened the
  /// body as artwork (#170).
  @Test func `the index title replaces a partial one and the rest leaves the lead in`() throws {
    let replaced = LegacyTextParser.parse(
      try Fixtures.string("rfc1149.txt"), title: "Carrier Pigeons for Internet Datagrams")
    #expect(replaced.header.title == "Carrier Pigeons for Internet Datagrams")

    let abstract = [
      "            This memo suggests a  file  format  to  be  used  to  inform",
      "            multiple   mail   reading  user  agent  programs  about  the",
      "            locally-installed facilities for handling  mail  in  various",
      "            formats.",
    ]
    let leadIn = LegacyTextParser.leadInWithoutFrontMatter(
      [
        LegacyTextParser.RawBlock(lines: [
          "                       For Multimedia Mail Format Information"
        ]),
        LegacyTextParser.RawBlock(lines: abstract),
      ],
      title: "A User Agent Configuration Mechanism for Multimedia Mail Format Information",
      proseIndent: 15,
      number: 1343)
    #expect(leadIn.map(\.lines) == [abstract])
  }

  /// The index sets older titles in sentence case and drops their article, so where its
  /// words are the page's, the page's own title stays -- unless the page sets it in
  /// capitals, which is emphasis rather than spelling.
  @Test func `the page title stays where the index only recases it`() throws {
    let avian = LegacyTextParser.parse(
      try Fixtures.string("rfc1149.txt"),
      title: "Standard for the transmission of IP datagrams on avian carriers")
    #expect(
      avian.header.title == "A Standard for the Transmission of IP Datagrams on Avian Carriers")

    let tcp = LegacyTextParser.parse(
      try Fixtures.string("rfc793.txt"), title: "Transmission Control Protocol")
    #expect(tcp.header.title == "Transmission Control Protocol")
  }

  /// The index rewords titles as well as recasing them, so the page's stays where it
  /// has most of the index's words, in order, and little else. It gives way where the
  /// front matter took something that is not the title -- a header line, an author, a
  /// paragraph that happens to use the title's words -- and where it took only the
  /// first of the runs a title page sets its title over.
  @Test func `the page title stays where the index rewords it`() {
    func title(_ page: String, _ index: String, titlePage: [[String]] = []) -> String {
      LegacyTextParser.title(page: page, index: index, titlePage: titlePage)
    }

    let managedObjects = "Definitions of Managed Objects for the Example Routing Protocol"
    #expect(
      title(managedObjects, "Definitions of Managed Objects for Example Routing Protocol")
        == managedObjects)
    let variance = "Variance for the PPP Connection Negotiation Option"
    #expect(title(variance, "Variance for the PPP Compression Negotiation Option") == variance)
    #expect(
      title("Example transfer protocol", "Example Transfer Protocol")
        == "Example transfer protocol",
      "words are compared whatever their case")

    #expect(title("Network Working Group", "Echo Protocol for Hosts") == "Echo Protocol for Hosts")
    #expect(
      title("J. Example   Example University   March 1979", "A Proposal for Example Mail")
        == "A Proposal for Example Mail")
    #expect(
      title("At Example the network meeting agreed to meet again in the spring.", "Network Meeting")
        == "Network Meeting",
      "all of the index's words, and many more of its own")
    #expect(
      title("EXAMPLE TRANSFER PROTOCOL", "Example transfer protocol")
        == "Example transfer protocol",
      "capitals give way, and the index's casing is kept")

    let partial = "A Mechanism for Configuring Mail Readers"
    let whole = "A Mechanism for Configuring Mail Readers for Multimedia Formats"
    let titlePage = [
      ["                  A Mechanism for Configuring Mail Readers"],
      ["                          FOR MULTIMEDIA FORMATS"],
    ]
    #expect(title(partial, whole, titlePage: titlePage) == whole, "the rest, however it is set")
    #expect(
      title(partial, whole, titlePage: Array(titlePage.prefix(1))) == partial,
      "without the rest on the page, the index has only named it more fully")
  }

  /// A date alone on a line is the title page's, like the author above it: RFC 355's
  /// `June 9, 1972` was the lead-in's second block (#170).
  @Test func `a date alone on a line is the title pages`() {
    let body = [
      "   Long transmission delays such as those inherent in satellite",
      "   communication are most certainly a cause for concern among users of",
      "   remote interactive systems.",
    ]
    let leadIn = LegacyTextParser.leadInWithoutFrontMatter(
      [
        LegacyTextParser.RawBlock(lines: ["                              June 9, 1972"]),
        LegacyTextParser.RawBlock(lines: body),
      ],
      title: "Response to NWG/RFC 346",
      proseIndent: 6,
      number: 355)
    #expect(leadIn.map(\.lines) == [body])
  }

  /// A document has one abstract, and it is the first. RFC 2371 embeds the TMP
  /// specification as an appendix, abstract and all, and each `Abstract` heading was
  /// lifted into the header in turn: the document's abstract came out as TMP's, and
  /// neither was left in the body. The catalogues -- RFC 1292, 1632, 2116 -- give every
  /// entry one, and lost each entry's to the header the same way (#72).
  @Test func `only the first abstract is the documents`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2371.txt"))
    let abstract = document.header.abstract.compactMap {
      if case .paragraph(let paragraph) = $0 { return paragraph.plainText }
      return nil
    }
    #expect(
      abstract.first?.hasPrefix("In many applications where different nodes cooperate") == true)
    #expect(
      document.paragraphs.contains { $0.plainText.hasPrefix("TMP provides a simple mechanism") })
    #expect(
      !document.paragraphs.contains {
        $0.plainText.hasPrefix("In many applications where different nodes cooperate")
      })
  }

  /// Furniture recurs in the same place, so a line at the foot of one page and a line
  /// at the head of the next are not two sightings of it. RFC 1556 cites ISO 8859
  /// parts 6 and 8 as one anchor each, word for word the same up to the part number
  /// on the entry's third line, and the pair straddles a page break.
  @Test func `the same line at opposite edges is not a running header`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1556.txt"))
    let labels = document.referenceLists.flatMap { $0.entries.map(\.displayAnchor) }
    #expect(labels.filter { $0 == "ISO-8859" }.count == 2)
    #expect(labels.count == 7)
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

  /// The front matter accepted one spelling of the number line, `Request for Comments:`,
  /// and 496 documents wrote another (#51): the series predates the convention and
  /// never settled on one. Each fixture is the smallest real document of its shape --
  /// a bare `RFC 757`, a colon and two spaces, a revision note after the number, a
  /// label and number far enough apart to be two columns, the number in the right
  /// column, a singular `Comment`, the source's own `Commments`, and `NWG RFC` with no slash.
  @Test(arguments: [
    ("rfc757.txt", 757), ("rfc793.txt", 793), ("rfc12.txt", 12), ("rfc50.txt", 50),
    ("rfc811.txt", 811), ("rfc4801.txt", 4801), ("rfc2347.txt", 2347), ("rfc103.txt", 103),
  ])
  func `every spelling of the number line is read`(fixture: String, number: Int) throws {
    #expect(LegacyTextParser.parse(try Fixtures.string(fixture)).header.id == .rfc(number))
  }

  /// The header block was taken to be the first run of lines, and RFC 609 opens with its
  /// title instead: the number was never reached, and the header itself became the
  /// title. Twenty documents open with a date, a title or a report number this way.
  @Test func `the header is the run that states the number`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc609.txt"))
    #expect(document.header.id == .rfc(609))
    #expect(document.header.title == "Statement of Upcoming Move of NIC/NLS Services")
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

  /// RFC 651 sets no blank line after its title, so the title run is the whole
  /// document: `1. Command name and code` and everything after it became the title,
  /// and the body was empty (#60). A numbered heading at column 0 ends the title run,
  /// unless it is the run's first line.
  @Test func `a numbered heading ends the title`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc651.txt"))
    #expect(document.header.title == "Revised Telnet Status Option")
    #expect(document.section(number: "1")?.titleText == "Command name and code")
    #expect(document.section(number: "4")?.titleText == "Motivation for the option")
  }

  /// RFC 873 opens with an NLS journal stamp in two runs of lines ahead of its header,
  /// and sets every heading five columns in, so the front matter ends where the
  /// fallback puts it, after the second run -- which was counted from the stamp, and
  /// fell before the number line. The runs are counted from the header (#60, #51).
  @Test func `the title is counted from the header`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc873.txt"))
    #expect(document.header.id == .rfc(873))
    #expect(document.header.title == "THE ILLUSION OF VENDOR SUPPORT")
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

  /// An anchor is what a deep link, the table of contents and a reading position key off,
  /// and the XML declares each one as an ID. Headings that repeat gave two sections one
  /// anchor -- RFC 1 has two `Introduction`s, RFC 19 two sections numbered 1 -- and a
  /// bibliography that lists a label twice gave two entries one: 526 documents in all
  /// (#65). A repeat takes the next free `-2`, `-3`, the way xml2rfc numbers them, and
  /// the first keeps its anchor, so every link that landed on it still does.
  @Test func `no two elements share an anchor`() throws {
    let fixtures = try Fixtures.legacyTexts()
    #expect(fixtures.count > 20)
    for fixture in fixtures {
      let document = LegacyTextParser.parse(try Fixtures.string(fixture))
      let repeated = Dictionary(grouping: document.declaredAnchors, by: { $0 }).filter {
        $0.value.count > 1
      }.keys.sorted()
      #expect(repeated.isEmpty, "\(fixture): \(repeated)")
    }

    let first = LegacyTextParser.parse(try Fixtures.string("rfc1.txt")).allSections.map(\.anchor)
    let original = try #require(first.firstIndex(of: "name-introduction"))
    let second = try #require(first.firstIndex(of: "name-introduction-2"))
    #expect(original < second)
    #expect(
      LegacyTextParser.parse(try Fixtures.string("rfc19.txt")).allSections.map(\.anchor).contains(
        "section-1-2"))

    let entries = LegacyTextParser.parse(try Fixtures.string("rfc1556.txt")).referenceLists.flatMap(
      \.entries)
    let relabelled = try #require(entries.first { $0.anchor == "ISO-8859-2" })
    #expect(
      relabelled.displayAnchor == "ISO-8859",
      "a renamed entry still reads as the label its citations use")
  }

  /// A numbered entry whose text names no RFC was recorded as the RFC its number
  /// happened to be: RFC 2013's `[1]` is ISO 8824, and it and its citation became RFC 1.
  /// 6,887 entries in 1,381 converted documents. `[2]`, which says RFC 1902, still is.
  @Test func `a numbered entry is not the RFC of its number`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2013.txt"))
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
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1041.txt"))
    let entries = document.referenceLists.flatMap(\.entries)
    #expect(entries.first { $0.displayAnchor == "1" }?.documentID == .rfc(854))
    #expect(entries.first { $0.displayAnchor == "3" }?.documentID == .rfc(885))
    #expect(
      entries.first { $0.displayAnchor == "5" }?.documentID == nil, "the IBM manual names no RFC")
    #expect(document.referencedDocuments.contains(.rfc(856)))

    // But a title names RFCs too, and the hyphenated spelling is only the fallback:
    // RFC 1494's `[1]` is "Mapping between X.400 and RFC-822 Message Bodies", RFC 1495.
    let mapping = LegacyTextParser.parse(try Fixtures.string("rfc1494.txt")).referenceLists.flatMap(
      \.entries)
    #expect(mapping.first { $0.displayAnchor == "1" }?.documentID == .rfc(1495))
  }

  /// And in the series' earliest spellings: RFC 338 cites `RFC #189` and `RFC #183`,
  /// RFC 1275 `Request for Comments 1006`, RFC 1005 `Request For Comments 990`, broken
  /// across a line.
  @Test func `an entry names an RFC in the series earliest spellings`() throws {
    let rfc338 = LegacyTextParser.parse(try Fixtures.string("rfc338.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc338.first { $0.displayAnchor == "1" }?.documentID == .rfc(189))
    #expect(rfc338.first { $0.displayAnchor == "4" }?.documentID == .rfc(183))
    #expect(rfc338.first { $0.displayAnchor == "2" }?.documentID == nil, "a note names no RFC")

    let rfc1275 = LegacyTextParser.parse(try Fixtures.string("rfc1275.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc1275.first { $0.displayAnchor == "RC87" }?.documentID == .rfc(1006))

    let rfc1005 = LegacyTextParser.parse(try Fixtures.string("rfc1005.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc1005.first { $0.displayAnchor == "3" }?.documentID == .rfc(990))
    #expect(rfc1005.first { $0.displayAnchor == "5" }?.documentID == .rfc(796))
  }

  /// The XML declares each anchor as an ID, which has to be a name: `[1]`, `[RFC 2119]`
  /// and `[Cheswick and Bellovin, 1994]` are not, in 2,361 documents (#65). And a
  /// citation of an entry that names no RFC pointed at `ref-<label>`, which no entry was
  /// declared under: RFC 2005 cited `<xref target="ref-MIP-OPTIM">` beside `<reference
  /// anchor="MIP-OPTIM">`, and 30,368 citations in 3,708 documents linked nowhere (#81).
  @Test func `every anchor is a name and every citation reaches one`() throws {
    var cited = 0
    for fixture in try Fixtures.legacyTexts() {
      let document = LegacyTextParser.parse(try Fixtures.string(fixture))
      // An NCName, closely enough: a letter or underscore, then letters, digits, `.`, `-`, `_`.
      let unnamed = document.declaredAnchors.filter {
        $0.wholeMatch(of: #/[\p{L}_][\p{L}0-9._-]*/#) == nil
      }
      #expect(unnamed.isEmpty, "\(fixture): \(unnamed)")
      let targets = document.everyCrossReference.compactMap {
        if case .anchor(let anchor) = $0.target { anchor } else { nil }
      }
      cited += targets.count
      let dangling = Set(targets).subtracting(document.declaredAnchors).sorted()
      #expect(dangling.isEmpty, "\(fixture): \(dangling)")
    }
    #expect(cited > 0, "the fixtures cite something by anchor, so the check checks something")

    // A label that is a name is the anchor, as the published series has it.
    let rfc5234 = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc5234.contains { $0.anchor == "US-ASCII" && $0.displayAnchor == "US-ASCII" })
    // One that is not takes the document it cites, and still reads as its label: RFC 2023
    // lists RFCs 1883 and 1884 both as `[2]`, and they are two anchors, not one and a `-2`.
    let rfc2023 = LegacyTextParser.parse(try Fixtures.string("rfc2023.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc2023.filter { $0.displayAnchor == "2" }.map(\.anchor) == ["RFC1883", "RFC1884"])
    let rfc2347 = LegacyTextParser.parse(try Fixtures.string("rfc2347.txt"))
    #expect(
      rfc2347.crossReferences.contains {
        $0.target == .document(.rfc(2348), section: nil) && $0.text == "[2]"
      })
    // And one that cites no document is `ref-` and the label spelled as a name.
    let rfc1556 = LegacyTextParser.parse(try Fixtures.string("rfc1556.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc1556.contains { $0.anchor == "ref-ECMA-TR-53" && $0.displayAnchor == "ECMA TR/53" })
    let rfc2606 = LegacyTextParser.parse(try Fixtures.string("rfc2606.txt")).referenceLists.flatMap(
      \.entries)
    #expect(rfc2606.contains { $0.anchor == "RFC1034" && $0.displayAnchor == "RFC 1034" })
  }

  /// Entry anchors are settled before the prose is linked, so a citation points at the
  /// anchor its entry ends with rather than one a later rename moves. None of these
  /// shapes is in the corpus, so they are pinned at the guard, on entries by hand.
  @Test func `an entry is renamed only onto an anchor nothing else holds`() {
    func settled(_ labels: [String], reserved: Set<String> = []) -> [String] {
      let entries = labels.map {
        Reference(
          anchor: LegacyTextParser.entryAnchor(label: $0, documentID: nil), displayAnchor: $0,
          title: $0)
      }
      return LegacyTextParser.settlingEntryAnchors([0: entries], reserved: reserved)[0]?.map(
        \.anchor) ?? []
    }
    // `[X-2]` keeps its own anchor, so the repeat of `[X]` does not take it from under it.
    #expect(settled(["X", "X", "X-2"]) == ["X", "X-3", "X-2"])
    // Two labels that spell one name are two anchors.
    #expect(settled(["ECMA TR 53", "ECMA TR/53"]) == ["ref-ECMA-TR-53", "ref-ECMA-TR-53-2"])
    // And an entry never takes an anchor a section can have.
    #expect(settled(["section-1"], reserved: ["section-1"]) == ["section-1-2"])
    // A label with nothing of a name in it is a note: RFC 2130's `[*]`, RFC 906's `[**]`.
    #expect(settled(["*", "**"]) == ["ref-note", "ref-note-2"])
  }

  /// A heading that repeats is renamed after the prose is linked, so what an entry must
  /// not take is every anchor a section can be renamed to, not only the ones it starts
  /// with: an entry settled onto `section-1-2` beside two sections numbered 1 lost it to
  /// the second, and its citations to a rename. Every suffix a repeat can reach is held,
  /// past the ones another heading already spells (`name-foo-2`, for `Foo 2`).
  @Test func `a repeated heading holds every anchor it can be renamed to`() {
    #expect(
      LegacyTextParser.reservedAnchors(["section-1", "section-1"]) == ["section-1", "section-1-2"])
    #expect(
      LegacyTextParser.reservedAnchors(["name-foo", "name-foo", "name-foo-2"]) == [
        "name-foo", "name-foo-2", "name-foo-3",
      ])
    #expect(
      LegacyTextParser.reservedAnchors(["section-1", "section-2"]) == ["section-1", "section-2"])
  }

  /// What `parse` reserves is every anchor its sections end with, and no entry holds one:
  /// RFC 19 numbers two sections 1, and the second is `section-1-2`.
  @Test func `every section anchor is reserved and no entry holds one`() throws {
    #expect(
      try LegacyTextParser.reservedAnchors(in: Fixtures.string("rfc19.txt")).contains("section-1-2")
    )
    for fixture in try Fixtures.legacyTexts() {
      let text = try Fixtures.string(fixture)
      let reserved = LegacyTextParser.reservedAnchors(in: text)
      let document = LegacyTextParser.parse(text)
      let unreserved = Set(document.allSections.map(\.anchor)).subtracting(reserved).sorted()
      #expect(unreserved.isEmpty, "\(fixture): \(unreserved)")
      let held = Set(document.referenceLists.flatMap(\.entries).map(\.anchor)).intersection(
        reserved
      ).sorted()
      #expect(held.isEmpty, "\(fixture): \(held)")
    }
  }

  /// A label listed twice is cited as its first entry, whether that names a document or
  /// not: RFC 2023 lists RFCs 1883 and 1884 both as `[2]`.
  @Test func `a repeated label is cited as its first entry`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2023.txt"))
    let cited = document.everyCrossReference.filter { $0.text == "[2]" || $0.label == "[2]" }.map(
      \.target)
    #expect(!cited.isEmpty)
    #expect(cited.allSatisfy { $0 == .document(.rfc(1883), section: nil) }, "\(cited)")
  }

  /// The stricter rule applies only to documents whose body is not indented: where the
  /// body *is* indented, a heading followed immediately by text is still a heading.
  @Test func `indented body still accepts headings without a blank line after`() {
    let text = """
      Network Working Group                                          A. Person
      Request for Comments: 99998                                  Example Org
      Category: Informational                                     January 2030


                               A Synthetic Test Document

      1. Introduction
         Text that follows the heading directly, with no blank line between
         the heading and the first line of the paragraph.

         A second paragraph, so that the indented body outnumbers the two
         headings sitting at column 0.

      Security Considerations
         None worth mentioning, but the section has to exist.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.sections.map(\.titleText) == ["Introduction", "Security Considerations"])
  }

  /// A tab is indentation too: the contents listing of RFC 1142 is tab-indented, and
  /// every entry matched the numbered-heading pattern.
  @Test func `tab indented lines are not headings`() {
    let text = """
      Network Working Group                                          A. Person
      Request for Comments: 99997                                  Example Org
      Category: Informational                                     January 2030


                               A Synthetic Test Document

      Contents
      \t1 \tScope and Field of Application\t1
      \t2 \tReferences\t1

      1 Scope and Field of Application

         This document specifies a routeing protocol, and the procedures
         that go with it, for use between intermediate systems.

         The protocol is defined in terms of the services it provides, the
         encoding of the protocol data units it exchanges, and the state
         machine each system runs.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.sections.map(\.titleText) == ["Contents", "Scope and Field of Application"])
  }

  /// RFC 775 and RFC 1144 indent their headings like the body, so the scan for the end of
  /// the front matter never finds a column-0 heading. The text still has to survive.
  @Test func `document without column zero headings keeps its prose`() {
    let text = """
            RFC 99996          A Document With No Column Zero          Page 1


                           A DOCUMENT WITH NO COLUMN ZERO

                             A. Person (person@example)


            As a part of the Remote Site Maintenance project, we have
            expanded the servers on these machines to include commands
            which deal with the creation of directories.

            We have added four commands to our server.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.header.title == "A DOCUMENT WITH NO COLUMN ZERO")
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(paragraphs.count == 2)
    #expect(paragraphs[0].hasPrefix("As a part of the Remote Site Maintenance"))
    #expect(paragraphs[1] == "We have added four commands to our server.")
  }

  /// Most pre-1990 RFCs indent the first line of a paragraph and set the rest at the
  /// left margin (RFC 722, 891, 904). Taking the block's indent from the first line made
  /// every one of those paragraphs artwork.
  @Test func `paragraphs with a first line indent are prose`() {
    let text = """
      Network Working Group                                          A. Person
      Request for Comments: 99995                                  Example Org
      Category: Informational                                     January 2030


                               A Synthetic Test Document

      1.  Introduction

           A model is developed of interactions between programs.
      Salient features of this model which promote and simplify
      the construction of reliable, responsive services are
      identified.

           Using this model as a template, the general
      architecture of one possible interaction protocol is
      presented.
      """
    let document = LegacyTextParser.parse(text)
    let intro = try? #require(document.section(number: "1"))
    let paragraphs = (intro?.blocks ?? []).compactMap { block -> String? in
      if case .paragraph(let paragraph) = block { return paragraph.plainText }
      return nil
    }
    #expect(paragraphs.count == 2)
    #expect(
      paragraphs.first
        == "A model is developed of interactions between programs. Salient features of this model which promote and simplify the construction of reliable, responsive services are identified."
    )
    #expect(
      !(intro?.blocks ?? []).contains { block in
        if case .preformatted = block { return true }
        return false
      })
  }

  /// RFC 817, 813, 888 and about twenty others are typeset double spaced. A blank line
  /// between every pair of lines means no paragraph ever forms and every line stands
  /// alone, so RFC 817 produced 577 sections for 658 lines of text.
  /// RFC 817, 813, 888 and about twenty others are typeset double spaced: a single blank
  /// line is a wrapped line and two or more are the real break. No paragraph ever formed
  /// and every line stood alone, so RFC 817 produced 577 sections for 658 lines of text.
  @Test func `double spaced documents are collapsed`() throws {
    let text = """
      Network Working Group                                          A. Person
      Request for Comments: 99994                                  Example Org
      Category: Informational                                     January 2030


                               A Synthetic Test Document


      1.  Introduction


           Experience suggests that one of the most important factors in

      determining the performance of an implementation is the manner in

      which that implementation is modularized.


           The protocol is not the only thing that matters here.  In fact,

      this document will argue that modularity is one of the chief villains

      in attempting to obtain good performance.


      2.  Efficiency Considerations


           There are many aspects to efficiency.  One aspect is sending

      data at minimum transmission cost, which is a critical aspect of

      common carrier communications, if not in local area networks.


           Another aspect is sending data at a high rate, which may not be

      possible at all if the network is very slow, but which may be the one

      central design constraint.


           A third aspect is the cost of the implementation itself, which

      is paid once by the implementor and then over and over again by

      everyone who has to maintain the result.
      """
    let document = LegacyTextParser.parse(text)
    #expect(document.sections.map(\.number) == ["1", "2"])

    let intro = try #require(document.section(number: "1"))
    let paragraphs = intro.blocks.compactMap { block -> String? in
      if case .paragraph(let paragraph) = block { return paragraph.plainText }
      return nil
    }
    #expect(paragraphs.count == 2)
    #expect(
      paragraphs.first
        == "Experience suggests that one of the most important factors in determining the performance of an implementation is the manner in which that implementation is modularized."
    )
    #expect(intro.blocks.count == 2, "no line survives as its own block")
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

  @Test func `overstrikes and control bytes are removed`() {
    let bold = "T\u{08}Ta\u{08}ab\u{08}bl\u{08}le\u{08}e"
    let underlined = "_\u{08}R_\u{08}F_\u{08}C"
    #expect(LegacyTextParser.removingControlCharacters(bold) == "Table")
    #expect(LegacyTextParser.removingControlCharacters(underlined) == "RFC")
    #expect(LegacyTextParser.removingControlCharacters("a\u{00}\u{1B}b\tc\u{0C}") == "ab\tc\u{0C}")
    #expect(LegacyTextParser.removingControlCharacters("plain") == "plain")
  }
}

extension RFCDocument {
  /// The extractions the assertions here open with. Every one of them is a filter
  /// of the same block list, and written out at each call site the filter -- which
  /// is the part that differs -- is the line you have to read four lines to find.
  ///
  /// The blocks directly in a section, not the nested ones and not the abstract:
  /// what these tests count. `RFCDocument.blocks` is every block (#131).
  var everyBlock: [Block] { allSections.flatMap(\.blocks) }

  /// The unnumbered text before the first heading, which the parser keeps as `preamble`.
  var leadIn: [Block] { sections.first { $0.anchor == "preamble" }?.blocks ?? [] }

  var referenceLists: [ReferenceList] {
    everyBlock.compactMap {
      if case .references(let list) = $0 { return list }
      return nil
    }
  }

  var paragraphs: [Paragraph] {
    everyBlock.compactMap {
      if case .paragraph(let paragraph) = $0 { return paragraph }
      return nil
    }
  }

  /// Every paragraph at any depth: inside list items, definitions, figures, block
  /// quotes and asides as well as directly in a section.
  var nestedParagraphs: [Paragraph] {
    everyBlock.flattened.compactMap {
      if case .paragraph(let paragraph) = $0 { return paragraph }
      return nil
    }
  }

  var artworkText: [String] {
    everyBlock.compactMap {
      if case .preformatted(let art) = $0 { return art.text }
      return nil
    }
  }

  var lists: [ListBlock] {
    everyBlock.compactMap {
      if case .list(let list) = $0 { return list }
      return nil
    }
  }

  /// What the XML declares as an ID: every section's anchor and every bibliography entry's.
  var declaredAnchors: [String] {
    allSections.map(\.anchor) + referenceLists.flatMap(\.entries).map(\.anchor)
  }

  var crossReferences: [CrossReference] {
    paragraphs.flatMap {
      $0.inlines.compactMap {
        if case .crossReference(let xref) = $0 { return xref }
        return nil
      }
    }
  }

  /// Every citation anywhere the linker runs: headings, the abstract, and prose at any
  /// depth -- lists, definitions, tables, quotes, a reference's annotation -- not only
  /// top-level paragraphs.
  var everyCrossReference: [CrossReference] {
    proseInlines.compactMap {
      if case .crossReference(let xref) = $0 { return xref }
      return nil
    }
  }

}
