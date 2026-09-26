import Foundation
import Testing

@testable import RFCKit

@Suite("Prose diagnostics")
struct ProseDiagnosticsTests {
  // MARK: A block that passes

  @Test func plainProsePassesEveryGuard() {
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
  @Test func indentTooDeepCarriesTheIndentThatFailed() {
    let lines = [
      "       An example paragraph set well past the body margin, which the",
      "       parser treats as preformatted for that reason alone.",
      "       It reads like ordinary prose in every other respect.",
    ]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections == [.indentTooDeep])
    #expect(diagnosis.indent == 7, "one column past the limit, which is what makes it a near miss")
  }

  @Test func firstLineIndentOutOfRangeIsDistinctFromIndent() {
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

  @Test func raggedIndentIsReportedSeparately() {
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
  @Test func oneArrowRejectsAnOtherwiseOrdinaryParagraph() {
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

  @Test func artworkMatchesAreCountedNotJustDetected() {
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
  @Test func justifiedProseIsExcusedTheInternalGapGuard() throws {
    let text = try Fixtures.string("rfc757.txt")
    let blocks = LegacyTextParser.proseDiagnostics(for: text)
    let justified = blocks.filter { $0.diagnosis.justification.agreed }
    #expect(!justified.isEmpty, "RFC 757 is one of the justified-typeset documents")
    for block in justified {
      #expect(!block.diagnosis.rejections.contains(.internalGap))
    }
  }

  @Test func aFailedTellIsNamed() {
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
  func everyClassifiedBlockIsAlsoDiagnosed(fixture: String) throws {
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

  /// `classify` offers a block to the list parser before it asks the prose test, so a
  /// list item's prose verdict was never actually taken. A hanging marker outdents the
  /// first line, so these fail `firstLineIndentOutOfRange` almost without exception —
  /// and counting that as a failure of the prose test would misreport the parser.
  @Test func listItemsAreMarkedAsNeverReachingTheProseTest() throws {
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
  func shortCircuitingAgreesWithTheFullDiagnosis(fixture: String) throws {
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

  @Test func everyBlockCarriesEnoughToFindItAgain() throws {
    let blocks = LegacyTextParser.proseDiagnostics(for: try Fixtures.string("rfc2119.txt"))
    let sample = try #require(blocks.first { $0.diagnosis.isProse })
    #expect(!sample.firstLine.isEmpty)
    #expect(sample.lineCount > 0)
    #expect(sample.firstLine.count <= 80, "truncated for a report, not a second copy of the corpus")
  }

  @Test func rejectionsAreRecordedInEvaluationOrder() {
    let lines = ["          +-+-+-+-+", "          | A | B |", "          +-+-+-+-+"]
    let diagnosis = LegacyTextParser.diagnose(lines)
    #expect(diagnosis.rejections.first == .indentTooDeep, "indent is tested before content")
    #expect(diagnosis.rejections.contains(.artworkPattern))
  }

  @Test func emptyInputIsRejectedWithoutCrashing() {
    let diagnosis = LegacyTextParser.diagnose([])
    #expect(diagnosis.rejections == [.noLines])
  }

  // MARK: The byte scans answer what the regexes answer

  /// The prose test asks `artworkPattern` and `internalGapPattern` of every line through
  /// a byte scan, because the regexes were half of `parse`. Each scan has to answer
  /// exactly what its regex would, over every line of every fixture and over the shapes
  /// the scans treat specially: the gap's punctuation rule, runs at the trimmed edges,
  /// `\r\n`, and lines that are not ASCII.
  @Test func theByteScansAgreeWithTheRegexes() throws {
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
}
