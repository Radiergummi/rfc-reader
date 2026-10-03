import Foundation
import Testing

@testable import RFCKit

// Findings about what the parser makes of a whole document, over documents read from
// a fetched corpus rather than committed as fixtures (`CorpusText`). `make
// test-corpus` fetches them and runs these; everywhere else they are skipped. The
// guards these findings led to are tested over a few lines each, in the suite of the
// parser stage they belong to; these check that the whole document still comes out
// that way.

/// The text of every block of the document's lead-in, a list's items included, so a
/// finding about what leaves the lead-in holds whatever kind of block it would be.
private func leadInText(_ document: RFCDocument) -> [String] {
  func text(_ block: Block) -> String {
    switch block {
    case .paragraph(let paragraph): paragraph.plainText
    case .preformatted(let artwork): artwork.text
    case .list(let list):
      list.items.flatMap(\.blocks).map(text).joined(separator: "\n")
    default: ""
    }
  }
  return document.leadIn.map(text)
}

@Suite("Corpus-backed: the prose cap", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedProseCapTests {
  /// The prose cap was six columns everywhere: a body at column 3, plus three. RFC 1178
  /// sets its headings at 6 and its body at 9, so every paragraph it has failed the cap
  /// and was kept as artwork, and none of it was linked (#55). The cap follows the
  /// body now, and nothing in the document is artwork.
  @Test func `a body set deeper than column three is still prose`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1178"))
    #expect(document.artworkText.isEmpty, "\(document.artworkText.count) blocks kept as artwork")
    #expect(document.paragraphs.contains { $0.plainText.contains("semantic implications") })
  }
}

@Suite("Corpus-backed: page joins", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedPageJoinTests {
  /// RFC 1581's `it is assumed that:` ends a page, the list under it starts the next,
  /// and its first item was read into the sentence as `that: o The most recently ...`.
  @Test func `a bullet at the top of a page is not the rest of a sentence`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1581"))
    let blocks = try #require(document.section(number: "3.3")).blocks
    let sentence = try #require(blocks.first?.paragraph, "expected the sentence and then its list")
    let list = try #require(
      blocks.dropFirst().first?.list, "expected the sentence and then its list")
    #expect(sentence.plainText.hasSuffix("assumed that:"))
    #expect(list.items.count == 2)
  }

  /// RFC 6614's `For example, they send` ends a page, and its list of packet types,
  /// which starts the next, was read into it as `they send o Access-Request ...`.
  @Test func `a bullet after an unfinished sentence is not its rest`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc6614"))
    let blocks = try #require(document.section(number: "2.5")).blocks
    let sentence = try #require(
      blocks.firstIndex {
        guard case .paragraph(let paragraph) = $0 else { return false }
        return paragraph.plainText.hasSuffix("they send")
      })
    let list = try #require(
      blocks.dropFirst(sentence + 1).first?.list,
      "expected the list of packet types after the sentence")
    let items = list.items.compactMap { item -> String? in
      guard case .paragraph(let text)? = item.blocks.first else { return nil }
      return text.plainText
    }
    #expect(items.starts(with: ["Access-Request", "Accounting-Request", "Status-Server"]))
  }
}

@Suite("Corpus-backed: the title page", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedTitlePageTests {
  /// Since the front matter ends at the first paragraph (#74), whatever the title page
  /// leaves between it and the body reaches the lead-in, and is taken out of it by what
  /// it is (#76): RFC 674's header block, under its journal stamp, and the page number
  /// after its title; RFC 1441's centered `Status of this Memo` and its paragraph, and
  /// its contents. The body after them stays.
  @Test func `the title pages leftovers are not the lead in`() throws {
    let procedureCall = leadInText(LegacyTextParser.parse(try CorpusText.text("rfc674")))
    #expect(!procedureCall.contains { $0.contains("Request for Comments 674") })
    #expect(!procedureCall.contains("1"))
    #expect(procedureCall.first?.hasPrefix("Procedure Call Protocol Documents") == true)
    #expect(procedureCall.contains { $0.hasPrefix("As many of you") }, "the body after them stays")

    let management = leadInText(LegacyTextParser.parse(try CorpusText.text("rfc1441")))
    #expect(!management.contains { $0.localizedCaseInsensitiveContains("status of this memo") })
    #expect(!management.contains { $0.contains("specifes") }, "nor the status paragraph")
    #expect(!management.contains { $0.contains("Table of Contents") || $0.contains("......") })
    #expect(management.contains { $0.hasPrefix("The purpose of") }, "the body after them stays")
  }

  /// What the title page leaves in the lead-in, `parse` drops unread (#76), so the
  /// report does not diagnose it either: RFC 1441's centered status paragraph and its
  /// contents listing are refused by the prose test, and were counted as its refusals.
  @Test func `the title pages leftovers are not diagnosed`() throws {
    let leadIn = LegacyTextParser.proseDiagnostics(for: try CorpusText.text("rfc1441"))
      .filter { $0.section.isEmpty }.map(\.firstLine)
    #expect(!leadIn.contains("Status of this Memo"))
    #expect(!leadIn.contains { $0.hasPrefix("1 Introduction .....") })
    #expect(
      leadIn.first?.hasPrefix("1.  Introduction") == true,
      "neither the status paragraph nor the contents is diagnosed before it")
  }

  /// A title page sets a long title over several runs of lines, and the front matter
  /// takes one of them for the title. Given the title the RFC index has, the parser uses
  /// it, and the run the front matter left behind leaves the lead-in: RFC 1343's
  /// `For Multimedia Mail Format Information` opened the body as artwork (#170).
  @Test func `the index title replaces a partial one and the rest leaves the lead in`() throws {
    let title = "A User Agent Configuration Mechanism for Multimedia Mail Format Information"
    let text = try CorpusText.text("rfc1343")
    #expect(LegacyTextParser.parse(text).header.title == "A User Agent Configuration Mechanism")

    let document = LegacyTextParser.parse(text, title: title)
    #expect(document.header.title == title)
    #expect(!leadInText(document).contains { $0.contains("For Multimedia Mail") })
  }

  /// A date alone on a line is the title page's, like the author above it: RFC 355's
  /// `June 9, 1972` was the lead-in's second block (#170).
  @Test func `a date alone on a line is the title pages`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc355"))
    #expect(!leadInText(document).contains { $0.contains("June 9, 1972") })
  }

  /// A title the index and the title page both set in capitals is title-cased (#219),
  /// where the front matter took another line and only the title page's runs repeat
  /// the index's: RFC 822 sets its title over two of them under a header, and RFC 169
  /// under a workshop's name.
  @Test func `a title in capitals on the title page and in the index is title cased`() throws {
    let format = LegacyTextParser.parse(
      try CorpusText.text("rfc822"),
      title: "STANDARD FOR THE FORMAT OF ARPA INTERNET TEXT MESSAGES")
    #expect(format.header.title == "Standard for the Format of ARPA Internet Text Messages")

    let networks = LegacyTextParser.parse(
      try CorpusText.text("rfc169"), title: "COMPUTER NETWORKS")
    #expect(networks.header.title == "Computer Networks")
  }
}

@Suite("Corpus-backed: appendix headings", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedAppendixHeadingTests {
  /// RFC 2326 heads its appendices `Appendix A: Title`, as about 150 legacy RFCs do.
  /// They were unnumbered sections titled with the whole line; they are appendices
  /// now, lettered, with the title alone (#200).
  @Test func `an appendix headed with a colon is an appendix`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2326"))
    let appendix = try #require(document.section(anchor: "appendix-A"))
    #expect(appendix.number == "A")
    #expect(!appendix.titleText.hasPrefix("Appendix"))
    #expect(document.section(anchor: "appendix-B") != nil)
    #expect(document.section(anchor: "appendix-C") != nil)
  }

  /// RFC 8011 names its status codes as lettered subsections, `B.1.4.1.  ` and a code
  /// in lower case. The appendix pattern wanted a capital after the number, and they
  /// were unnumbered sections beside their parents, titled with the whole line. They
  /// are appendices now, each under the one its number is under (#201).
  @Test func `a lettered subsection nests under its appendix`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc8011"))
    let appendix = try #require(document.section(anchor: "appendix-B"))
    let values = try #require(appendix.subsections.first { $0.number == "B.1" })
    let clientErrors = try #require(values.subsections.first { $0.number == "B.1.4" })
    let code = try #require(clientErrors.subsections.first { $0.number == "B.1.4.1" })
    #expect(code.isAppendix)
    #expect(code.anchor == "appendix-B.1.4.1")
    #expect(code.titleText.hasPrefix("client-error-"))
  }

  /// RFC 1043 numbers its appendices `APPENDIX 1` and `APPENDIX 2`, and has no section
  /// 2 heading of its own. Its prose cites `Section 2`, which named no section and must
  /// not link to one: an appendix's number is not a section's.
  @Test func `a section citation does not link to an appendix's number`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1043"))
    #expect(document.section(anchor: "appendix-2") != nil)
    let targets = document.everyCrossReference.compactMap { reference -> String? in
      if case .anchor(let anchor) = reference.target { return anchor }
      return nil
    }
    #expect(!targets.contains("section-2"))
  }

  /// A contents entry with a short spaced leader (RFC 5735) or a page number in a
  /// column of its own (RFC 1276) took its appendix's anchor, and the appendix was
  /// renamed `appendix-A-2`, so a link to Appendix A opened the contents (#427).
  @Test(arguments: ["rfc5735", "rfc1276"])
  func `an appendix keeps its anchor from its contents entry`(stem: String) throws {
    let document = LegacyTextParser.parse(try CorpusText.text(stem))
    #expect(document.allSections.count { $0.isAppendix && $0.number == "A" } == 1)
    #expect(document.section(anchor: "appendix-A") != nil)
    #expect(document.section(anchor: "appendix-A-2") == nil)
  }

  /// RFC 707 sets its body's headings with a page number at the margin, as a contents
  /// entry is set without a leader. Each stands between paragraphs, so each is a
  /// heading: the four appendices are there, and the references.
  @Test func `a heading with its page number at the margin is no contents entry`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc707"))
    for (letter, word) in [("A", "DATA"), ("B", "TRANSMISSION"), ("C", "ENCODING"), ("D", "LOOK")] {
      #expect(
        document.allSections.contains {
          $0.isAppendix && $0.number == letter && $0.titleText.contains(word)
        })
    }
    #expect(document.allSections.contains { $0.titleText.hasPrefix("REFERENCES") })
  }
}

@Suite("Corpus-backed: catalogs", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedCatalogTests {
  /// RFC 1012's index of RFCs is a thousand `NN  - Author, "Title", ...` entries,
  /// each hung past its number. They were artwork, every reference in them unlinked;
  /// they are one catalog now, numbered as the document numbers them (#204).
  @Test func `the RFC index of RFC 1012 is a catalog`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1012"))
    let entries = try #require(document.definitionLists.max { $0.count < $1.count })
    #expect(entries.count > 900)
    #expect(entries.first?.term.plainText == "1")
    #expect(
      document.artworkText.allSatisfy { !$0.contains("  - Crocker, Steve") },
      "no entry is left as artwork")
  }

  /// Its entries stand a blank line apart, so each arrives as a block of its own and
  /// is merged into the catalog above; the merged catalog is still compact, and hangs
  /// its numbers, so a thousand entries are not set at twice their height (#352).
  @Test func `the RFC index of RFC 1012 is compact and hangs its numbers`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1012"))
    let catalog = try #require(
      document.everyBlock.compactMap(\.definitionList).max { $0.items.count < $1.items.count })
    #expect(catalog.isCompact)
    #expect(catalog.hangsTerms)
  }

  /// The standards summaries set a new RFC's number and title on one line and its
  /// description under it. The title was a paragraph and the description artwork;
  /// the description is the entry's second paragraph now.
  @Test func `an entry's indented description joins the entry`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2300"))
    let entry = try #require(
      document.definitionLists.flatMap { $0 }.first { $0.term.plainText == "2352" })
    #expect(entry.definition.count == 2)
  }

  /// Most of those descriptions are a short phrase in title case (`A Draft Standard
  /// protocol.`), which the sentence test a list item's continuation asks refuses.
  /// Kept as artwork, each one ended the catalog above it, and the summary came
  /// out as one list per entry or two.
  @Test func `a short description does not break the catalog`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2300"))
    let lists = document.definitionLists
    #expect(lists.count < 20, "\(lists.count) catalogs")
    #expect(document.artworkText.allSatisfy { $0 != "A Draft Standard protocol." })
  }

  /// RFC 793 sets a legend under each sequence-space diagram, one line to an entry,
  /// and centers the figure's captions under it. A caption is not the last entry's
  /// second paragraph.
  @Test func `a caption centered under a legend stays out of it`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc793"))
    let entries = document.definitionLists.flatMap { $0 }
    #expect(!entries.isEmpty)
    #expect(entries.allSatisfy { $0.definition.count == 1 }, "an entry took a second paragraph")
  }

  /// RFC 1140 right-aligns its numbers, so `996` stands a column deeper than `1006`,
  /// its text in the same column. One catalog still.
  @Test func `right-aligned numbers stay one catalog`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1140"))
    let holding996 = try #require(
      document.definitionLists.first { $0.contains { $0.term.plainText == "996" } })
    #expect(holding996.contains { $0.term.plainText == "1006" })
  }

  /// RFC 206 sets three error-code tables one after another, each under its own
  /// caption. They are three catalogs, not one that runs its numbering again.
  @Test func `tables under their own captions are separate catalogs`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc206"))
    for entries in document.definitionLists {
      let terms = entries.compactMap { Int($0.term.plainText) }
      #expect(terms == terms.sorted(), "a catalog restarts its numbering: \(terms)")
      #expect(entries.allSatisfy { $0.definition.count == 1 })
    }
  }
}

@Suite("Corpus-backed: hanging-indent definitions", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedHangingDefinitionTests {
  /// RFC 6186 sets each SRV service label as xml2rfc sets a `<dl>` entry: the label,
  /// two spaces, and its description hung three columns in. Each was artwork (#436).
  @Test func `a hanging-indent entry is a definition, not artwork`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc6186"))
    let terms = document.definitionLists.flatMap { $0 }.map(\.term.plainText)
    #expect(terms.contains("submission:"))
    #expect(terms.contains("_imap:"))
    #expect(document.artworkText.allSatisfy { !$0.hasPrefix("submission:") })
  }

  /// A page break in RFC 5545 cuts the first parameter's `Description:` in the
  /// middle of a sentence. The prose test that rejoins a paragraph's halves refuses
  /// a hanging one, so the rest was the definition's second paragraph.
  @Test func `a definition cut by a page break is one paragraph`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc5545"))
    let description = try #require(
      document.definitionLists.flatMap { $0 }.first { $0.term.plainText == "Description:" })
    #expect(description.definition.count == 1)
    #expect(description.definition.first?.paragraph?.plainText.contains("quoted-string") == true)
  }

  /// RFC 6614's terminology aligns each definition under its own text, and sets
  /// the first, one line long, above the two that hang. One list of three.
  @Test func `a one-line entry joins the hanging entries beside it`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc6614"))
    let list = try #require(
      document.definitionLists.first {
        $0.contains { $0.term.plainText == "RADIUS/TLS Client:" }
      })
    #expect(
      list.map(\.term.plainText) == [
        "RADIUS/TLS node:", "RADIUS/TLS Client:", "RADIUS/TLS Server:",
      ])
  }
}

@Suite("Corpus-backed: references sections", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedReferencesSectionTests {
  /// The first section of that title with anything in it: RFC 2196's contents
  /// listing leaves an empty `9. References` of its own ahead of the real one.
  private static func section(titled title: String, in stem: String) throws -> Section {
    let document = LegacyTextParser.parse(try CorpusText.text(stem))
    return try #require(
      document.firstSection { $0.title.plainText == title && !$0.blocks.isEmpty })
  }

  private static func holdsEntries(_ block: Block) -> Bool {
    if case .references(let list) = block { return !list.entries.isEmpty }
    return false
  }

  /// RFC 1958 opens its references with a note on why there are only two, and RFC
  /// 2196 with a warning that some may be hard to find. A references section kept
  /// only its entries, so what came before the first one was dropped (74 documents).
  @Test func `the text before the first entry is kept`() throws {
    for (stem, opening) in [
      ("rfc1958", "Note that the"),
      ("rfc2196", "The following references"),
    ] {
      let references = try Self.section(titled: "References", in: stem)
      guard case .paragraph(let first)? = references.blocks.first else {
        Issue.record(
          "\(stem) opens its references with \(String(describing: references.blocks.first))")
        continue
      }
      #expect(first.plainText.hasPrefix(opening), "\(stem)")
      #expect(references.blocks.contains(where: Self.holdsEntries), "\(stem) lost its entries")
    }
  }

  /// RFC 6186's `Priority for Domain Preferences` has `references` inside
  /// `preferences`, and was read as a bibliography from its first bracketed line.
  @Test func `a heading that says preferences is not a bibliography`() throws {
    let section = try Self.section(titled: "Priority for Domain Preferences", in: "rfc6186")
    #expect(!section.blocks.contains { if case .references = $0 { true } else { false } })
    #expect(
      section.blocks.contains {
        guard case .paragraph(let paragraph) = $0 else { return false }
        return paragraph.plainText.hasPrefix("The priority field")
      })
  }

  private static func holdsList(_ section: Section) -> Bool {
    section.blocks.contains(where: holdsEntries)
  }

  /// A plain references title is a bibliography whatever the parser makes of it: RFC
  /// 1716's and 2315's read as one entry each, beside text before it.
  @Test func `a plain references title stays a bibliography`() throws {
    for (stem, number) in [("rfc1716", "11"), ("rfc2315", "2")] {
      let document = LegacyTextParser.parse(try CorpusText.text(stem))
      let section = try #require(document.section(number: number), "\(stem)")
      #expect(Self.holdsList(section), "\(stem) \(number)")
    }
  }

  /// A section that only mentions references is not a bibliography: RFC 7322's
  /// advice on writing one, RFC 4511's continuation references, RFC 3275's example
  /// with references in parentheses. Each was read as one, its text taken for an
  /// entry's and its subsections lost in the XML (#686).
  @Test func `a section that mentions references keeps its text`() throws {
    for (stem, number) in [("rfc7322", "4.8.6"), ("rfc4511", "4.5.3"), ("rfc3275", "2.1")] {
      let document = LegacyTextParser.parse(try CorpusText.text(stem))
      let section = try #require(document.section(number: number), "\(stem)")
      #expect(!Self.holdsList(section), "\(stem) \(number)")
      #expect(
        section.blocks.contains { if case .paragraph = $0 { true } else { false } },
        "\(stem) \(number) has no prose")
      #expect(!section.subsections.isEmpty, "\(stem) \(number) lost its subsections")
    }
  }

  /// A bibliography adopts no section that is not one: RFC 2814's appendix has no
  /// heading of its own, so its `A.1` was numbered under `9. References`, and RFC
  /// 2639 numbers its authors' addresses under its references (#686).
  @Test func `a bibliography holds no section that is not one`() throws {
    for stem in ["rfc1195", "rfc2639", "rfc2814"] {
      let document = LegacyTextParser.parse(try CorpusText.text(stem))
      let bibliographies = document.allSections.filter(Self.holdsList)
      #expect(!bibliographies.isEmpty, "\(stem) has no bibliography")
      for bibliography in bibliographies {
        #expect(
          bibliography.subsections.allSatisfy(RFCXMLSerializer.isReferences),
          "\(stem) \(bibliography.anchor)")
      }
    }
  }

  /// What the app reads is what it would write (#683), for the documents whose
  /// bibliographies held what `<references>` cannot (#686).
  @Test func `the documents a misread bibliography broke survive a round trip`() throws {
    let serializer = RFCXMLSerializer()
    for stem in ["rfc1195", "rfc2639", "rfc2814", "rfc3075", "rfc3275", "rfc4511", "rfc7322"] {
      let xml = serializer.serialize(LegacyTextParser.parse(try CorpusText.text(stem)))
      let again = serializer.serialize(try RFCXMLParser.parse(Data(xml.utf8)))
      #expect(again == xml, "\(stem)")
    }
  }
}

@Suite("Corpus-backed: body layouts", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedBodyLayoutTests {
  /// RFC 5193 sets its title at column 0 under a header block whose right-hand
  /// column runs on past the left one. Shapes found in the first full corpus run
  /// (September 2026).
  @Test func `a title at column zero is the title`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc5193"))
    #expect(document.header.id == .rfc(5193))
    #expect(
      document.header.title
        == "Protocol for Carrying Authentication for Network Access (PANA) Framework")
    #expect(document.header.date == PublicationDate(year: 2008, month: 5))
  }

  /// A tab is indentation too: the contents listing of RFC 1142 is tab-indented, and
  /// every entry matched the numbered-heading pattern.
  @Test func `tab indented contents entries are not headings`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1142"))
    let scope = document.allSections.filter { $0.titleText == "Scope and Field of Application" }
    #expect(scope.map(\.number) == ["1"])
  }

  /// RFC 775 indents its headings like its body, so the scan for the end of the front
  /// matter never finds a column-0 heading. The text still has to survive.
  @Test func `a document without column zero headings keeps its prose`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc775"))
    #expect(document.header.title == "DIRECTORY ORIENTED FTP COMMANDS")
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(paragraphs.contains { $0.contains("Remote Site Maintenance") })
    #expect(paragraphs.contains { $0.hasSuffix("to our server:") })
  }

  /// Most pre-1990 RFCs indent the first line of a paragraph and set the rest at the
  /// left margin (RFC 722, 891, 904). Taking the block's indent from the first line made
  /// every one of those paragraphs artwork.
  @Test func `paragraphs with a first line indent are prose`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc722"))
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(paragraphs.contains { $0.hasPrefix("A model is developed") })
    #expect(!document.artworkText.contains { $0.contains("Using this model") })
  }

  /// RFC 817 is typeset double spaced: a single blank line is a wrapped line and two
  /// or more are the real break. No paragraph ever formed and every line stood alone,
  /// so it produced 577 sections for 658 lines of text.
  @Test func `a double spaced document is collapsed`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc817"))
    #expect(document.allSections.count < 20, "\(document.allSections.count) sections")
    let paragraphs = document.paragraphs.map(\.plainText)
    let experience = try #require(paragraphs.first { $0.hasPrefix("Experience suggests") })
    #expect(experience.hasSuffix("the operating system."))
  }
}

@Suite("Corpus-backed: ABNF", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedABNFTests {
  /// Every preformatted block of the document, the lead-in's included.
  private static func preformatted(_ stem: String) throws -> [Preformatted] {
    let document = LegacyTextParser.parse(try CorpusText.text(stem))
    return (document.leadIn.flattened + document.blocks).compactMap { block in
      guard case .preformatted(let preformatted) = block else { return nil }
      return preformatted
    }
  }

  /// RFC 1415 lists directory entries, and RFC 707 and RFC 708 lay out messages, in
  /// lines that parse as ABNF but assign one name twice with nothing else a grammar
  /// has (#45). They stay artwork.
  @Test(arguments: [
    ("rfc1415", "CommonName"), ("rfc707", "message-type="), ("rfc708", "message-type="),
  ])
  func `a listing that assigns one name twice stays artwork`(stem: String, marker: String) throws {
    let blocks = try Self.preformatted(stem).filter { $0.text.contains(marker) }
    #expect(!blocks.isEmpty)
    #expect(blocks.allSatisfy { $0.kind == .artwork }, "\(stem)")
  }

  /// RFC 2326, RFC 2569 and RFC 2910 each define one rule name twice where `=/` or
  /// another name was meant; their repetitions and numeric values say they are
  /// grammars all the same.
  @Test(arguments: [
    ("rfc2326", "utc-time"), ("rfc2569", "job-number"), ("rfc2910", "delimiter-tag"),
  ])
  func `a grammar that defines one name twice is still ABNF`(stem: String, rule: String) throws {
    let blocks = try Self.preformatted(stem).filter { $0.text.contains(rule) }
    #expect(blocks.contains { $0.kind == .sourceCode && $0.type == "abnf" }, "\(stem)")
  }

  /// RFC 1122 and RFC 6654 set legends as `name = what it names`, where the first word
  /// of what it names is the name again. A rule referring to itself refers to no other
  /// rule, so the legend is no grammar, and stays artwork.
  @Test(arguments: [("rfc1122", "remote = remote"), ("rfc6654", "Host = IPv6")])
  func `a legend naming itself stays artwork`(stem: String, marker: String) throws {
    let blocks = try Self.preformatted(stem).filter { $0.text.contains(marker) }
    #expect(!blocks.isEmpty)
    #expect(blocks.allSatisfy { $0.kind == .artwork }, "\(stem)")
  }
}

@Suite("Corpus-backed: unnumbered headings", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedUnnumberedHeadingTests {
  /// The front matter ends at the first line that could be a heading, and that test is
  /// kept lax: refusing prose there as the body does ran RFC 783's front matter on past
  /// its summary, set at column 0 under a centered `Summary`, and lost it (#201). The
  /// summary stays in the lead-in.
  @Test func `a summary at column 0 is not swallowed into the front matter`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc783"))
    #expect(leadInText(document).contains { $0.contains("its name comes") })
  }
}

@Suite("Corpus-backed: omitted boilerplate", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedOmittedBoilerplateTests {
  /// An omitted section, such as `Status of this Memo`, runs to the next heading. A
  /// column-0 line refused as a heading used to end it all the same, and when it was
  /// refused as prose what follows went with the boilerplate: RFC 1198's list of the
  /// X Consortium's standards, under a sentence at column 0 (#201). It ends there
  /// still, and the list is the body's.
  @Test func `a sentence refused as a heading still ends omitted boilerplate`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1198"))
    let text = document.paragraphs.map(\.plainText) + document.artworkText
    #expect(text.contains { $0.contains("Bitmap Distribution Format") })
    #expect(!document.allSections.contains { $0.titleText.hasPrefix("The following documents") })
  }

  /// A refused line can continue a block rather than start one: RFC 2223 quotes a
  /// `Status of this Memo` in its nroff source, and the sentence under it starts at
  /// column 0 two lines into a block of requests. The omitted status ends at that line,
  /// as it did when it was a heading, and the lines of its block before it are the
  /// status's still.
  @Test func `a refused line inside a block ends the boilerplate at that line`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2223"))
    let text = document.paragraphs.map(\.plainText) + document.artworkText
    #expect(text.contains { $0.hasPrefix("This memo") && $0.contains("avian carriers") })
    #expect(!text.contains { $0.hasPrefix(".fi") && $0.contains("avian carriers") })
  }

  /// A contents entry takes no heading's place, so it ends no omitted contents: RFC
  /// 7231's has one wrapped to column 0 behind a stray `ed` in the middle of a block,
  /// which ended the contents there and put the rest of them in the body (#403).
  @Test func `a contents entry at column zero does not end the contents`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc7231"))
    let text = document.paragraphs.map(\.plainText) + document.artworkText
    #expect(!text.contains { $0.contains("Payment Required ....") })
    #expect(!text.contains { $0.contains("Origination Date ....") })
  }
}

@Suite("Corpus-backed: page furniture", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedPageFurnitureTests {
  /// RFC 798 heads each of its chapters itself, `III.` at column 0, and runs the
  /// same words at the head of the chapter's later pages. The first of those copies
  /// was kept, because the document-wide check read only a heading numbered in
  /// digits (#57): each chapter's name stood twice, the second time as a stray
  /// block. Answered on the pages around the copy now (#291), the chapter is named
  /// once.
  @Test(arguments: ["Encoding Algorithm", "the Data Header"])
  func `a chapter headed by the document is not named again by its running header`(
    words: String
  ) throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc798"))
    #expect(document.allSections.count { $0.titleText.contains(words) } == 1)
    #expect(!document.artworkText.contains { $0.contains(words) })
  }
}

@Suite("Corpus-backed: packet diagrams", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedPacketDiagramTests {
  /// RFC 791's IPv4 header, as the parser hands it over: every field, with its
  /// width, the three-bit Flags included.
  @Test func `the IPv4 header in RFC 791 is recognized with every field`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc791"))
    let artwork = try #require(
      document.blocks.lazy.compactMap { block -> String? in
        guard case .preformatted(let content) = block, content.text.contains("Total Length")
        else { return nil }
        return content.text
      }.first)
    let diagram = try #require(PacketDiagram.recognize(artwork))
    #expect(
      diagram.fields.map(\.name) == [
        "Version", "IHL", "Type of Service", "Total Length", "Identification", "Flags",
        "Fragment Offset", "Time to Live", "Protocol", "Header Checksum", "Source Address",
        "Destination Address", "Options", "Padding",
      ])
    #expect(diagram.fields.map(\.bitWidth) == [4, 4, 8, 16, 16, 3, 13, 8, 8, 16, 32, 32, 24, 8])
  }
}

@Suite("Corpus-backed: defined terms", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedDefinedTermsTests {
  /// RFC 9110 marks a definition with a primary index entry in the paragraph that
  /// gives it, and a status code's with one directly in its section (#176).
  @Test func `a primary index entry defines its term where the document does`() throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml("rfc9110"))
    let upstream = try #require(document.definedTerms["upstream"])
    #expect(upstream.anchor == "section-3.7-4")
    #expect(upstream.definition.count == 1)
    let status = try #require(document.definedTerms["100 Continue (status code)"])
    #expect(status.anchor == "status.100")
    #expect(status.definition.isEmpty, "an entry directly in a section has no one block")
  }

  /// RFC 9114 marks `connection error` in its section and defines it in its
  /// terminology list: the term lands on the list item, with its definition.
  @Test func `a definition list entry supplies an index entry's definition`() throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml("rfc9114"))
    for (term, anchor) in [
      ("connection error", "section-2.2-4.7"), ("stream error", "section-2.2-4.25"),
    ] {
      let defined = try #require(document.definedTerms[term])
      #expect(defined.anchor == anchor, "\(term)")
      #expect(!defined.definition.isEmpty, "\(term)")
    }
  }
}

@Suite("Corpus-backed: citations", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedCitationsTests {
  /// RFC 9393 lists BCP 26 and BCP 178 as groups and cites each only through its
  /// member, RFC 8126 and RFC 6648: the prose cites the group's entry, so the
  /// bibliography adds no row for it (#174).
  @Test func `a group cited through its member is not cited from the bibliography`() throws {
    let citations = Citations.of(try RFCXMLParser.parse(try CorpusText.xml("rfc9393")))
    #expect(citations.contains { $0.cited == .rfc(8126) && $0.place != .bibliography })
    #expect(citations.contains { $0.cited == .rfc(6648) && $0.place != .bibliography })
    let bibliography = citations.filter { $0.place == .bibliography }.map(\.cited)
    #expect(!bibliography.contains(DocumentID(series: .bcp, number: 26)))
    #expect(!bibliography.contains(DocumentID(series: .bcp, number: 178)))
  }
}

/// What a converted citation points at: its entry's document, read from outside the
/// entry's title, and the entry itself, kept through the XML (#424).
@Suite("Corpus-backed: bibliography entries", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedBibliographyEntryTests {
  /// RFC 8259 cites RFC 8174, whose title is about the keywords of RFC 2119, and lists
  /// an erratum of RFC 7159 ahead of RFC 7159's own entry.
  @Test func `a citation keeps its entry and its document through the XML`() throws {
    let parsed = LegacyTextParser.parse(try CorpusText.text("rfc8259"))
    let entries = parsed.referenceLists.flatMap(\.entries)
    #expect(entries.first { $0.anchor == "RFC8174" }?.documentID == .rfc(8174))

    let converted = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(parsed).utf8))
    let targets = converted.everyCrossReference.map(\.target)
    #expect(targets.contains(.document(.rfc(8174), section: nil, entry: "RFC8174")))
    #expect(!targets.contains(.document(.rfc(2119), section: nil, entry: "RFC8174")))
    // Each citation, paired with its conversion: one that resolved to an entry keeps
    // it, and a bare "RFC 7159", which records none, converts to RFC 7159's own entry
    // rather than the erratum listed ahead of it.
    let citations = parsed.everyCrossReference.map(\.target)
    try #require(citations.count == targets.count)
    #expect(citations.contains(.document(.rfc(7159), section: nil, entry: "Err3915")))
    #expect(citations.contains(.document(.rfc(7159), section: nil, entry: nil)))
    for (citation, conversion) in zip(citations, targets) {
      switch citation {
      case .document(.rfc(7159), let section, nil):
        #expect(conversion == .document(.rfc(7159), section: section, entry: "RFC7159"))
      case .document(_, _, .some):
        #expect(conversion == citation)
      default:
        continue
      }
    }
  }
}

@Suite("Corpus-backed: joined artwork", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedJoinedArtworkTests {
  /// RFC 793's state diagram has blank lines in it, and came out as a block per
  /// stretch between them (#437).
  @Test func `a drawing with blank lines in it is one artwork`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc793"))
    #expect(document.artworkText.contains { $0.contains("LISTEN") && $0.contains("TIME WAIT") })
  }

  /// RFC 3407's attribute registrations are one-line definitions a blank line
  /// apart, which a hanging list below takes back as the blocks they made; joined
  /// as artwork, they were left out of it.
  @Test func `one-line definitions a blank line apart are still a list`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc3407"))
    let terms = document.definitionLists.flatMap { $0 }.map(\.term.plainText)
    #expect(terms.filter { $0.hasPrefix("Attribute name") }.count >= 3)
    #expect(!document.artworkText.contains { $0.contains("Attribute name") })
  }
}
