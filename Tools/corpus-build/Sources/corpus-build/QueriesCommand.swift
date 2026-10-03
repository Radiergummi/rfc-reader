import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Writes the cross-reference judgment set used to measure search ranking (#37). What
/// makes a citing sentence a query is `QuerySet`.
struct QueriesCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "queries",
    abstract: "Extract the cross-reference query set from the converted corpus."
  )

  private static let logger = Logger(command: "queries")

  @Option(name: .customLong("in"), help: "The directory of converted rfcNNNN.xml files.")
  var input: String

  @Option(help: "Where to write the query set.")
  var out: String

  @Option(help: "How many queries to sample.")
  var limit = 4000

  @Option(help: "The seed of the sample, so the set can be reproduced.")
  var seed: UInt64 = 11

  @Option(help: "The fewest content words a query may have.")
  var minWords = 8

  func run() throws {
    let corpus = try ConvertedCorpus(directory: URL(fileURLWithPath: input))
    Self.logger.info("reading", metadata: ["documents": "\(corpus.files.count)"])

    var querySet = QuerySet()
    // A file that does not parse costs the set its sentences, not the run: the set is
    // a sample.
    let reading = try corpus.read { offset, _, id, document in
      querySet.collect(document, id: id.description)
      if (offset + 1) % 2000 == 0 {
        Self.logger.info(
          "progress", metadata: ["completed": "\(offset + 1)", "total": "\(corpus.files.count)"])
      }
    }
    let unparseable = reading.unreadable.count
    Self.logger.info(
      "recovered citing sentences",
      metadata: ["sentences": "\(querySet.citingSentences)", "unparseable": "\(unparseable)"])

    let selection = querySet.select(limit: limit, seed: seed, minimumWords: minWords)
    for (reason, count) in selection.dropped.sorted(by: { $0.value > $1.value }) {
      Self.logger.info("dropped", metadata: ["reason": "\(reason)", "candidates": "\(count)"])
    }
    Self.logger.info("usable", metadata: ["candidates": "\(selection.usable)"])

    try writeJSON(selection.rows, to: out)
    Self.logger.info(
      "wrote queries", metadata: ["queries": "\(selection.rows.count)", "path": "\(out)"])
  }
}
