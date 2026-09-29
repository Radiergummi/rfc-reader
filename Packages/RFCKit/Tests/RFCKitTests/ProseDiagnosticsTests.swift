import Foundation
import Testing

@testable import RFCKit

@Suite("Prose diagnostics")
struct ProseDiagnosticsTests {
  // MARK: A block that passes

  @Test func `plain prose passes every guard`() {
    let lines = [
      "   The key words in this document are to be interpreted as",
      "   described in the relevant specification, and carry their",
      "   ordinary meaning elsewhere.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.isProse)
    #expect(diagnosis.rejections.isEmpty)
    #expect(diagnosis.indent == 3)
    #expect(diagnosis.firstLineIndent == 0)
  }

  // MARK: Each guard reports itself, and reports its margin

  /// The margin matters as much as the verdict: #43 samples blocks that miss by a
  /// little, and an indent of 7 is a different proposition from an indent of 20.
  @Test func `indent too deep carries the indent that failed`() {
    let lines = [
      "       An example paragraph set well past the body margin, which the",
      "       parser treats as preformatted for that reason alone.",
      "       It reads like ordinary prose in every other respect.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections == [.indentTooDeep])
    #expect(diagnosis.indent == 7, "one column past the limit, which is what makes it a near miss")
  }

  /// Past the classic cap of six, a document whose body sits deeper excuses the indent
  /// (#55) -- for sentences only. The same document sets its one-line code at that
  /// depth, and a single line has no other guard to keep it artwork. Refused within
  /// the cap, it is refused for what it says rather than for its indent, and the
  /// report names that apart: an indent of 9 is not too deep in such a document.
  @Test func `a deeper cap excuses sentences but not code`() {
    let sentences = [
      "         Using a word that has strong semantic implications in the",
      "         current context will cause confusion.",
    ]
    #expect(LegacyTextParser.diagnose(sentences).rejections == [.indentTooDeep])
    #expect(LegacyTextParser.diagnose(sentences, maxIndent: 12).isProse)

    let code = ["         ::= { ifMauEntry 4 }"]
    #expect(LegacyTextParser.diagnose(code, maxIndent: 12).rejections == [.deepIndentNotSentences])
    #expect(LegacyTextParser.diagnose(code, maxIndent: 6).rejections == [.indentTooDeep])
  }

  /// Nor does it excuse a MIB module's text, which is sentences where it is a
  /// `DESCRIPTION` or a comment: a block with an assignment in it, or a comment of
  /// several lines. A list marked with dashes is not one.
  @Test func `a deeper cap does not excuse a modules text`() {
    let comment = [
      "         -- The peer table.  This table holds one entry for each",
      "         -- peer, with what is known about the connection to it.",
    ]
    let clauseEnd = [
      "         This object is kept only for compatibility with older agents.\"",
      "         ::= { exampleObjects 1 }",
    ]
    for lines in [comment, clauseEnd] {
      #expect(
        LegacyTextParser.diagnose(lines, maxIndent: 12).rejections
          == [.deepIndentNotSentences],
        "\(lines[0])")
    }

    let dashedItem = [
      "         -- The \"print\" field names a program that prints a body part",
      "         in the given format, as the view command displays it.",
    ]
    #expect(LegacyTextParser.diagnose(dashedItem, maxIndent: 12).isProse)
    #expect(
      LegacyTextParser.diagnose(
        ["         -- only when the message could not be delivered"], maxIndent: 12
      )
      .isProse)
  }

  // MARK: The document's prose cap

  /// The cap is three columns past the body, which is the indent a quarter of the
  /// document's sentences sit at or left of (#55). A MIB module's `DESCRIPTION` clauses
  /// are sentences too, and where the module is most of the document they outnumber
  /// the body enough to carry the quarter into the module: the cap rose with it, and
  /// the module's text became paragraphs. A clause's quoted string is not counted.
  @Test func `the prose cap follows the body and not a module`() {
    let body = [
      "   This memo defines a portion of the management information base for",
      "   use with the network management protocols in the community.",
    ]
    let clause = [
      "                    DESCRIPTION",
      "                       \"The number of packets that were received on this",
      "                       interface and discarded because they were found",
      "                       to be malformed in some way, as the counter says.",
      "                       This counter is maintained by every interface",
      "                       which supports the module as it is described.\"",
      "                    ::= { exampleEntry 4 }",
    ]
    let module = Array(repeating: clause, count: 3).flatMap { $0 }
    #expect(LegacyTextParser.proseIndent(body + module) == 6)
    #expect(
      LegacyTextParser.proseIndent(body + module.filter { !$0.contains("DESCRIPTION") }) == 26,
      "counted as the body's, the clauses would set the cap")

    let deeperBody = [
      "      1.  Introduction",
      "",
      "         A host name is chosen once and then kept for as long as the",
      "         machine is in service, so it is worth choosing with some care.",
    ]
    #expect(LegacyTextParser.proseIndent(deeperBody) == 12)
    #expect(
      LegacyTextParser.proseIndent(["      DESCRIPTION \"The local system number.\""] + deeperBody)
        == 12,
      "a clause closed on its own line leaves the lines after it counted")
  }

  @Test func `first line indent out of range is distinct from indent`() {
    let lines = [
      "                The opening line is set far too deep relative to the body",
      "   of the paragraph, which sits at the ordinary margin.",
      "   So the block is rejected on its first line, not on its indent.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections == [.firstLineIndentOutOfRange])
    #expect(diagnosis.indent == 3)
    #expect(diagnosis.firstLineIndent == 13)
  }

  @Test func `ragged indent is reported separately`() {
    // The block's indent comes from its *second* line, so the ragged line has to be
    // the third: a ragged second line reads as a first-line indent instead.
    let lines = [
      "   A paragraph whose second line returns to the same margin as",
      "   the first, but whose third does not, is not a paragraph this",
      "      parser accepts, however sentence-like its words may be.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections == [.raggedIndent])
  }

  /// The case #43 exists to find: prose rejected on a single incidental match.
  @Test func `one arrow rejects an otherwise ordinary paragraph`() {
    let lines = [
      "   The client moves to the established state, and the transition",
      "   from open -> closed is described in the following section of",
      "   this document at some length.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections == [.artworkPattern])
    #expect(
      diagnosis.artworkMatches == 1,
      "a single incidental match, against every other signal agreeing")
    #expect(diagnosis.isNearMiss)
    #expect(diagnosis.sentenceRatio > 0.6)
  }

  @Test func `artwork matches are counted not just detected`() {
    let lines = [
      "   +--------+      +--------+",
      "   | Client | ---> | Server |",
      "   +--------+      +--------+",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections.contains(.artworkPattern))
    #expect(
      diagnosis.artworkMatches > 1, "real artwork matches repeatedly; incidental prose matches once"
    )
    #expect(!diagnosis.isNearMiss)
  }

  // MARK: Justification, tell by tell

  /// Asserting the five tells inside a filter on `agreed` would be vacuous — `agreed`
  /// *is* their conjunction. What is worth pinning is the consequence: agreeing tells
  /// are what excuse a justified block's padding from the internal-gap guard.
  @Test func `justified prose is excused the internal gap guard`() throws {
    let text = try Fixtures.string("rfc757.txt")
    let blocks = LegacyTextParser.proseDiagnostics(for: text)
    let justified = blocks.filter { $0.diagnosis.justification.agreed }
    #expect(!justified.isEmpty, "RFC 757 is one of the justified-typeset documents")
    for block in justified {
      #expect(!block.diagnosis.rejections.contains(.internalGap))
    }
  }

  @Test func `a failed tell is named`() {
    // A common right margin and spread padding, but a gutter running through it:
    // a two-column layout, not justified prose.
    let lines = [
      "   Name                                  Value                   ",
      "   Another                               Something else          ",
      "   Third                                 A third value           ",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(!diagnosis.justification.agreed)
    #expect(!diagnosis.justification.noColumnGutter, "the gutter is what disqualifies it")
  }

  // MARK: The diagnostic pipeline must see what the parse pipeline sees

  /// Both entry points share one block segmentation, so the diagnosis covers every
  /// block the parser saw. Classification merges adjacent lists and drops blocks that
  /// linkify to nothing, so it may end with fewer — never with more, and never with
  /// none at all.
  @Test(arguments: ["rfc2119.txt", "rfc1149.txt", "rfc757.txt", "rfc1245.txt"])
  func `every classified block is also diagnosed`(fixture: String) throws {
    let text = try Fixtures.string(fixture)
    let diagnosed = LegacyTextParser.proseDiagnostics(for: text)
    let classified = Self.blockCount(LegacyTextParser.parse(text).sections)

    #expect(classified > 0)
    #expect(
      diagnosed.count >= classified,
      "classification never invents a block the segmentation did not produce")
  }

  private static func blockCount(_ sections: [Section]) -> Int {
    sections.reduce(0) { $0 + $1.blocks.count + blockCount($1.subsections) }
  }

  /// What the title page leaves in the lead-in, `parse` drops unread (#76), so the
  /// report does not diagnose it either: RFC 1441's centred status paragraph and its
  /// contents listing are refused by the prose test, and were counted as its refusals.
  /// RFC 757's phone number is the whole of its lead-in, and the report has none.
  @Test func `the title pages leftovers are not diagnosed`() throws {
    let leadIn = LegacyTextParser.proseDiagnostics(for: try Fixtures.string("rfc757.txt"))
      .filter { $0.section.isEmpty }
    #expect(leadIn.isEmpty, "\(leadIn.map(\.firstLine))")
  }

  /// Whatever title `parse` is handed, the report is handed too, because the lead-in
  /// loses the blocks that repeat it: a report given only the page's title diagnoses
  /// blocks the parser dropped. The title here is made up to be one RFC 873's
  /// `Bedford, Massachusetts` line repeats; the page sets its own in capitals, so the
  /// given one is the title `parse` uses.
  @Test func `the report filters the lead in by the title parse is given`() throws {
    let text = try Fixtures.string("rfc873.txt")
    let title = "The Illusion of Vendor Support, Bedford, Massachusetts"
    let leadIn = { (title: String?) in
      LegacyTextParser.proseDiagnostics(for: text, title: title)
        .filter { $0.section.isEmpty }.map(\.firstLine)
    }

    #expect(LegacyTextParser.parse(text, title: title).header.title == title)
    #expect(leadIn(nil).contains("Bedford, Massachusetts"))
    #expect(!leadIn(title).contains("Bedford, Massachusetts"))
  }

  /// `classify` offers a block to the list parser before it asks the prose test, so a
  /// list item's prose verdict was never actually taken. A hanging marker outdents the
  /// first line, so these fail `firstLineIndentOutOfRange` almost without exception —
  /// and counting that as a failure of the prose test would misreport the parser.
  @Test func `list items are marked as never reaching the prose test`() throws {
    let blocks = LegacyTextParser.proseDiagnostics(for: try Fixtures.string("rfc1245.txt"))
    let lists = blocks.filter(\.claimedByList)
    #expect(!lists.isEmpty, "RFC 1245 is full of bulleted lists")

    let outdented = lists.filter { $0.diagnosis.firstLineIndent < 0 }
    #expect(
      !outdented.isEmpty, "the hanging marker is exactly what makes these look like rejected prose")
    #expect(
      outdented.allSatisfy { $0.diagnosis.rejections.contains(.firstLineIndentOutOfRange) },
      "these carry a rejection that a report must not count, which is why the flag exists"
    )
  }

  /// The parse path takes the short-circuiting route, the report takes the full one.
  /// They must never disagree on the verdict — the guards are a conjunction of absolute
  /// vetoes, so stopping at the first one cannot change the answer, and this is what
  /// says so for every block of four real documents rather than in a comment.
  @Test(arguments: ["rfc2119.txt", "rfc1149.txt", "rfc757.txt", "rfc1245.txt", "rfc5234.txt"])
  func `short circuiting agrees with the full diagnosis`(fixture: String) throws {
    // Any group of lines will do — the invariant is a property of `diagnose`, not of
    // the parser's segmentation — so this splits the document at blank lines and gets
    // far more varied inputs than the blocks alone.
    var checked = 0
    for group in try Fixtures.string(fixture).components(separatedBy: "\n\n") {
      let lines = group.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard !lines.isEmpty else { continue }
      #expect(
        LegacyTextParser.diagnose(lines, thorough: false).isProse
          == LegacyTextParser.diagnose(lines, thorough: true).isProse,
        "disagreed on: \(lines.first ?? "")"
      )
      checked += 1
    }
    #expect(checked > 10)
  }

  @Test func `every block carries enough to find it again`() throws {
    let blocks = LegacyTextParser.proseDiagnostics(for: try Fixtures.string("rfc2119.txt"))
    let sample = try #require(blocks.first { $0.diagnosis.isProse })
    #expect(!sample.firstLine.isEmpty)
    #expect(sample.lineCount > 0)
    #expect(sample.firstLine.count <= 80, "truncated for a report, not a second copy of the corpus")
  }

  @Test func `rejections are recorded in evaluation order`() {
    let lines = ["          +-+-+-+-+", "          | A | B |", "          +-+-+-+-+"]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections.first == .indentTooDeep, "indent is tested before content")
    #expect(diagnosis.rejections.contains(.artworkPattern))
  }

  @Test func `empty input is rejected without crashing`() {
    let diagnosis = LegacyTextParser.diagnose([])
    #expect(diagnosis.rejections == [.noLines])
  }

  // MARK: The byte scans answer what the regexes answer

  /// The prose test asks `artworkPattern` and `internalGapPattern` of every line through
  /// a byte scan, because the regexes were half of `parse`. Each scan has to answer
  /// exactly what its regex would, over every line of every fixture and over the shapes
  /// the scans treat specially: the gap's punctuation rule, runs at the trimmed edges,
  /// `\r\n`, and lines that are not ASCII.
  @Test func `the byte scans agree with the regexes`() throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    var lines = [
      "a.   b", "a    b", "a   b", "a  \tb", "    four leading", "x\u{0B}\u{0C} y",
      "1  2", "1 2", "1\t\t2", "x|", "| x", "x |", "a\r\n\r\nb", "1\r\n 2",
      "café   au lait", "α +- β", "\u{00A0}\u{00A0}\u{00A0}x", "...", "....", "==", "===", "--",
      "---",
      "<-", "->", "-+", "+-", "/_", "\\_", "_/", "_\\", "", "   ", "\t",
    ]
    for fixture in try FileManager.default.contentsOfDirectory(atPath: directory.path)
    where fixture.hasSuffix(".txt") {
      lines += try Fixtures.string(fixture).components(separatedBy: "\n")
    }
    for line in lines {
      let content = line.trimmingCharacters(in: .whitespaces)
      #expect(
        LegacyTextParser.containsArtwork(line) == content.contains(LegacyTextParser.artworkPattern),
        "\(line.debugDescription)")
      #expect(
        LegacyTextParser.hasInternalGap(line)
          == content.contains(LegacyTextParser.internalGapPattern), "\(line.debugDescription)")
    }
  }

  // MARK: Where a block is (#43)

  /// A block's line range in the source, so a sample of blocks can name them without
  /// copying their text. Through the page furniture and the lead-in: every block's
  /// first line is the source line it points at.
  @Test(arguments: ["rfc2119.txt", "rfc793.txt", "rfc757.txt", "rfc1245.txt"])
  func `every diagnosed block points at its own lines in the source`(fixture: String) throws {
    let text = try Fixtures.string(fixture)
    let source = text.replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0).replacingOccurrences(of: "\u{0C}", with: "").expandingTabs() }
    let blocks = LegacyTextParser.proseDiagnostics(for: text)
    #expect(!blocks.isEmpty)
    var previous = 0
    for block in blocks {
      #expect(block.startLine > previous, "blocks come in source order: \(block.firstLine)")
      #expect(block.endLine >= block.startLine + block.lineCount - 1)
      let line = source[block.startLine - 1].trimmingCharacters(in: .whitespaces)
      #expect(String(line.prefix(80)) == block.firstLine)
      previous = block.startLine
    }
  }

  /// The margin of an indent refusal is taken against the document's own limit.
  @Test func `a diagnosis records the indent limit it was judged against`() {
    let lines = ["         Set nine deep, past a limit of seven for this document."]
    let diagnosis = LegacyTextParser.diagnose(lines, maxIndent: 7)
    #expect(diagnosis.indentLimit == 7)
    #expect(diagnosis.rejections == [.indentTooDeep])
  }
}
