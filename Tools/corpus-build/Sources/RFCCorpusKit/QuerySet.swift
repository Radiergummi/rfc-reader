import Foundation
import RFCKit

/// Builds the cross-reference judgement set used to measure search ranking (#37).
///
/// A cross reference that names a section of another RFC is a relevance judgement its
/// author already made: the sentence around it says what the target section is about.
/// Excise the citation and that sentence becomes a query whose answer is known, which
/// is the only way to get thousands of judgements without writing them by hand.
///
/// The filtering lives here rather than in a scratch script because the set is
/// worthless if it cannot be reproduced.
public struct QuerySet {
  /// Function words carry no discrimination over a corpus of specifications; a
  /// sentence made only of these describes nothing and cannot identify a section.
  private static let stopwords: Set<String> = [
    "a", "an", "the", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did",
    "how", "what", "when", "where", "why", "which", "who", "whom", "whose", "that", "this",
    "these", "those", "i", "it", "its", "he", "she", "they", "them", "their", "you", "your",
    "and", "or", "but", "if", "then", "than", "so", "as", "at", "by", "for", "from", "in",
    "into", "of", "on", "to", "with", "without", "not", "no", "can", "could", "may", "might",
    "must", "shall", "should", "will", "would", "have", "has", "had", "get", "got", "about",
    "there", "here", "out", "up", "down", "over", "under", "again", "only", "own", "same",
  ]

  private struct Candidate {
    let query: String
    let fromDoc: String
    let toDoc: String
    let toSection: String
  }

  public struct Row: Encodable, Sendable {
    // The committed query sets spell the query `q`.
    // swiftlint:disable:next identifier_name
    public let q: String
    public let kind: String
    public let primary: String
    public let from: String
    public let answers: [[String]]
  }

  /// What `select` kept, and why it dropped the rest.
  public struct Selection: Sendable {
    /// The seeded sample, at most `limit` long.
    public var rows: [Row]
    /// How many candidates survived filtering, before sampling.
    public var usable: Int
    /// How many candidates each filter dropped, by reason.
    public var dropped: [String: Int]
  }

  /// Every numbered section in the corpus, so a citation pointing at one that was
  /// never parsed can be dropped rather than counted as a miss nobody can reach.
  private var known: Set<String> = []
  private var candidates: [Candidate] = []

  public init() {}

  /// How many citing sentences have been recovered so far, before any filtering.
  public var citingSentences: Int { candidates.count }

  /// Recovers the citing sentences of one document, and records its numbered sections
  /// as targets. `id` is the document's name as a citation of it spells it (`RFC2119`).
  public mutating func collect(_ document: RFCDocument, id: String) {
    for section in document.allSections {
      if let number = section.number, !number.isEmpty { known.insert("\(id)\u{1F}\(number)") }
      for case .paragraph(let paragraph) in section.blocks.flattened {
        let located = paragraph.inlines.locatedPlainText
        for citation in located.crossReferences {
          guard case .document(let target, let targetSection?) = citation.reference.target,
            let sentence = Self.sentence(around: citation.range, in: located.text)
          else { continue }
          candidates.append(
            Candidate(
              query: sentence, fromDoc: id,
              toDoc: target.description, toSection: targetSection))
        }
      }
    }
  }

  /// Filters the candidates collected from the whole corpus, then samples `limit` of
  /// them with a generator seeded by `seed`.
  public func select(limit: Int, seed: UInt64, minimumWords: Int) -> Selection {
    var kept: [Row] = []
    var seen: Set<String> = []
    var dropped: [String: Int] = [:]
    let shortReason = "under \(minimumWords) content words"
    for candidate in candidates {
      guard known.contains("\(candidate.toDoc)\u{1F}\(candidate.toSection)") else {
        dropped["target not in corpus", default: 0] += 1
        continue
      }
      guard candidate.fromDoc != candidate.toDoc else {
        dropped["self-citation", default: 0] += 1
        continue
      }
      let content = Self.words(in: candidate.query).map { $0.lowercased() }.filter {
        !Self.stopwords.contains($0)
      }
      guard content.count >= minimumWords else {
        dropped[shortReason, default: 0] += 1
        continue
      }
      let key = String(content.sorted().joined(separator: " ").prefix(120))
      guard seen.insert(key).inserted else {
        dropped["near-duplicate", default: 0] += 1
        continue
      }
      kept.append(
        Row(
          q: candidate.query, kind: "xref", primary: candidate.toDoc,
          from: candidate.fromDoc, answers: [[candidate.toDoc, candidate.toSection]]))
    }
    let usable = kept.count

    // Seeded so the set can be reproduced exactly; Swift's own shuffle
    // takes the system generator and would give a different sample every run.
    var generator = SplitMix64(seed: seed)
    kept.shuffle(using: &generator)
    return Selection(rows: Array(kept.prefix(limit)), usable: usable, dropped: dropped)
  }

  private static func words(in text: String) -> [String] {
    text.split(whereSeparator: {
      !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    })
    .map(String.init)
    .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
  }

  /// The sentence containing the citation at `range` of `text`, with the citation
  /// excised so the query cannot simply name its own answer.
  private static func sentence(around range: Range<String.Index>, in text: String) -> String? {
    guard range.lowerBound < text.endIndex else { return nil }
    var low = range.lowerBound
    while low > text.startIndex {
      let previous = text.index(before: low)
      if text[previous] == "." || text[previous] == "\n" { break }
      low = previous
    }
    var high = range.upperBound
    while high < text.endIndex {
      let character = text[high]
      high = text.index(after: high)
      if character == "." || character == "\n" { break }
    }
    guard low < range.lowerBound, high > range.upperBound else { return nil }
    let before = text[low..<range.lowerBound]
    let after = text[range.upperBound..<high]
    return (before + " " + after)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// A small seeded generator, so `--seed` reproduces a sample byte for byte on any
/// platform. `SystemRandomNumberGenerator` cannot be seeded and CI runs on Linux.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}
