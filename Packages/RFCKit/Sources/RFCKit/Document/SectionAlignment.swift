import Foundation

/// A section of a successor that replaces a section of the document it obsoletes
/// (#388): 7231 §5.3.2 → 9110 §12.5.1.
///
/// A row in the shape the corpus extractors take (#174), like `Amendment`: computed
/// offline for every obsoletes edge, so a reader of either document can ask where a
/// section went or came from without parsing the other.
public struct AlignedSection: Sendable, Hashable, Codable {
  /// The obsoleted document.
  public var old: DocumentID
  /// The anchor of its section.
  public var oldSection: String
  /// The document that obsoletes it.
  public var new: DocumentID
  /// The anchor of the section that replaces it.
  public var newSection: String
  /// How alike the two sections are, from 0 to 1: what the pair cleared
  /// `SectionAlignment.threshold` with.
  public var score: Double

  public init(
    old: DocumentID, oldSection: String, new: DocumentID, newSection: String, score: Double
  ) {
    self.old = old
    self.oldSection = oldSection
    self.new = new
    self.newSection = newSection
    self.score = score
  }
}

/// Which sections of a successor replace which sections of the document it obsoletes.
///
/// Every section of either document, at every depth, is scored against every section
/// of the other, from two parts: how alike their titles are, at 0.4, and how alike
/// their own prose is, at 0.6. The title finds a renumbered section (7231 §5.3.2
/// "Accept" is 9110 §12.5.1 "Accept"); the prose finds a retitled one (7231 "Payload
/// Semantics" is 9110 "Content"). Where the sections stand in their documents breaks
/// only a tie: a successor that restructures its predecessor, as 9110 does, moves
/// whole chapters, so an alignment that keeps the order would fail where it is
/// needed most.
///
/// A pair is kept when it clears `threshold` and is the best match of one of its two
/// sections. So matching is not one to one: a section split in two is the best match
/// of both halves, and two merged into one each have it as theirs. A section with no
/// pair is new, or gone.
public enum SectionAlignment {
  /// The least score a pair is kept with. It and the weights were set against the
  /// hand-labeled predecessors of RFC 9110's sections (#388), for the most recall
  /// that keeps precision at 90% or more, since a wrong successor misleads where a
  /// missing one only leaves the document-level status: 31 of 33 pairs right, 31 of
  /// 35 found. Weighed equally, the parts reach 29 of 29 right, but only 29 found.
  public static let threshold = 0.3

  public static func pairs(old: RFCDocument, new: RFCDocument) -> [AlignedSection] {
    guard let oldID = old.header.id, let newID = new.header.id else { return [] }
    let oldProfiles = profiles(of: old)
    let newProfiles = profiles(of: new)
    let weights = inverseDocumentFrequencies(of: oldProfiles + newProfiles)
    let oldVectors = oldProfiles.map { vector(of: $0, weights: weights) }
    let newVectors = newProfiles.map { vector(of: $0, weights: weights) }

    var scores = [[Double]](
      repeating: [Double](repeating: 0, count: newProfiles.count), count: oldProfiles.count)
    for (oldIndex, oldProfile) in oldProfiles.enumerated() {
      for (newIndex, newProfile) in newProfiles.enumerated() {
        let titles = similarity(oldProfile.title, newProfile.title)
        let prose = cosine(oldVectors[oldIndex], newVectors[newIndex])
        scores[oldIndex][newIndex] = 0.4 * titles + 0.6 * prose
      }
    }

    // The tie-break: a pair's distance in place, as fractions of each document.
    func rank(_ oldIndex: Int, _ newIndex: Int) -> Double {
      let distance = abs(
        oldProfiles[oldIndex].position - newProfiles[newIndex].position)
      return scores[oldIndex][newIndex] - distance * 1e-6
    }
    let oldIndices = Array(oldProfiles.indices)
    let newIndices = Array(newProfiles.indices)
    let bestForNew = newIndices.map { newIndex in
      oldIndices.max { rank($0, newIndex) < rank($1, newIndex) }
    }
    let bestForOld = oldIndices.map { oldIndex in
      newIndices.max { rank(oldIndex, $0) < rank(oldIndex, $1) }
    }

    var pairs: [AlignedSection] = []
    for oldIndex in oldIndices {
      for newIndex in newIndices {
        let score = scores[oldIndex][newIndex]
        guard score >= threshold,
          bestForNew[newIndex] == oldIndex || bestForOld[oldIndex] == newIndex
        else { continue }
        pairs.append(
          AlignedSection(
            old: oldID, oldSection: oldProfiles[oldIndex].anchor,
            new: newID, newSection: newProfiles[newIndex].anchor,
            score: score))
      }
    }
    return pairs
  }

  /// What a section is compared by.
  private struct Profile {
    var anchor: String
    var title: Set<String>
    /// How often each word occurs in the section's title and its own prose, not its
    /// subsections'.
    var terms: [String: Int]
    /// Where the section stands in its document, from 0 for the first to 1.
    var position: Double
  }

  /// A bibliography is left out: its entries are titles of other documents, which
  /// would match every section that cites the same ones.
  private static func profiles(of document: RFCDocument) -> [Profile] {
    let sections = document.allSections.filter { !$0.holdsOnlyReferences }
    let last = Double(max(sections.count - 1, 1))
    return sections.enumerated().compactMap { index, section in
      let title = words(in: section.titleText)
      let prose = section.blocks.flattened.flatMap(\.proseRuns).map(\.plainText)
      let terms = (title + prose.flatMap(words(in:))).reduce(into: [String: Int]()) {
        $0[$1, default: 0] += 1
      }
      guard !terms.isEmpty else { return nil }
      return Profile(
        anchor: section.anchor, title: Set(title), terms: terms,
        position: Double(index) / last)
    }
  }

  /// The words of `text`, lowercased, less the ones too common to tell sections apart.
  private static func words(in text: String) -> [String] {
    text.lowercased()
      .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
      .filter { $0.count > 1 && !stopWords.contains($0) }
  }

  private static let stopWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "does", "for",
    "from", "has", "have", "if", "in", "into", "is", "it", "its", "may", "must", "no", "not",
    "of", "on", "or", "other", "shall", "should", "so", "such", "than", "that", "the", "their",
    "then", "there", "these", "this", "those", "to", "was", "were", "which", "will", "with",
  ]

  /// Jaccard similarity of two titles' words.
  private static func similarity(_ first: Set<String>, _ second: Set<String>) -> Double {
    let union = first.union(second).count
    guard union > 0 else { return 0 }
    return Double(first.intersection(second).count) / Double(union)
  }

  /// How rare each word is across the sections of both documents, so a word every
  /// section of an HTTP document uses, "request", counts for less than "trailer".
  private static func inverseDocumentFrequencies(of profiles: [Profile]) -> [String: Double] {
    var counts: [String: Int] = [:]
    for profile in profiles {
      for term in profile.terms.keys {
        counts[term, default: 0] += 1
      }
    }
    let total = Double(profiles.count)
    return counts.mapValues { log(1 + total / Double($0)) }
  }

  /// A section's words weighed by how rare they are, scaled to length 1.
  private static func vector(of profile: Profile, weights: [String: Double]) -> [String: Double] {
    let weighted = profile.terms.mapValues(Double.init).map { term, count in
      (term, count * (weights[term] ?? 0))
    }
    let length = sqrt(weighted.reduce(0) { $0 + $1.1 * $1.1 })
    guard length > 0 else { return [:] }
    return Dictionary(uniqueKeysWithValues: weighted.map { ($0, $1 / length) })
  }

  private static func cosine(_ first: [String: Double], _ second: [String: Double]) -> Double {
    let (shorter, longer) = first.count < second.count ? (first, second) : (second, first)
    return shorter.reduce(0) { $0 + $1.value * (longer[$1.key] ?? 0) }
  }
}
