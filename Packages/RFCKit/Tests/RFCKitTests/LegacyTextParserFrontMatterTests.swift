import Foundation
import Testing

@testable import RFCKit

/// The title page: the header block, the title, the lead-in and the boilerplate.
@Suite("Legacy text parser: front matter")
struct LegacyTextParserFrontMatterTests {
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
    #expect(abnf.header.category == .standardsTrack)
    #expect(
      abnf.header.authors == [
        Author(name: "D. Crocker", role: .editor), Author(name: "P. Overell"),
      ])
    #expect(abnf.header.date == PublicationDate(year: 2008, month: 1))
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
  /// 1441's centered `Status of this Memo` and its paragraph, and its contents. The
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
  /// neither was left in the body. The catalogs -- RFC 1292, 1632, 2116 -- give every
  /// entry one, and lost each entry's to the header the same way (#72).
  @Test func `only the first abstract is the documents`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2371.txt"))
    let abstract = document.header.abstract.compactMap(\.paragraph?.plainText)
    #expect(
      abstract.first?.hasPrefix("In many applications where different nodes cooperate") == true)
    #expect(
      document.paragraphs.contains { $0.plainText.hasPrefix("TMP provides a simple mechanism") })
    #expect(
      !document.paragraphs.contains {
        $0.plainText.hasPrefix("In many applications where different nodes cooperate")
      })
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
}
