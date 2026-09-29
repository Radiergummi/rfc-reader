import Foundation
import RFCKit

/// What the prose test decided across the corpus, and where it decided narrowly.
///
/// Not every block: at roughly a million of them the file would be unusable. The
/// two things worth keeping are the shape of the whole — which guard fires, how
/// often — and the blocks refused by exactly one guard, which is the sample
/// hand-labeling draws from.
public struct ProseReport: Codable, Sendable {
  public var documents = 0
  public var blocks = 0
  public var prose = 0
  /// Claimed by the list parser, so never put to the prose test.
  public var lists = 0
  public var nearMisses = 0
  /// How often each guard refused a block, counting a block once per guard.
  public var byRejection: [String: Int] = [:]
  /// How often each guard was the *only* one to refuse: relax that guard alone,
  /// and this many blocks change their verdict.
  public var soleRejection: [String: Int] = [:]
  /// Which justification tell dissented, among blocks where the others agreed.
  public var justificationDissent: [String: Int] = [:]
  /// The near misses themselves, capped. The counts above stay exact; this is a
  /// sample and is named one. A full corpus run puts the near-miss population in
  /// the hundreds of thousands, which is tens of megabytes of JSON nobody reads.
  public var sample: [NearMiss] = []

  /// Enough near misses to see the shape of each guard's population by eye.
  public static let sampleLimit = 2000

  public struct NearMiss: Codable, Sendable {
    public var document: String
    public var section: String
    public var firstLine: String
    public var lineCount: Int
    public var rejection: String
    public var indent: Int
    public var firstLineIndent: Int
    public var artworkMatches: Int
    public var sentenceRatio: Double
  }

  public init() {}

  /// The report of one document, from its diagnosed blocks.
  public init(diagnosed: [BlockDiagnostics], id: String) {
    documents += 1
    for block in diagnosed {
      let diagnosis = block.diagnosis
      blocks += 1
      if block.claimedByList {
        lists += 1
        continue
      }
      if diagnosis.isProse {
        prose += 1
        continue
      }
      for rejection in diagnosis.rejections {
        byRejection[rejection.rawValue, default: 0] += 1
      }
      // The tells gate the internalGap guard and nothing else, so counting dissent
      // on a block refused elsewhere would mix in blocks where they were inert.
      if diagnosis.rejections.contains(.internalGap) {
        let dissent = diagnosis.justification.dissenting
        if dissent.count == 1, let only = dissent.first {
          justificationDissent[only, default: 0] += 1
        }
      }
      guard diagnosis.isNearMiss, let rejection = diagnosis.rejections.first else { continue }
      nearMisses += 1
      soleRejection[rejection.rawValue, default: 0] += 1
      guard sample.count < Self.sampleLimit else { continue }
      sample.append(
        NearMiss(
          document: id,
          section: block.section,
          firstLine: block.firstLine,
          lineCount: block.lineCount,
          rejection: rejection.rawValue,
          indent: diagnosis.indent,
          firstLineIndent: diagnosis.firstLineIndent,
          artworkMatches: diagnosis.artworkMatches,
          sentenceRatio: (diagnosis.sentenceRatio * 1000).rounded() / 1000
        ))
    }
  }

  /// Each document is diagnosed into a report of its own, and they are folded
  /// together in document order, so the capped sample is the first `sampleLimit`
  /// near misses of the corpus -- the same ones a single pass over it would keep.
  public mutating func merge(_ other: ProseReport) {
    documents += other.documents
    blocks += other.blocks
    prose += other.prose
    lists += other.lists
    nearMisses += other.nearMisses
    byRejection.merge(other.byRejection, uniquingKeysWith: +)
    soleRejection.merge(other.soleRejection, uniquingKeysWith: +)
    justificationDissent.merge(other.justificationDissent, uniquingKeysWith: +)
    sample += other.sample.prefix(Self.sampleLimit - sample.count)
  }
}
