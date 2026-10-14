import Foundation
import RFCKit

/// In how many documents each word appears in prose, across the corpus, and how that
/// bears on the terms documents define (#396): the reader skips a defined term that is
/// a common English word, `client` or `message`, which every reader knows and almost
/// every document defines its own way.
///
/// A word is a run of letters and digits, with a hyphen or apostrophe inside it, as it
/// is written: `Client` at the start of a sentence is another word than `client`. Only
/// the words written in lower-case letters can be common English words; `TLS` is used
/// in many documents and is still no English word.
public struct WordFrequency: Sendable {
  public private(set) var documentsRead = 0
  /// How many documents use each lower-case word in prose.
  public private(set) var documentFrequency: [String: Int] = [:]
  /// How many documents define each single-word term, by its spelling.
  public private(set) var definedSingleWords: [String: Int] = [:]

  public init() {}

  public mutating func add(_ document: RFCDocument) {
    documentsRead += 1
    var words: Set<String> = []
    func read(_ blocks: [Block]) {
      for block in blocks.flattened {
        if case .references = block { continue }
        for run in block.proseRuns {
          words.formUnion(Self.words(in: run.plainText).filter(Self.isLowercaseWord))
        }
      }
    }
    read(document.header.abstract)
    for section in document.allSections { read(section.blocks) }
    for word in words { documentFrequency[word, default: 0] += 1 }
    for term in document.definedTerms.keys where !term.contains(where: \.isWhitespace) {
      definedSingleWords[term, default: 0] += 1
    }
  }

  /// The lower-case words used in at least `threshold` of the documents read, in
  /// order: the common-word list the reader ships.
  public func commonWords(threshold: Double) -> [String] {
    let least = Self.least(threshold, of: documentsRead)
    return documentFrequency.filter { $0.value >= least }.keys.sorted()
  }

  /// What each candidate threshold would make common, for choosing one.
  public func report(thresholds: [Double], sampleLimit: Int = 300) -> WordFrequencyReport {
    let terms = definedSingleWords.map { term, defining in
      WordFrequencyReport.Term(
        term: term, definingDocuments: defining,
        share: Double(documentFrequency[term] ?? 0) / Double(max(documentsRead, 1)))
    }
    .sorted { $0.share != $1.share ? $0.share > $1.share : $0.term < $1.term }
    let cuts = thresholds.map { threshold in
      let least = Self.least(threshold, of: documentsRead)
      let skipped = terms.filter { (documentFrequency[$0.term] ?? 0) >= least }
      return WordFrequencyReport.Cut(
        threshold: threshold,
        commonWords: documentFrequency.values.filter { $0 >= least }.count,
        skippedTerms: skipped.count,
        skippedDefinitions: skipped.reduce(0) { $0 + $1.definingDocuments })
    }
    return WordFrequencyReport(
      documentsRead: documentsRead, definedSingleWords: terms.count, cuts: cuts,
      terms: Array(terms.prefix(sampleLimit)))
  }

  /// The words of `text`, as `WordFrequency` counts them.
  public static func words(in text: String) -> [String] {
    var words: [String] = []
    var current = ""
    func end() {
      while current.last == "-" || current.last == "'" { current.removeLast() }
      if !current.isEmpty { words.append(current) }
      current = ""
    }
    for character in text {
      if character.isLetter || character.isNumber {
        current.append(character)
      } else if character == "-" || character == "'", !current.isEmpty {
        current.append(character)
      } else {
        end()
      }
    }
    end()
    return words
  }

  static func isLowercaseWord(_ word: String) -> Bool {
    word.first?.isLowercase == true && word.allSatisfy { $0.isLowercase || $0 == "-" || $0 == "'" }
  }

  /// The fewest documents a word must appear in to be used in `threshold` of `count`.
  private static func least(_ threshold: Double, of count: Int) -> Int {
    max(1, Int((threshold * Double(count)).rounded(.up)))
  }
}

/// What `WordFrequency.report(thresholds:)` says each candidate threshold would make
/// common.
public struct WordFrequencyReport: Encodable, Sendable {
  public var documentsRead: Int
  /// How many different single-word spellings documents define.
  public var definedSingleWords: Int
  public var cuts: [Cut]
  /// The single-word terms used in the most documents, most first, with that share.
  public var terms: [Term]

  public struct Cut: Encodable, Sendable {
    public var threshold: Double
    public var commonWords: Int
    /// How many of the defined single-word spellings it would skip.
    public var skippedTerms: Int
    /// And how many definitions those are, counting each document that defines one.
    public var skippedDefinitions: Int
  }

  public struct Term: Encodable, Sendable {
    public var term: String
    public var definingDocuments: Int
    /// The share of documents that use it in prose.
    public var share: Double
  }
}
