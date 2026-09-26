import Foundation

/// Why `LegacyTextParser` reached the verdict it reached on one block.
///
/// The parser decides prose-versus-artwork by a conjunction of absolute vetoes, and
/// keeps only the answer. That is enough to render a document and not nearly enough to
/// judge a change to the heuristics: `corpus/report.json` reports outcomes, so a block
/// that comes out wrong carries no record of *which* guard rejected it, or by how much.
///
/// This is that record. It is a by-product of the same code that decides — never a
/// second implementation of it — so the two cannot disagree.
public struct ProseDiagnostics: Sendable {
  /// A guard that refused the block, named for the thing it tests. Order of
  /// declaration is order of evaluation.
  public enum Rejection: String, Sendable {
    /// The block had no lines at all.
    case noLines
    /// The body indent is deeper than a paragraph is allowed to start.
    case indentTooDeep
    /// The first line is offset from the body by more than a paragraph indent.
    case firstLineIndentOutOfRange
    /// Some line after the first does not return to the block's indent.
    case raggedIndent
    /// A line matched the artwork pattern: box drawing, rules, arrows, ellipses.
    case artworkPattern
    /// A run of three or more spaces inside a line, in a block that is not justified.
    case internalGap
  }

  /// Every guard that refused, in evaluation order. Empty means the block is prose.
  public var rejections: [Rejection] = []

  /// The block's indent, taken from its second line where it has one — most
  /// pre-1990 RFCs indent a paragraph's first line and set the rest at the margin.
  public var indent: Int = 0

  /// How far the first line is offset from `indent`. May be negative.
  public var firstLineIndent: Int = 0

  /// How many times the artwork pattern matched across the whole block. One match is
  /// an incidental `->` in a sentence; a diagram matches on nearly every line.
  public var artworkMatches: Int = 0

  /// The share of words that read as ordinary lower-case prose rather than
  /// identifiers, addresses or numbers. The guard itself uses an exact integer
  /// comparison; this is the same quantity, reported.
  public var sentenceRatio: Double = 0

  /// Which of the four tells for justified typesetting agreed, and which did not.
  public var justification = JustificationTells()

  public init() {}

  /// No guard refused.
  public var isProse: Bool { rejections.isEmpty }

  /// Refused by exactly one guard, and so a candidate for the boundary sample that
  /// hand-labelling draws from: everything agreed except one thing.
  public var isNearMiss: Bool { rejections.count == 1 }
}

/// The four tells that have to agree before a block counts as justified prose, kept
/// apart so a disagreement can be attributed.
///
/// Any one of them is satisfied on its own by a table, a definition list or a block of
/// code, which is why the parser requires all four — and why knowing *which* one
/// dissented is worth more than knowing that one did.
public struct JustificationTells: Sendable {
  /// Three lines at minimum; below that a common margin means nothing.
  public var enoughLines = false
  /// Every line but the last ends at the same column, at or past column 60.
  public var commonRightMargin = false
  /// No run of columns left blank by every line — that would be a two-column layout.
  public var noColumnGutter = false
  /// The padding is spread over most lines rather than sitting in one column.
  public var paddingSpread = false
  /// The words read like sentences rather than identifiers.
  public var readsLikeSentences = false

  public init() {}

  public var agreed: Bool {
    enoughLines && commonRightMargin && noColumnGutter && paddingSpread && readsLikeSentences
  }

  /// The tells that dissented, for a report that wants to say why.
  public var dissenting: [String] {
    var names: [String] = []
    if !enoughLines { names.append("enoughLines") }
    if !commonRightMargin { names.append("commonRightMargin") }
    if !noColumnGutter { names.append("noColumnGutter") }
    if !paddingSpread { names.append("paddingSpread") }
    if !readsLikeSentences { names.append("readsLikeSentences") }
    return names
  }
}

/// One block of a document, diagnosed, with just enough context to find it again in the
/// source. Deliberately not the block's text: the report is an index into the corpus,
/// not a second copy of it.
public struct BlockDiagnostics: Sendable {
  /// The anchor of the section the block sits in, or `""` before the first heading.
  public var section: String
  /// The block's first line, trimmed and truncated — enough to locate it by eye.
  public var firstLine: String
  /// How many lines the block has.
  public var lineCount: Int
  /// The list parser claimed this block, so classification never put the prose test
  /// to it.
  ///
  /// The diagnosis is still recorded, because a block that is a list *and* reads as
  /// prose is worth seeing — but its rejections describe a decision that was never
  /// taken, and counting them as failures of the prose test would be a lie. A hanging
  /// list item outdents its marker, so it fails `firstLineIndentOutOfRange` with a
  /// negative offset essentially every time.
  public var claimedByList: Bool
  /// The verdict and its reasons.
  public var diagnosis: ProseDiagnostics

  public init(
    section: String, firstLine: String, lineCount: Int, claimedByList: Bool,
    diagnosis: ProseDiagnostics
  ) {
    self.section = section
    self.firstLine = firstLine
    self.lineCount = lineCount
    self.claimedByList = claimedByList
    self.diagnosis = diagnosis
  }
}
