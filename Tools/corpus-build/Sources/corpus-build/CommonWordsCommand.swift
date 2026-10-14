import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Measures in how many documents of the converted corpus each word is used, and
/// writes the common-word list the reader skips defined terms by (#396). Not part of
/// `make corpus`: the list is committed, and made again only when the threshold or
/// the corpus moves.
struct CommonWordsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "common-words",
    abstract: "Measure word frequency across the converted corpus, and write the common words."
  )

  private static let logger = Logger(command: "common-words")

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.xml files.")
  var input: String

  @Option(help: "Where to write the report of candidate thresholds.")
  var report: String

  @Option(help: "Where to write the common words, one per line; nothing is written without it.")
  var list: String?

  @Option(help: "The share of documents a word must be used in to be common.")
  var threshold: Double = 0.1

  func run() throws {
    let corpus = try ConvertedCorpus(directory: URL(fileURLWithPath: input))
    Self.logger.info("reading", metadata: ["documents": "\(corpus.files.count)"])

    var frequency = WordFrequency()
    let reading = try corpus.read { _, _, _, document in frequency.add(document) }
    Self.logger.report(reading)
    try writeJSON(
      frequency.report(thresholds: [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.3]), to: report)

    if let list {
      let words = frequency.commonWords(threshold: threshold)
      try (words.joined(separator: "\n") + "\n").write(
        to: URL(fileURLWithPath: list), atomically: true, encoding: .utf8)
      Self.logger.info(
        "wrote common words", metadata: ["words": "\(words.count)", "path": "\(list)"])
    }
    try Self.logger.failOnLeftOut(reading)
  }
}
