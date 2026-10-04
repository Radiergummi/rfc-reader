import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit

// corpus-build: the offline half of RFC Reader's data pipeline.
//
// `corpus-build help` lists the commands and `corpus-build help <command>` what each
// option does; the Makefile's corpus targets show them in use. See docs/DATA_PIPELINE.md
// for the why and the pack layout.

@main
struct CorpusBuild: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "corpus-build",
    abstract: "The offline half of RFC Reader's data pipeline.",
    subcommands: [
      FetchCommand.self, ConvertCommand.self, ManifestCommand.self, QueriesCommand.self,
      ScoreCommand.self,
      RevisionsCommand.self, GroupsCommand.self, IndexCommand.self, AbbreviationsCommand.self,
    ]
  )
}

// MARK: - Support

/// `.sortedKeys` is what makes these files diffable between corpus runs, so the encoder
/// is configured in one place rather than at each call site. Slashes are left unescaped:
/// they are in paths, URLs and quoted prose, which is read by people as often as tools.
func writeJSON(_ value: some Encodable, to path: String) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
}

extension Logger {
  /// The logger of one command, labeled `corpus-build.<command>`. It writes to standard
  /// error, where progress and diagnostics have always gone, and is made with its handler
  /// rather than through `LoggingSystem.bootstrap`, whose default writes to standard
  /// output. Values go in metadata, so a message is the same text from run to run.
  init(command: String) {
    self.init(label: "corpus-build.\(command)") { label in
      StreamLogHandler.standardError(label: label)
    }
  }

  /// Logs each file reading `ConvertedCorpus` passed over or could not parse.
  func report(_ reading: ConvertedCorpus.Reading) {
    for file in reading.passedOver {
      info("not an RFC", metadata: ["file": "\(file.url.lastPathComponent)"])
    }
    for (file, error) in reading.unreadable {
      self.error(
        "unreadable", metadata: ["file": "\(file.url.lastPathComponent)", "error": "\(error)"])
    }
  }

  /// Fails the run when reading the corpus could not parse an RFC, naming each: called
  /// once the rest is written, for the files to be looked at.
  func failOnLeftOut(_ reading: ConvertedCorpus.Reading) throws {
    guard reading.unreadable.isEmpty else {
      let stems = reading.unreadable.map(\.file.stem)
      self.error("RFCs left out", metadata: ["documents": "\(stems.joined(separator: " "))"])
      throw ExitCode.failure
    }
  }
}
