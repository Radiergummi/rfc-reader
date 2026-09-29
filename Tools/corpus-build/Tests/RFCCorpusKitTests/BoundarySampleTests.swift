import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The blocks the prose test refused by exactly one guard, and narrowly: what hand-
/// labelling draws from (#43). Hand-built diagnoses, each criterion just inside and
/// just outside its margin.
@Suite("Boundary sample")
struct BoundarySampleTests {
  private static func block(
    _ diagnosis: ProseDiagnostics, sourceLines: ClosedRange<Int>? = 3...4,
    claimedByList: Bool = false
  ) -> BlockDiagnostics {
    BlockDiagnostics(
      section: "section-1", firstLine: "a line", lineCount: 2, claimedByList: claimedByList,
      diagnosis: diagnosis, sourceLines: sourceLines)
  }

  private static func indented(_ indent: Int, limit: Int = 6) -> ProseDiagnostics {
    var diagnosis = ProseDiagnostics()
    diagnosis.rejections = [.indentTooDeep]
    diagnosis.indent = indent
    diagnosis.indentLimit = limit
    diagnosis.readsAsDeepProse = true
    return diagnosis
  }

  private static func artwork(_ matches: Int) -> ProseDiagnostics {
    var diagnosis = ProseDiagnostics()
    diagnosis.rejections = [.artworkPattern]
    diagnosis.artworkMatches = matches
    return diagnosis
  }

  /// Refused only for its internal gap, with every justification tell agreeing but
  /// the ones named in `dissenting`.
  private static func gapped(dissenting: Set<String>, sentenceRatio: Double = 0.8)
    -> ProseDiagnostics
  {
    var diagnosis = ProseDiagnostics()
    diagnosis.rejections = [.internalGap]
    diagnosis.sentenceRatio = sentenceRatio
    diagnosis.justification.enoughLines = !dissenting.contains("enoughLines")
    diagnosis.justification.commonRightMargin = !dissenting.contains("commonRightMargin")
    diagnosis.justification.noColumnGutter = !dissenting.contains("noColumnGutter")
    diagnosis.justification.paddingSpread = !dissenting.contains("paddingSpread")
    diagnosis.justification.readsLikeSentences = !dissenting.contains("readsLikeSentences")
    return diagnosis
  }

  private static func criterion(_ diagnosis: ProseDiagnostics) -> String? {
    BoundarySample.criterion(for: diagnosis)?.name
  }

  @Test func `an indent one or two past the limit is on the boundary`() {
    #expect(Self.criterion(Self.indented(7)) == "indent")
    #expect(Self.criterion(Self.indented(8)) == "indent")
    #expect(Self.criterion(Self.indented(9)) == nil)
    #expect(
      Self.criterion(Self.indented(12, limit: 10)) == "indent", "against the document's own limit")
    #expect(BoundarySample.criterion(for: Self.indented(8))?.margin == 2)
  }

  /// Past the classic cap a looser limit excuses only sentences, so a block too deep
  /// that reads as code would be refused as code instead: two guards, not one.
  @Test func `an indent a looser limit would refuse as code is not on the boundary`() {
    var code = Self.indented(7)
    code.readsAsDeepProse = false
    #expect(Self.criterion(code) == nil)
  }

  @Test func `a single artwork match is on the boundary`() {
    #expect(Self.criterion(Self.artwork(1)) == "artwork")
    #expect(Self.criterion(Self.artwork(2)) == nil)
  }

  @Test func `a sentence ratio just under three fifths is on the boundary`() throws {
    let near = Self.gapped(dissenting: ["readsLikeSentences"], sentenceRatio: 0.55)
    #expect(Self.criterion(near) == "sentences")
    let margin = try #require(BoundarySample.criterion(for: near)?.margin)
    #expect(abs(margin - 0.05) < 0.0001)
    #expect(
      Self.criterion(Self.gapped(dissenting: ["readsLikeSentences"], sentenceRatio: 0.45)) == nil)
  }

  @Test func `four of the five justification tells agreeing is on the boundary`() {
    #expect(Self.criterion(Self.gapped(dissenting: ["paddingSpread"])) == "justified")
    #expect(Self.criterion(Self.gapped(dissenting: ["paddingSpread", "noColumnGutter"])) == nil)
  }

  @Test func `a block two guards refused is never on the boundary`() {
    var diagnosis = Self.indented(7)
    diagnosis.rejections.append(.artworkPattern)
    diagnosis.artworkMatches = 1
    #expect(BoundarySample.criterion(for: diagnosis) == nil)
  }

  /// The list parser took it before the prose test; its refusals describe nothing.
  @Test func `a block the list parser claimed is never sampled`() {
    let sample = BoundarySample.entries(
      for: [Self.block(Self.artwork(1), claimedByList: true)], in: "one\ntwo\nthree\nfour",
      document: "rfc1")
    #expect(sample.entries.isEmpty)
    #expect(sample.unlocated == 0)
  }

  /// A block on the boundary that was not found in the source is counted, not dropped
  /// without a trace.
  @Test func `a block not found in the source is counted`() {
    let sample = BoundarySample.entries(
      for: [Self.block(Self.artwork(1), sourceLines: nil)], in: "one\ntwo", document: "rfc1")
    #expect(sample.entries.isEmpty)
    #expect(sample.unlocated == 1)
  }

  /// An entry names the block by line range and hash, never by its text.
  @Test func `an entry locates the block without its text`() throws {
    let text = "first\nsecond\nthe block's line\nand its next\nafter"
    let entry = try #require(
      BoundarySample.entries(
        for: [Self.block(Self.artwork(1), sourceLines: 3...4)], in: text, document: "rfc9"
      ).entries.first)
    #expect(entry.document == "rfc9")
    #expect(entry.startLine == 3 && entry.endLine == 4)
    #expect(entry.criterion == "artwork" && entry.rejection == "artworkPattern")
    #expect(entry.sha256.count == 64)
    let other = try #require(
      BoundarySample.entries(
        for: [Self.block(Self.artwork(1), sourceLines: 1...2)], in: text, document: "rfc9"
      ).entries.first)
    #expect(other.sha256 != entry.sha256, "the hash is of the block's own lines")
  }
}
