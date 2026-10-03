import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Writes the abbreviations the parser collects from every document of the converted
/// corpus, legacy and modern alike, with their totals (#211). A measure for the
/// precision check that comes before the reader shows expansions (#67), so it is not
/// part of `make corpus`.
struct AbbreviationsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "abbreviations",
    abstract: "Report the abbreviations the parser collects across the converted corpus."
  )

  private static let logger = Logger(command: "abbreviations")

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.xml files.")
  var input: String

  @Option(help: "Where to write the report.")
  var out: String

  func run() throws {
    let corpus = try ConvertedCorpus(directory: URL(fileURLWithPath: input))
    Self.logger.info("reading", metadata: ["documents": "\(corpus.files.count)"])

    var report = AbbreviationReport()
    let reading = try corpus.read { _, _, id, document in
      report.add(document.abbreviations, document: id.fileStem)
    }
    Self.logger.report(reading)
    try writeJSON(report, to: out)

    let totals = report.totals
    Self.logger.info(
      "wrote report",
      metadata: [
        "documents": "\(totals.documentsRead)", "withAny": "\(totals.documentsWithAny)",
        "abbreviations": "\(totals.abbreviations)", "path": "\(out)",
      ])
    // A document left out would be missing from the measure without a trace, so the
    // run fails once the rest is written, for the files to be looked at.
    try Self.logger.failOnLeftOut(reading)
  }
}
