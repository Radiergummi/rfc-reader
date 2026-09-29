import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Writes the cross-reference judgement set used to measure search ranking (#37). What
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
    let files = try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: input), includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "xml" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    Self.logger.info("reading", metadata: ["documents": "\(files.count)"])

    var querySet = QuerySet()
    var unparseable = 0
    for (index, file) in files.enumerated() {
      guard let data = try? Data(contentsOf: file), let document = try? RFCXMLParser.parse(data)
      else {
        unparseable += 1
        continue
      }
      let id = document.header.id?.description ?? file.deletingPathExtension().lastPathComponent
      querySet.collect(document, id: id)
      if (index + 1) % 2000 == 0 {
        Self.logger.info(
          "progress", metadata: ["completed": "\(index + 1)", "total": "\(files.count)"])
      }
    }
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
