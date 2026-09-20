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

    @Test func overstrikesAndControlBytesAreRemoved() {
        let bold = "T\u{08}Ta\u{08}ab\u{08}bl\u{08}le\u{08}e"
        let underlined = "_\u{08}R_\u{08}F_\u{08}C"
        #expect(LegacyTextParser.removingControlCharacters(bold) == "Table")
        #expect(LegacyTextParser.removingControlCharacters(underlined) == "RFC")
        #expect(LegacyTextParser.removingControlCharacters("a\u{00}\u{1B}b\tc\u{0C}") == "ab\tc\u{0C}")
        #expect(LegacyTextParser.removingControlCharacters("plain") == "plain")
    }
}
