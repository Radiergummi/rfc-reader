import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

struct ManifestCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "manifest",
    abstract: "Write the size and SHA-256 of every file in --dir to a manifest."
  )

  private static let logger = Logger(command: "manifest")

  @Option(help: "The directory of files the manifest lists.")
  var dir: String

  @Option(help: "Where to write the manifest.")
  var out: String

  @Option(help: "The data packs' version, such as 2026.09.")
  var version: String

  func run() throws {
    let directory = URL(fileURLWithPath: dir)
    let output = URL(fileURLWithPath: out)

    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    var entries: [Manifest.Entry] = []
    for name in names where !name.hasPrefix(".") {
      let data = try Data(contentsOf: directory.appending(path: name))
      entries.append(Manifest.Entry(path: name, data: data))
    }
    let manifest = Manifest(
      version: version, generatedAt: ISO8601DateFormatter().string(from: .now), files: entries)
    try writeJSON(manifest, to: output.path)
    Self.logger.info(
      "wrote manifest", metadata: ["entries": "\(entries.count)", "path": "\(output.path)"])
  }
}
