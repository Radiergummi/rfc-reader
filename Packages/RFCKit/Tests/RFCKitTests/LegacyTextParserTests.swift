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
        let titles = document.sections.map(\.titleText)
        #expect(titles == ["Overview and Rational", "Frame Format", "Discussion", "Security Considerations", "Author's Address"])
        #expect(document.header.abstract.isEmpty, "RFC 1149 has no abstract")
        #expect(document.sections.allSatisfy { $0.number == nil })
    }

    @Test func abstractMovesToHeader() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc2119.txt"))
        #expect(!document.sections.contains { $0.titleText == "Abstract" })
        #expect(!document.sections.contains { $0.titleText.hasPrefix("Status of") })
        guard case .paragraph(let paragraph)? = document.header.abstract.first else {
            Issue.record("abstract missing")
            return
        }
        #expect(paragraph.plainText.hasPrefix("In many standards track documents"))
    }

    @Test func paragraphsSplitAcrossPagesAreRejoined() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc1149.txt"))
        let discussion = try #require(document.sections.first { $0.titleText == "Discussion" })
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

    /// `[RFC 2211]` and `[RFC2582,FF96,Hoe96]` used to match neither pattern: the
    /// bracket pattern's anchor admitted no space or comma, and the bare pattern
    /// discarded anything a `[` preceded. Between them they dropped 1,606 of the
    /// 1,640 unlinked RFC mentions left in the corpus's prose.
    @Test func bracketedRFCMentionsLinkWhateverTheirSpacing() {
        let text = """
        Network Working Group                                          A. Person
        Request for Comments: 99999                                  Example Org
        Category: Informational                                     January 2030


                                 A Synthetic Test Document

        1. Introduction

           One [RFC 2211] and two [RFC1234], then [RFC2582,FF96,Hoe96] and
           [RFC 1277], [RFC 1777]. Not [Page 3] and not [16].

        2. Details

           Details here.
        """
        let document = LegacyTextParser.parse(text)
        guard case .paragraph(let paragraph)? = document.sections[0].blocks.first else {
            Issue.record("expected paragraph")
            return
        }
        let xrefs = paragraph.inlines.compactMap { inline -> CrossReference? in
            if case .crossReference(let xref) = inline { return xref }
            return nil
        }
        #expect(xrefs.map(\.target) == [
            .document(.rfc(2211), section: nil),
            .document(.rfc(1234), section: nil),
            .document(.rfc(2582), section: nil),
            .document(.rfc(1277), section: nil),
            .document(.rfc(1777), section: nil),
        ])
        // A bracket the series spells itself composes back, whichever side of the
        // space the RFC Editor set it on.
        #expect(xrefs.allSatisfy { $0.text == nil }, "every one of these is the series' own spelling")
        // The brackets of a multi-anchor citation are not ours to eat: the tags
        // beside the RFC stay exactly as they were set.
        #expect(paragraph.plainText.contains("[RFC\u{00A0}2582,FF96,Hoe96]"))
        // `[Page 3]` parses as no document and `[16]` is a numbered citation, not RFC 16.
        #expect(paragraph.plainText.contains("Not [Page 3] and not [16]."))
    }

    @Test func legacyBracketedRFCLabelsAreFlaggedAsCanonical() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
        let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }
        // Measured over 1,200 corpus documents before this rule was fixed: 12,612
        // references, 253 of them chips. The rest were exactly this case.
        let canonical = try #require(xrefs.first { xref in
            guard case .document(let id, _) = xref.target, id.series == .rfc else { return false }
            return xref.isCanonicalLabel
        }, "without this, 98% of the library shows no chips")
        #expect(canonical.text == nil)
        #expect(canonical.label.hasPrefix("[RFC"))
        let authored = try #require(xrefs.first { $0.text == "[US-ASCII]" })
        #expect(!authored.isCanonicalLabel, "an author's own tag must survive verbatim")
    }
}

@Suite("Legacy text parser: corpus findings")
struct LegacyTextCorpusFindingsTests {
    /// Two more spellings the linker was blind to, both common in the older half of
    /// the series: `RFC-1156`, and a list written once as `RFCs 734, 736 and 749`.
    /// Measured on the corpus, prose held 2,223 of the first and 659 of the second,
    /// against 1,640 of the plain `RFC 1156` the linker already knew.
    @Test func hyphenatedAndPluralMentionsLink() {
        let text = """
        Network Working Group                                          A. Person
        Request for Comments: 99999                                  Example Org
        Category: Informational                                     January 2030


                                 A Synthetic Test Document

        1. Introduction

           Same status as RFC-1156, see also RFCs 734, 736 and 749. Host
           Requirements ([RFC-1122, RFC-1123]) take precedence.

        2. Details

           Details here.
        """
        let document = LegacyTextParser.parse(text)
        guard case .paragraph(let paragraph)? = document.sections[0].blocks.first else {
            Issue.record("expected paragraph")
            return
        }
        let xrefs = paragraph.inlines.compactMap { inline -> CrossReference? in
            if case .crossReference(let xref) = inline { return xref }
            return nil
        }
        #expect(xrefs.map(\.target) == [
            .document(.rfc(1156), section: nil),
            .document(.rfc(734), section: nil),
            .document(.rfc(736), section: nil),
            .document(.rfc(749), section: nil),
            .document(.rfc(1122), section: nil),
            .document(.rfc(1123), section: nil),
        ])
        // The hyphen is the author's, not ours: `isCanonicalTag` does not count it as
        // the series' own spelling, so the words stay exactly as they were set, here
        // and inside the bracket, and neither is restyled into a chip.
        #expect(xrefs[0].text == "RFC-1156")
        #expect(xrefs[4].text == "RFC-1122")
        // A number in a list reads as the list wrote it -- composing "RFC 736" over
        // the top of "RFCs 734, 736" would say RFC twice.
        #expect(xrefs[1].text == "734")
        #expect(paragraph.plainText.contains("see also RFCs 734, 736 and 749."))
        #expect(paragraph.plainText.contains("Same status as RFC-1156,"))
    }

    /// The reference list sets its anchors the way the prose cites them, and a
    /// seventh of the corpus puts a space in: `[RFC 2119]`. `referenceStartPattern`
    /// admitted no whitespace in an anchor, so those lines started no entry and were
    /// swallowed as continuation text of whatever came before -- RFC 2290 and RFC
    /// 2535 produced no bibliography at all. 782 entries across 205 documents.
    @Test func referenceAnchorsMayHoldSpaces() {
        let text = """
        Network Working Group                                          A. Person
        Request for Comments: 99999                                  Example Org
        Category: Informational                                     January 2030


                                 A Synthetic Test Document

        1. Introduction

           See [RFC 2119] and [Cheswick and Bellovin, 1994].

        2. References

           [RFC 2119]  Bradner, S., "Key words for use in RFCs to Indicate
                       Requirement Levels", BCP 14, RFC 2119, March 1997.

           [RFC2616]   Fielding, R., "Hypertext Transfer Protocol", RFC 2616,
                       June 1999.

           [Cheswick and Bellovin, 1994]  Cheswick, W. and S. Bellovin,
                       "Firewalls and Internet Security", 1994.

           [Page 12]

           [This RFC was put into machine readable form for entry into the
                       online archives]
        """
        let document = LegacyTextParser.parse(text)
        guard case .references(let list)? = document.section(number: "2")?.blocks.first else {
            Issue.record("expected a reference list")
            return
        }
        #expect(list.entries.map(\.anchor) == ["RFC 2119", "RFC2616", "Cheswick and Bellovin, 1994"])
        #expect(list.entries[0].documentID == .rfc(2119))
        #expect(list.entries[0].title == "Key words for use in RFCs to Indicate Requirement Levels")
        #expect(list.entries[2].title == "Firewalls and Internet Security")

        // A citation in the prose finds the entry it names, spaces and all.
        guard case .paragraph(let intro)? = document.sections[0].blocks.first else {
            Issue.record("expected a paragraph")
            return
        }
        let targets = intro.inlines.compactMap { inline -> CrossReference.Target? in
            if case .crossReference(let xref) = inline { return xref.target }
            return nil
        }
        #expect(targets.first == .document(.rfc(2119), section: nil))
    }

    /// `Section.title` was a `String`, so a heading that named a document -- 3,471
    /// of them across the corpus, "Changes from RFC 3066" among them -- could not
    /// carry the link even in principle.
    @Test func headingsCarryTheirCrossReferences() {
        let text = """
        Network Working Group                                          A. Person
        Request for Comments: 99999                                  Example Org
        Category: Informational                                     January 2030


                                 A Synthetic Test Document

        1. Introduction

           Body text.

        8. Changes from RFC 3066

           More body text.
        """
        let document = LegacyTextParser.parse(text)
        let changes = document.section(number: "8")
        #expect(changes?.titleText == "Changes from RFC\u{00A0}3066")
        #expect(changes?.displayTitle == "8. Changes from RFC\u{00A0}3066")
        let targets = (changes?.title ?? []).compactMap { inline -> CrossReference.Target? in
            if case .crossReference(let xref) = inline { return xref.target }
            return nil
        }
        #expect(targets == [.document(.rfc(3066), section: nil)])
        // The number belongs to the section, not to the words, so the reader composes
        // it around whatever the heading links to.
        #expect(changes?.displayTitleInlines.first.map { inline in
            if case .text(let text) = inline { return text == "8. " }
            return false
        } == true)
    }

    /// A hanging list whose items carry continuation paragraphs -- the shape RFC
    /// 3712 sets its Introduction in. Each paragraph arrives as its own block,
    /// indented past the marker and carrying no marker of its own, so it used to
    /// fail `looksLikeProse`'s indent guard and be preserved as artwork. Artwork is
    /// never linkified, which is how `[RFC3066]` came to sit unlinked in an
    /// introduction, and the list was shredded into one single-item list per item.
    @Test func listContinuationParagraphsStayProse() {
        let text = """
        Network Working Group                                          A. Person
        Request for Comments: 99999                                  Example Org
        Category: Informational                                     January 2030


                                 A Synthetic Test Document

        1. Introduction

           These are defined in this document:

           1)  URI
               - printer-uri, printer-xri-supported

               The UTF-8 encoding is forward compatible with any future
               deployment of IRI currently being developed.

           2)  Description
               - printer-name, printer-location

               The UTF-8 encoding supports descriptions in any language,
               conformant with the policy in [RFC2277].

               Note:  The attribute contains a language tag [RFC3066] for
               these description attributes.

           3)  Convert

               c = OS2IP (C).

           4)  URI

               The UTF-8 encoding is forward compatible with any future
               deployment of (UTF-8 based) IRI (Internationalized Resource
               Identifiers) [W3C-IRI] currently being developed by the W3C
               Internationalization Working Group.

        2. Details

           Details here.
        """
        let document = LegacyTextParser.parse(text)
        let blocks = document.sections[0].blocks
        guard case .list(let list)? = blocks.first(where: { if case .list = $0 { return true }; return false }) else {
            Issue.record("expected the items to end up in one list, got \(blocks.map(\.self.kindName))")
            return
        }
        #expect(list.items.count == 3, "the items belong to one list, not one list each")
        #expect(list.items[1].blocks.count == 3, "the item keeps its continuation paragraphs")
        // An algorithm step is not prose because a list happens to sit above it. The
        // indent is excused; every other test of prose still has to pass, and a line
        // of identifiers and operators fails `readsLikeSentences` as it always did.
        #expect(list.items[2].blocks.count == 1, "pseudocode under an item is not swallowed into it")
        // The artwork between them is a block like any other, so it ends the list the
        // way it always did; item 4 opens a new one.
        #expect(blocks.map(\.kindName) == ["paragraph", "list", "preformatted", "list"])
        guard case .list(let resumed) = blocks[3] else {
            Issue.record("expected the fourth item to open a list of its own")
            return
        }
        // RFC 3712's own paragraph, which is the reason the bar is a half and not
        // three fifths: acronyms and bracketed tags hold it to 0.56 ordinary words,
        // and at three fifths the document that prompted all of this stayed broken.
        #expect(resumed.items[0].blocks.count == 2, "acronym-heavy prose is still prose")
        #expect(blocks.contains { if case .preformatted(let art) = $0 { return art.text.contains("OS2IP") }; return false },
                "it stays artwork")

        let xrefs = list.items[1].blocks.flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }
        #expect(xrefs.map(\.target) == [
            .document(.rfc(2277), section: nil),
            .document(.rfc(3066), section: nil),
        ])
    }

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
        #expect(document.sections.map(\.titleText) == ["Introduction", "Security Considerations"])
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
        #expect(document.sections.map(\.titleText) == ["Contents", "Scope and Field of Application"])
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
        // swiftlint:disable:next line_length - one reflowed paragraph, asserted whole
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
        // swiftlint:disable:next line_length - one reflowed paragraph, asserted whole
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
        // swiftlint:disable:next line_length - one reflowed paragraph, asserted whole
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

extension Block {
    /// A short name for a block, for test failure messages only.
    var kindName: String {
        switch self {
        case .paragraph: "paragraph"
        case .list: "list"
        case .definitionList: "definitionList"
        case .preformatted: "preformatted"
        case .figure: "figure"
        case .table: "table"
        case .blockQuote: "blockQuote"
        case .aside: "aside"
        case .references: "references"
        }
    }
}
