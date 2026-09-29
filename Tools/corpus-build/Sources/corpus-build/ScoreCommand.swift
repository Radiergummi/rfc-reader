import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

struct ScoreCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "score",
    abstract:
      "Score the legacy parser on the text xml2rfc generated, against the XML it came from."
  )

  private static let logger = Logger(command: "score")

  @Option(help: "The directory of rfcNNNN.xml files, the ground truth.")
  var xml: String

  @Option(help: "The directory of the same RFCs' rfcNNNN.txt files, fetched as modern-text.")
  var text: String

  @Option(help: "Where to write the scores.")
  var out: String

  @Option(help: "How many of the worst documents to log.")
  var worst = 10

  /// The two files of one document.
  struct Pair: Sendable {
    var id: DocumentID
    var text: URL
    var xml: URL
  }

  func run() async throws {
    let textDirectory = URL(fileURLWithPath: text)
    let xmlDirectory = URL(fileURLWithPath: xml)
    // Every text with its XML beside it. A text without is skipped, and said so:
    // the XML fetch and this one can have been limited differently.
    let texts = try ConversionPlan.files(
      in: try FileManager.default.contentsOfDirectory(atPath: textDirectory.path))
    var pairs: [Pair] = []
    var unpaired = 0
    for name in texts {
      guard let number = ConversionPlan.rfcNumber(of: name) else { continue }
      let id = DocumentID.rfc(number)
      let xmlFile = xmlDirectory.appending(path: "\(id.fileStem).xml")
      guard FileManager.default.fileExists(atPath: xmlFile.path) else {
        unpaired += 1
        continue
      }
      pairs.append(Pair(id: id, text: textDirectory.appending(path: name), xml: xmlFile))
    }
    Self.logger.info(
      "scoring", metadata: ["documents": "\(pairs.count)", "unpaired": "\(unpaired)"])

    // Each pair is independent, and both parses are pure functions of their files.
    var scored: [(DocumentID, [GroundTruth.Kind: GroundTruth.Counts])] = []
    var failures = 0
    await withTaskGroup(
      of: (DocumentID, Result<[GroundTruth.Kind: GroundTruth.Counts], any Error>).self
    ) { group in
      var pending = pairs.makeIterator()
      func startNext() {
        guard let pair = pending.next() else { return }
        group.addTask { (pair.id, Result { try Self.score(pair) }) }
      }
      for _ in 0..<ProcessInfo.processInfo.activeProcessorCount { startNext() }
      for await (id, result) in group {
        switch result {
        case .success(let counts): scored.append((id, counts))
        case .failure(let error):
          failures += 1
          Self.logger.error("scoring failed", error: error, metadata: ["document": "\(id)"])
        }
        startNext()
      }
    }

    let report = GroundTruthReport(documents: scored)
    try writeJSON(report, to: out)
    for kind in GroundTruth.Kind.allCases {
      guard let total = report.kinds[kind.rawValue] else { continue }
      Self.logger.info(
        "scored",
        metadata: [
          "kind": "\(kind.rawValue)", "truePositives": "\(total.truePositives)",
          "falsePositives": "\(total.falsePositives)",
          "falseNegatives": "\(total.falseNegatives)",
          "precision": "\(total.precision.map(Self.percent) ?? "-")",
          "recall": "\(total.recall.map(Self.percent) ?? "-")",
        ])
    }
    for document in report.documents.prefix(worst) where document.errors > 0 {
      Self.logger.info(
        "worst", metadata: ["document": "\(document.document)", "errors": "\(document.errors)"])
    }
    Self.logger.info("wrote scores", metadata: ["path": "\(out)", "failures": "\(failures)"])
    if failures > 0 { throw ExitCode.failure }
  }

  /// The parser's blocks of the text against the XML's.
  private static func score(_ pair: Pair) throws -> [GroundTruth.Kind: GroundTruth.Counts] {
    let found = GroundTruth.blocks(of: LegacyTextParser.parse(try Data(contentsOf: pair.text)))
    let expected = GroundTruth.blocks(of: try RFCXMLParser.parse(try Data(contentsOf: pair.xml)))
    return GroundTruth.score(found: found, expected: expected)
  }

  private static func percent(_ ratio: Double) -> String {
    String(format: "%.1f%%", ratio * 100)
  }
}
