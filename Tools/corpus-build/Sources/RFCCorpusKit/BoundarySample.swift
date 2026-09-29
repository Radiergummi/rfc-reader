import Foundation
import RFCKit

/// The blocks the prose test refused by exactly one guard, and narrowly: the decision
/// boundary, which is what hand-labelling draws from (#43).
///
/// A uniform sample of blocks would be almost all unambiguous prose. Because the prose
/// test is a conjunction of guards, "near the boundary" has an exact meaning: every
/// guard but one agreed, and that one only just refused. `ProseReport`'s near-miss
/// sample is capped and carries no line range; this sees every block of a `convert`
/// run and records where each selected block is, never its text. A reviewer reads the
/// block from the fetched source by its line range; the hash says the source is the
/// one the entry was taken from.
public enum BoundarySample {
  /// One block on the boundary.
  public struct Entry: Codable, Sendable, Equatable {
    public var document: String
    /// The block's source lines, 1-based and inclusive.
    public var startLine: Int
    public var endLine: Int
    /// SHA-256 of those source lines, joined by newlines, as UTF-8: of the text as
    /// `convert` decoded it, which for the few Windows-1252 documents is not the bytes
    /// of the file.
    public var sha256: String
    /// Which boundary: `indent`, `artwork`, `sentences` or `justified`.
    public var criterion: String
    /// The one guard that refused, as `ProseDiagnostics.Rejection` names it.
    public var rejection: String
    /// What was measured against the guard's threshold.
    public var measurement: Double
    /// How far past the threshold it was.
    public var margin: Double
  }

  /// A criterion a diagnosis met, with its measurement and margin.
  public struct Criterion: Equatable, Sendable {
    public var name: String
    public var measurement: Double
    public var margin: Double
  }

  /// The boundary criterion `diagnosis` meets, or nil when it was refused by no guard,
  /// by more than one, or by one but not narrowly:
  ///
  /// - **indent:** set one or two columns past its document's limit, and reading as
  ///   the sentences a limit that deep would excuse;
  /// - **artwork:** one artwork match in the whole block, an incidental `->` or `...`;
  /// - **sentences:** justified but for reading as sentences, with a sentence ratio in
  ///   [0.5, 0.6), just under the three fifths that tell asks for;
  /// - **justified:** four of the five justification tells agreeing, the fifth not
  ///   the sentences one. Their agreement is what excuses an internal gap.
  public static func criterion(for diagnosis: ProseDiagnostics) -> Criterion? {
    guard diagnosis.isNearMiss, let rejection = diagnosis.rejections.first else { return nil }
    switch rejection {
    case .indentTooDeep:
      // A looser limit excuses only sentences past the classic cap; code set that deep
      // would be refused as code instead.
      let over = diagnosis.indent - diagnosis.indentLimit
      guard (1...2).contains(over), diagnosis.readsAsDeepProse else { return nil }
      return Criterion(name: "indent", measurement: Double(diagnosis.indent), margin: Double(over))
    case .artworkPattern:
      guard diagnosis.artworkMatches == 1 else { return nil }
      return Criterion(name: "artwork", measurement: 1, margin: 1)
    case .internalGap:
      guard diagnosis.justification.dissenting.count == 1 else { return nil }
      if !diagnosis.justification.readsLikeSentences {
        let ratio = diagnosis.sentenceRatio
        guard (0.5..<0.6).contains(ratio) else { return nil }
        return Criterion(name: "sentences", measurement: ratio, margin: 0.6 - ratio)
      }
      return Criterion(name: "justified", measurement: 4, margin: 1)
    default:
      return nil
    }
  }

  /// The boundary entries among one document's diagnosed blocks, and how many blocks
  /// on the boundary could not be found in the source to point at. A block the list
  /// parser claimed is skipped: it was never put to the prose test, so its refusals
  /// describe a decision that was not taken.
  public static func entries(for blocks: [BlockDiagnostics], in text: String, document: String)
    -> (entries: [Entry], unlocated: Int)
  {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
    var entries: [Entry] = []
    var unlocated = 0
    for block in blocks {
      guard !block.claimedByList,
        let criterion = criterion(for: block.diagnosis),
        let rejection = block.diagnosis.rejections.first
      else { continue }
      guard let range = block.sourceLines else {
        unlocated += 1
        continue
      }
      let source = lines[(range.lowerBound - 1)..<range.upperBound].joined(separator: "\n")
      entries.append(
        Entry(
          document: document, startLine: range.lowerBound, endLine: range.upperBound,
          sha256: Manifest.sha256(of: Data(source.utf8)), criterion: criterion.name,
          rejection: rejection.rawValue,
          measurement: criterion.measurement, margin: criterion.margin))
    }
    return (entries, unlocated)
  }
}
