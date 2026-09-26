import ArgumentParser
import Foundation

// corpus-build: the offline half of RFC Reader's data pipeline.
//
//   corpus-build fetch    --out corpus [--format text|xml] [--index rfc-index.xml] [--limit N] [--concurrency 6]
//   corpus-build convert  --in corpus/text.noindex --out corpus/xml.noindex [--overrides corpus/overrides] [--report corpus/report.json]
//                         [--index corpus/rfc-index.xml] [--only 5 822 ...]
//                         [--diagnostics corpus/prose.json] [--schema Tools/corpus-build/Schema/v3.rng]
//   corpus-build manifest --dir corpus/xml.noindex --out corpus/manifest.json --version 2026.09
//   corpus-build queries  --in corpus/xml.noindex --out Tools/corpus-build/Evaluation/queries-xref.json
//                         [--limit 4000] [--seed 11] [--min-words 8]
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
    ]
  )
}

// MARK: - Support

enum PipelineError: Error, CustomStringConvertible {
  case http(Int, URL)
  case missingInput([Int])

  var description: String {
    switch self {
    case .http(let status, let url): "HTTP \(status) for \(url)"
    case .missingInput(let numbers):
      "no text in --in for \(numbers.map { "rfc\($0)" }.joined(separator: ", "))"
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

func log(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}
