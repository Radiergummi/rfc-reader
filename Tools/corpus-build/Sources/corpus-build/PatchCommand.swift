import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit

struct PatchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "patch",
    abstract:
      "Write the override patch that turns the converter's output for one RFC into a hand-edited copy of it."
  )

  private static let logger = Logger(command: "patch")

  @Argument(help: "The document, such as rfc822.")
  var document: String

  @Option(help: "The hand-edited copy of the converter's output.")
  var edited: String

  @Option(
    help:
      "The converter's output, from a run without --overrides. By default corpus/xml.noindex/<document>.xml."
  )
  var original: String?

  @Option(help: "The directory to write <document>.xml into.")
  var overrides = "corpus/overrides"

  @Flag(name: .customLong("print"), help: "Write the patch to standard output instead.")
  var toStandardOutput = false

  func validate() throws {
    guard ConversionPlan.rfcNumber(of: document) != nil else {
      throw ValidationError("\(document) is not an RFC's file stem, such as rfc822.")
    }
  }

  func run() throws {
    let originalPath = original ?? "corpus/xml.noindex/\(document).xml"
    let name = "\(document).xml"
    let patch: String
    do {
      patch = try PatchWriter.patch(
        original: Data(contentsOf: URL(fileURLWithPath: originalPath)),
        edited: Data(contentsOf: URL(fileURLWithPath: edited)), name: name)
    } catch let failure as PatchWriter.Failure {
      Self.logger.error("no patch written", metadata: ["reason": "\(failure)"])
      throw ExitCode.failure
    }
    if toStandardOutput {
      print(patch, terminator: "")
      return
    }
    let output = URL(fileURLWithPath: overrides).appending(path: name)
    // Its reasons are written by hand, and would be lost.
    guard !FileManager.default.fileExists(atPath: output.path) else {
      Self.logger.error(
        "the override exists; --print writes the new patch to compare with it",
        metadata: ["path": "\(output.path)"])
      throw ExitCode.failure
    }
    try Data(patch.utf8).write(to: output)
    Self.logger.info(
      "wrote patch; replace each TODO comment with the operation's reason before committing it",
      metadata: ["path": "\(output.path)"])
  }
}
