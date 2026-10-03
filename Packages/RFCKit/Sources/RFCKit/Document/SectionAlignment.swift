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
/// A pair is kept when it clears `threshold`, its prose has at least `minimumProse` in
/// common, and it is the best match of one of its two sections. So matching is not one to one: a section split in two is the best match
/// of both halves, and two merged into one each have it as theirs. A section with no
/// pair is new, or gone.
///
/// Documents joined by more than one obsoletes edge are aligned together, and a
/// section's best match is the best across all of them. RFC 7230 is obsoleted by 9110
/// and 9112, and 9110 obsoletes 7230 and 7231: a 7230 section that moved to 9112 is
/// paired there and not also with its nearest, wrong, counterpart in 9110, and 9110's
/// "Status Codes", whose predecessor is in 7231, does not take 7230's "Status Line"
/// for want of anything better in 7230.
public enum SectionAlignment {
  /// The least score a pair is kept with. It and the weights were set against the
  /// hand-labeled predecessors of RFC 9110's sections (#388), for the most recall
  /// that keeps precision at 90% or more, since a wrong successor misleads where a
  /// missing one only leaves the document-level status. See the decision record for
  /// what was measured.
  public static let threshold = 0.3

  /// The least the prose of a pair has in common for it to score at all, the cosine
  /// of the two sections' own prose with neither title's words in it. A title
  /// alone clears `threshold` (0.4 for two equal ones), so without it every
  /// "Overview" or "Examples" of a successor would pair with the old one whatever
  /// either says. It costs nothing measured against RFC 9110's labels.
  static let minimumProse = 0.1

  /// The sections of every document in `documents` that another of them obsoletes,
  /// paired with those of the documents obsoleting it. The edges are the ones each
  /// document's header names, among these documents; a document without a number
  /// takes part in none, and one naming itself is no edge.
  public static func pairs(among documents: [RFCDocument]) -> [AlignedSection] {
    var byID: [DocumentID: RFCDocument] = [:]
    for document in documents {
      guard let id = document.header.id, byID[id] == nil else { continue }
      byID[id] = document
    }
    let edges = byID.keys.sorted().flatMap { newID in
      Set(byID[newID]?.header.obsoletes ?? []).sorted()
        .filter { $0 != newID && byID[$0] != nil }
        .map { Edge(old: $0, new: newID) }
    }
    var profileCache: [DocumentID: [Profile]] = [:]
    func profiles(_ id: DocumentID) -> [Profile] {
      if let cached = profileCache[id] { return cached }
      let made = byID[id].map(Self.profiles(of:)) ?? []
      profileCache[id] = made
      return made
    }
    let matrices = edges.map { edge in
      scores(old: profiles(edge.old), new: profiles(edge.new))
    }

    // For each section, the edge that holds its best match.
    var oldHome: [Place: Int] = [:]
    var newHome: [Place: Int] = [:]
    for (edgeIndex, edge) in edges.enumerated() {
      let matrix = matrices[edgeIndex]
      for oldIndex in matrix.bestForOld.indices {
        let place = Place(document: edge.old, section: oldIndex)
        if oldHome[place].map({ matrices[$0].bestRank(forOld: oldIndex) }) ?? -.infinity
          < matrix.bestRank(forOld: oldIndex)
        {
          oldHome[place] = edgeIndex
        }
      }
      for newIndex in matrix.bestForNew.indices {
        let place = Place(document: edge.new, section: newIndex)
        if newHome[place].map({ matrices[$0].bestRank(forNew: newIndex) }) ?? -.infinity
          < matrix.bestRank(forNew: newIndex)
        {
          newHome[place] = edgeIndex
        }
      }
    }

    var pairs: [AlignedSection] = []
    for (edgeIndex, edge) in edges.enumerated() {
      let matrix = matrices[edgeIndex]
      var candidates: Set<Cell> = []
      for (newIndex, oldIndex) in matrix.bestForNew.enumerated()
      where newHome[Place(document: edge.new, section: newIndex)] == edgeIndex {
        if let oldIndex { candidates.insert(Cell(old: oldIndex, new: newIndex)) }
      }
      for (oldIndex, newIndex) in matrix.bestForOld.enumerated()
      where oldHome[Place(document: edge.old, section: oldIndex)] == edgeIndex {
        if let newIndex { candidates.insert(Cell(old: oldIndex, new: newIndex)) }
      }
      let oldProfiles = profiles(edge.old)
      let newProfiles = profiles(edge.new)
      for cell in candidates.sorted() {
        let score = matrix.values[cell.old][cell.new]
        guard score >= threshold else { continue }
        pairs.append(
          AlignedSection(
            old: edge.old, oldSection: oldProfiles[cell.old].anchor,
            new: edge.new, newSection: newProfiles[cell.new].anchor,
            score: score))
      }
    }
    return pairs
  }

  private struct Edge {
    var old: DocumentID
    var new: DocumentID
  }

  /// A section, by its index among its document's profiles.
  private struct Place: Hashable {
    var document: DocumentID
    var section: Int
  }

  private struct Cell: Hashable, Comparable {
    var old: Int
    var new: Int

    static func < (first: Cell, second: Cell) -> Bool {
      (first.old, first.new) < (second.old, second.new)
    }
  }

  /// Every pair of one old document's sections with one successor's, scored.
  private struct Scores {
    /// By old section, then new.
    var values: [[Double]]
    /// `values`, less a pair's distance in place, which only a tie can feel.
    var ranks: [[Double]]
    var bestForNew: [Int?]
    var bestForOld: [Int?]

    func bestRank(forOld oldIndex: Int) -> Double {
      bestForOld[oldIndex].map { ranks[oldIndex][$0] } ?? -.infinity
    }

    func bestRank(forNew newIndex: Int) -> Double {
      bestForNew[newIndex].map { ranks[$0][newIndex] } ?? -.infinity
    }
  }

  private static func scores(old: [Profile], new: [Profile]) -> Scores {
    let weights = inverseDocumentFrequencies(of: old + new)
    let oldVectors = old.map { vector(of: $0, weights: weights) }
    let newVectors = new.map { vector(of: $0, weights: weights) }
    var values: [[Double]] = []
    var ranks: [[Double]] = []
    for (oldIndex, oldProfile) in old.enumerated() {
      var valueRow: [Double] = []
      var rankRow: [Double] = []
      for (newIndex, newProfile) in new.enumerated() {
        let titles = similarity(oldProfile.title, newProfile.title)
        let prose = cosine(oldVectors[oldIndex], newVectors[newIndex])
        let value = prose < minimumProse ? 0 : 0.4 * titles + 0.6 * prose
        valueRow.append(value)
        rankRow.append(value - abs(oldProfile.position - newProfile.position) * 1e-6)
      }
      values.append(valueRow)
      ranks.append(rankRow)
    }
    let bestForNew = new.indices.map { newIndex in
      old.indices.max { ranks[$0][newIndex] < ranks[$1][newIndex] }
    }
    let bestForOld = old.indices.map { oldIndex in
      new.indices.max { ranks[oldIndex][$0] < ranks[oldIndex][$1] }
    }
    return Scores(
      values: values, ranks: ranks, bestForNew: bestForNew, bestForOld: bestForOld)
  }

  /// What a section is compared by.
  private struct Profile {
    var anchor: String
    var title: Set<String>
    /// How often each word occurs in the section's own prose, not its subsections'
    /// and not its title, which `title` scores apart: counted here too, two equal
    /// titles would clear `minimumProse` for each other over short prose.
    var terms: [String: Int]
    /// Where the section stands in its document, from 0 for the first to 1.
    var position: Double
  }

  /// A bibliography is left out, a whole section of one and a reference list inside
  /// another: its entries are titles of other documents, which would match every
  /// section that cites the same ones. So is a section with no prose of its own, a
  /// heading over its subsections or a section of only code or artwork, which
  /// `proseRuns` does not count: it could only pair by its title, which
  /// `minimumProse` exists to refuse.
  private static func profiles(of document: RFCDocument) -> [Profile] {
    let sections = document.allSections.filter { !$0.holdsOnlyReferences }
    let last = Double(max(sections.count - 1, 1))
    return sections.enumerated().compactMap { index, section in
      let title = words(in: section.titleText)
      let prose = section.blocks.flattened.flatMap { block -> [[Inline]] in
        if case .references = block { return [] }
        return block.proseRuns
      }
      let terms = prose.map(\.plainText).flatMap(words(in:))
        .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
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
    let shared = first.intersection(second).count
    let union = first.count + second.count - shared
    guard union > 0 else { return 0 }
    return Double(shared) / Double(union)
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

  /// A section's words weighed by how rare they are, scaled to length 1, in the order
  /// of the words. An array in a fixed order rather than a dictionary, whose order
  /// changes from run to run: the sums below would add in that order, and two runs
  /// over the same documents would write scores that differ in their last bits.
  private static func vector(
    of profile: Profile, weights: [String: Double]
  ) -> [(term: String, weight: Double)] {
    let weighted = profile.terms.keys.sorted().map { term in
      (term: term, weight: Double(profile.terms[term] ?? 0) * (weights[term] ?? 0))
    }
    let length = sqrt(weighted.reduce(0) { $0 + $1.weight * $1.weight })
    guard length > 0 else { return [] }
    return weighted.map { (term: $0.term, weight: $0.weight / length) }
  }

  /// The dot product of two vectors, walking both in the order of their words.
  private static func cosine(
    _ first: [(term: String, weight: Double)], _ second: [(term: String, weight: Double)]
  ) -> Double {
    var sum = 0.0
    var firstIndex = 0
    var secondIndex = 0
    while firstIndex < first.count, secondIndex < second.count {
      let firstTerm = first[firstIndex].term
      let secondTerm = second[secondIndex].term
      if firstTerm == secondTerm {
        sum += first[firstIndex].weight * second[secondIndex].weight
        firstIndex += 1
        secondIndex += 1
      } else if firstTerm < secondTerm {
        firstIndex += 1
      } else {
        secondIndex += 1
      }
    }
    return sum
  }
}
