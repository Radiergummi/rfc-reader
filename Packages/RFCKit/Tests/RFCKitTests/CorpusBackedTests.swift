import Foundation
import Testing

@testable import RFCKit

// Findings about what the parser makes of a whole document, over documents read from
// a fetched corpus rather than committed as fixtures (`CorpusText`). `make
// test-corpus` fetches them and runs these; everywhere else they are skipped. The
// guards these findings led to are tested over a few lines each, beside the other
// corpus findings; these check that the whole document still comes out that way.

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
    guard case .paragraph(let sentence)? = blocks.first,
      case .list(let list)? = blocks.dropFirst().first
    else {
      Issue.record("expected the sentence and then its list")
      return
    }
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
    guard case .list(let list)? = blocks.dropFirst(sentence + 1).first else {
      Issue.record("expected the list of packet types after the sentence")
      return
    }
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
}

@Suite("Corpus-backed: catalogues", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedCatalogueTests {
  private func catalogues(in document: RFCDocument) -> [[DefinitionItem]] {
    document.everyBlock.compactMap {
      if case .definitionList(let items) = $0 { return items }
      return nil
    }
  }

  /// RFC 1012's index of RFCs is a thousand `NN  - Author, "Title", ...` entries,
  /// each hung past its number. They were artwork, every reference in them unlinked;
  /// they are one catalogue now, numbered as the document numbers them (#204).
  @Test func `the RFC index of RFC 1012 is a catalogue`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1012"))
    let entries = try #require(catalogues(in: document).max { $0.count < $1.count })
    #expect(entries.count > 900)
    #expect(entries.first?.term.plainText == "1")
    #expect(
      document.artworkText.allSatisfy { !$0.contains("  - Crocker, Steve") },
      "no entry is left as artwork")
  }

  /// The standards summaries set a new RFC's number and title on one line and its
  /// description under it. The title was a paragraph and the description artwork;
  /// the description is the entry's second paragraph now.
  @Test func `an entry's indented description joins the entry`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2300"))
    let entry = try #require(
      catalogues(in: document).flatMap { $0 }.first { $0.term.plainText == "2352" })
    #expect(entry.definition.count == 2)
  }

  /// Most of those descriptions are a short phrase in title case (`A Draft Standard
  /// protocol.`), which the sentence test a list item's continuation asks refuses.
  /// Kept as artwork, each one ended the catalogue above it, and the summary came
  /// out as one list per entry or two.
  @Test func `a short description does not break the catalogue`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc2300"))
    let lists = catalogues(in: document)
    #expect(lists.count < 20, "\(lists.count) catalogues")
    #expect(document.artworkText.allSatisfy { $0 != "A Draft Standard protocol." })
  }

  /// RFC 793 sets a legend under each sequence-space diagram, one line to an entry,
  /// and centres the figure's captions under it. A caption is not the last entry's
  /// second paragraph.
  @Test func `a caption centered under a legend stays out of it`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc793"))
    let entries = catalogues(in: document).flatMap { $0 }
    #expect(!entries.isEmpty)
    #expect(entries.allSatisfy { $0.definition.count == 1 }, "an entry took a second paragraph")
  }

  /// RFC 1140 right-aligns its numbers, so `996` stands a column deeper than `1006`,
  /// its text in the same column. One catalogue still.
  @Test func `right-aligned numbers stay one catalogue`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc1140"))
    let holding996 = try #require(
      catalogues(in: document).first { $0.contains { $0.term.plainText == "996" } })
    #expect(holding996.contains { $0.term.plainText == "1006" })
  }

  /// RFC 206 sets three error-code tables one after another, each under its own
  /// caption. They are three catalogues, not one that runs its numbering again.
  @Test func `tables under their own captions are separate catalogues`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc206"))
    for entries in catalogues(in: document) {
      let terms = entries.compactMap { Int($0.term.plainText) }
      #expect(terms == terms.sorted(), "a catalogue restarts its numbering: \(terms)")
      #expect(entries.allSatisfy { $0.definition.count == 1 })
    }
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

  /// A refused line can continue a block rather than start one: RFC 7231's contents
  /// has an entry wrapped to column 0 in the middle of a block. The omitted contents end
  /// at that line, as they did when it was a heading, and the lines of its block
  /// before it are the contents' still.
  @Test func `a refused line inside a block ends the boilerplate at that line`() throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc7231"))
    let text = document.paragraphs.map(\.plainText) + document.artworkText
    #expect(!text.contains { $0.contains("Payment Required ....") })
    #expect(text.contains { $0.contains("Origination Date ....") })
  }
}
