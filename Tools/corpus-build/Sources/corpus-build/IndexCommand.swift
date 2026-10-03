import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// Writes the corpus's index database (#174): what `IndexDatabase` holds, computed
/// over every document of the converted corpus, legacy and modern alike.
struct IndexCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index",
    abstract: "Write the index database of the converted corpus."
  )

  private static let logger = Logger(command: "index")

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.xml files.")
  var input: String

  @Option(help: "Where to write the database.")
  var out: String

  @Option(help: "The data packs' version, such as 2026.09.")
  var version: String

  func run() throws {
    let files = try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: input), includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "xml" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    Self.logger.info("reading", metadata: ["documents": "\(files.count)"])

    let clock = ContinuousClock()
    let started = clock.now
    let database = try IndexDatabase(creatingAt: URL(fileURLWithPath: out))
    try database.setMeta("version", to: version)
    var indexed = 0
    var citations = 0
    var failed: [String] = []
    for (index, file) in files.enumerated() {
      let stem = file.deletingPathExtension().lastPathComponent
      // A document is the one its file names: a converted header may lack its number,
      // or state another one, and two files must not index as the same document.
      guard let id = DocumentID(fileStem: stem) else {
        Self.logger.info("not an RFC", metadata: ["file": "\(file.lastPathComponent)"])
        continue
      }
      let document: RFCDocument
      do {
        document = try RFCXMLParser.parse(Data(contentsOf: file))
      } catch {
        Self.logger.error(
          "unreadable", metadata: ["file": "\(file.lastPathComponent)", "error": "\(error)"])
        failed.append(stem)
        continue
      }
      let cited = Citations.of(document, citing: id)
      try database.insert(cited, citing: id)
      indexed += 1
      citations += cited.count
      if (index + 1) % 2000 == 0 {
        Self.logger.info(
          "progress", metadata: ["completed": "\(index + 1)", "total": "\(files.count)"])
      }
    }
    try database.setMeta("documents", to: String(indexed))
    try database.close()

    let size = try FileManager.default.attributesOfItem(atPath: out)[.size] as? Int ?? 0
    Self.logger.info(
      "wrote index",
      metadata: [
        "documents": "\(indexed)", "citations": "\(citations)", "bytes": "\(size)",
        "duration": "\(clock.now - started)", "path": "\(out)",
      ])
    // An RFC left out is a gap in the graph nothing else would show, so the run fails
    // once the rest is written, for the files to be looked at.
    guard failed.isEmpty else {
      Self.logger.error(
        "RFCs left out", metadata: ["documents": "\(failed.joined(separator: " "))"])
      throw ExitCode.failure
    }
  }
}
