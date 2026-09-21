import Foundation
import Testing
@testable import RFCKit

@Suite("Legacy text parser")
struct LegacyTextParserTests {
    @Test func stripsPageFurniture() throws {
        let text = try Fixtures.string("rfc2119.txt")
        let stripped = LegacyTextParser.stripPagination(text)
        #expect(!stripped.contains("[Page 1]"))
        #expect(!stripped.contains("RFC 2119                     RFC Key Words"))
        #expect(!stripped.contains("\u{0C}"))
        #expect(stripped.contains("Request for Comments: 2119"), "the first-page header block is content, not furniture")
        #expect(stripped.contains("6. Guidance in the use of these Imperatives"))
    }

    @Test func frontMatter() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
        #expect(document.source == .text)
        #expect(document.header.id == .rfc(1149))
        #expect(document.header.title == "A Standard for the Transmission of IP Datagrams on Avian Carriers")
        #expect(document.header.authors == [Author(name: "D. Waitzman")])
        #expect(document.header.date == PublicationDate(year: 1990, month: 4))

        let abnf = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
        #expect(abnf.header.id == .rfc(5234))
        #expect(abnf.header.title == "Augmented BNF for Syntax Specifications: ABNF")
        #expect(abnf.header.obsoletes == [.rfc(4234)])
        #expect(abnf.header.category == "Standards Track")
        #expect(abnf.header.authors == [Author(name: "D. Crocker", role: "Editor"), Author(name: "P. Overell")])
        #expect(abnf.header.date == PublicationDate(year: 2008, month: 1))
    }

    @Test func unnumberedHeadings() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
        let titles = document.sections.map(\.title)
        #expect(titles == ["Overview and Rational", "Frame Format", "Discussion", "Security Considerations", "Author's Address"])
        #expect(document.header.abstract.isEmpty, "RFC 1149 has no abstract")
        #expect(document.sections.allSatisfy { $0.number == nil })
    }

    @Test func abstractMovesToHeader() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc2119.txt"))
        #expect(!document.sections.contains { $0.title == "Abstract" })
        #expect(!document.sections.contains { $0.title.hasPrefix("Status of") })
        guard case .paragraph(let paragraph)? = document.header.abstract.first else {
            Issue.record("abstract missing")
            return
        }
        #expect(paragraph.plainText.hasPrefix("In many standards track documents"))
    }

    @Test func paragraphsSplitAcrossPagesAreRejoined() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
        let discussion = try #require(document.sections.first { $0.title == "Discussion" })
        let paragraphs = discussion.blocks.compactMap { block -> String? in
            if case .paragraph(let paragraph) = block { return paragraph.plainText }
            return nil
        }
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].contains("the carriers are self-regenerating."), "hyphenated word rejoined across the page break")
        #expect(paragraphs[0].hasSuffix("cable trays."))
    }

    @Test func numberedSectionsNest() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
        #expect(document.sections.map(\.number) == ["1", "2", "3", "4", "5", "6", "A", "B", nil])
        #expect(document.sections.last?.title == "Authors' Addresses")
        let operators = try #require(document.section(number: "3"))
        #expect(operators.subsections.count == 10)
        #expect(operators.subsections.last?.title == "Operator Precedence")
        #expect(document.section(number: "2.3")?.title == "Terminal Values")
        #expect(document.section(number: "3.1")?.title == "Concatenation: Rule1 Rule2")
        let appendixB = try #require(document.section(number: "B"))
        #expect(appendixB.isAppendix)
        #expect(appendixB.subsections.map(\.number) == ["B.1", "B.2"])
        #expect(!document.sections.contains { $0.title == "Table of Contents" })
    }

    @Test func proseVersusArtwork() throws {
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
        #expect(artworks.contains { $0.contains("CR          =  %d13") }, "column alignment inside artwork is preserved")

        let grammar = try #require(document.section(number: "4"))
        let artwork = grammar.blocks.compactMap { block -> Preformatted? in
            if case .preformatted(let value) = block { return value }
            return nil
        }
        #expect(artwork.contains { $0.text.contains("rulelist       =  1*( rule / (*c-wsp c-nl) )") })
    }

    @Test func listsAreDetected() throws {
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

    @Test func referencesAndLinks() throws {
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
        #expect(xrefs.contains { $0.target == .anchor("ref-US-ASCII") && $0.text == "[US-ASCII]" })
        #expect(document.referencedDocuments.contains(.rfc(822)))
    }

    @Test func inlineLinkingRules() {
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
        #expect(targets == [
            .document(.rfc(2119), section: nil),
            .document(.rfc(8174), section: nil),
            .document(.rfc(9110), section: "4.2"),
            .anchor("section-2"),
        ])
        #expect(paragraph.inlines.contains { inline in
            if case .link(let url, _) = inline { return url.absoluteString == "https://example.com/spec" }
            return false
        })
        #expect(paragraph.plainText.contains("Nothing in Section 9 exists."))
    }
}

@Suite("Legacy text parser: corpus findings")
struct LegacyTextCorpusFindingsTests {
    /// Shapes found in the first full corpus run (September 2026).
    @Test func columnZeroTitleAndAnchorOnlyReferences() {
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
        #expect(document.header.title == "Protocol for Carrying Authentication for Network Access (PANA) Framework")
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
    @Test func unindentedBodyDoesNotTurnEveryLineIntoAHeading() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc1245.txt"))
        #expect(document.header.id == .rfc(1245))
        #expect(document.header.title == "OSPF protocol analysis")

        #expect(document.allSections.count < 40, "got \(document.allSections.count) sections")
        #expect(document.section(number: "1.0")?.title == "Introduction")
        #expect(document.section(number: "3.1")?.title == "Operational data")
        #expect(document.section(number: "6.0")?.title == "Reference Documents")
        #expect(document.sections.contains { $0.title == "Author's Address" })

        // Lines from the middle of a paragraph must not become sections.
        let titles = document.allSections.map(\.title)
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

    /// The stricter rule applies only to documents whose body is not indented: where the
    /// body *is* indented, a heading followed immediately by text is still a heading.
    @Test func indentedBodyStillAcceptsHeadingsWithoutABlankLineAfter() {
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
        #expect(document.sections.map(\.title) == ["Introduction", "Security Considerations"])
    }

    /// A tab is indentation too: the contents listing of RFC 1142 is tab-indented, and
    /// every entry matched the numbered-heading pattern.
    @Test func tabIndentedLinesAreNotHeadings() {
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
        #expect(document.sections.map(\.title) == ["Contents", "Scope and Field of Application"])
    }

    /// RFC 775 and RFC 1144 indent their headings like the body, so the scan for the end of
    /// the front matter never finds a column-0 heading. The text still has to survive.
    @Test func documentWithoutColumnZeroHeadingsKeepsItsProse() {
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
        let paragraphs = document.allSections.flatMap(\.blocks).compactMap { block -> String? in
            if case .paragraph(let paragraph) = block { return paragraph.plainText }
            return nil
        }
        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].hasPrefix("As a part of the Remote Site Maintenance"))
        #expect(paragraphs[1] == "We have added four commands to our server.")
    }

    /// Most pre-1990 RFCs indent the first line of a paragraph and set the rest at the
    /// left margin (RFC 722, 891, 904). Taking the block's indent from the first line made
    /// every one of those paragraphs artwork.
    @Test func paragraphsWithAFirstLineIndentAreProse() {
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
        #expect(paragraphs.first == "A model is developed of interactions between programs. Salient features of this model which promote and simplify the construction of reliable, responsive services are identified.")
        #expect(!(intro?.blocks ?? []).contains { block in
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
    @Test func doubleSpacedDocumentsAreCollapsed() throws {
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
        #expect(paragraphs.first == "Experience suggests that one of the most important factors in determining the performance of an implementation is the manner in which that implementation is modularized.")
        #expect(intro.blocks.count == 2, "no line survives as its own block")
    }

    /// RFC 757 is typeset justified: every line is padded with extra spaces between words
    /// to reach a common right margin. Those runs of spaces are what tells prose from
    /// artwork everywhere else, so all 60-odd of its paragraphs were preformatted blocks.
    @Test func justifiedProseIsNotArtwork() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc757.txt"))
        #expect(document.header.title == "A Suggested Solution to the Naming, Addressing, and Delivery Problem for ARPAnet Message Systems")

        var paragraphs = 0
        var artwork = 0
        for block in document.allSections.flatMap(\.blocks) {
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
        #expect(first.plainText == "The current ARPAnet message handling scheme has evolved from rather informal, decentralized beginnings. Early developers took advantage of pre-existing tools -- TECO, FTP -- in order to implement their first systems. Later, protocols were developed to codify the conventions already in use. While these conventions have been able to support an amazing variety and amount of service, they have a number of shortcomings.")
    }

    @Test func overstrikesAndControlBytesAreRemoved() {
        let bold = "T\u{08}Ta\u{08}ab\u{08}bl\u{08}le\u{08}e"
        let underlined = "_\u{08}R_\u{08}F_\u{08}C"
        #expect(LegacyTextParser.removingControlCharacters(bold) == "Table")
        #expect(LegacyTextParser.removingControlCharacters(underlined) == "RFC")
        #expect(LegacyTextParser.removingControlCharacters("a\u{00}\u{1B}b\tc\u{0C}") == "ab\tc\u{0C}")
        #expect(LegacyTextParser.removingControlCharacters("plain") == "plain")
    }
}
