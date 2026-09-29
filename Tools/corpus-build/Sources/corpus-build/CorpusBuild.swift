import ArgumentParser
import Foundation
import Logging

// corpus-build: the offline half of RFC Reader's data pipeline.
//
//   corpus-build fetch    --out corpus [--format text|xml|modern-text] [--index rfc-index.xml] [--limit N] [--concurrency 6]
//   corpus-build convert  --in corpus/text.noindex --out corpus/xml.noindex [--overrides corpus/overrides] [--report corpus/report.json]
//                         [--index corpus/rfc-index.xml] [--only 5 822 ...]
//                         [--diagnostics corpus/prose.json] [--schema Tools/corpus-build/Schema/v3.rng]
//   corpus-build manifest --dir corpus/xml.noindex --out corpus/manifest.json --version 2026.09
//   corpus-build queries  --in corpus/xml.noindex --out Tools/corpus-build/Evaluation/queries-xref.json
//                         [--limit 4000] [--seed 11] [--min-words 8]
//   corpus-build score    --xml corpus/xml.noindex --text corpus/modern-text.noindex --out corpus/score.json
//   corpus-build revisions --out corpus/revisions [--scan corpus/revisions/revisions-scan.json] [--allow-shrink]
//
// `corpus-build help <command>` says what each option does. See docs/DATA_PIPELINE.md
// for the why and the pack layout.

@main
struct CorpusBuild: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "corpus-build",
    abstract: "The offline half of RFC Reader's data pipeline.",
    subcommands: [
      FetchCommand.self, ConvertCommand.self, ManifestCommand.self, QueriesCommand.self,
      ScoreCommand.self,
      RevisionsCommand.self,
    ]
  )
}

// MARK: - Support

enum PipelineError: Error, CustomStringConvertible {
  case http(Int, URL)

  var description: String {
    switch self {
    case .http(let status, let url): "HTTP \(status) for \(url)"
    }
  }
}

/// `.sortedKeys` is what makes these files diffable between corpus runs, so the encoder
/// is configured in one place rather than at each of the three call sites.
func writeJSON(_ value: some Encodable, to path: String) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
}

extension Logger {
  /// The logger of one command, labelled `corpus-build.<command>`. It writes to standard
  /// error, where progress and diagnostics have always gone, and is made with its handler
  /// rather than through `LoggingSystem.bootstrap`, whose default writes to standard
  /// output. Values go in metadata, so a message is the same text from run to run.
  init(command: String) {
    self.init(label: "corpus-build.\(command)") { label in
      StreamLogHandler.standardError(label: label)
    }
  }
}
