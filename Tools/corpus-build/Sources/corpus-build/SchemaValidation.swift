import Foundation
import RFCCorpusKit

/// Running xmllint for `SchemaCheck`: the half of the check that needs a process. What
/// a refused document contains is `SchemaCheck.causes(in:)`, in RFCCorpusKit.
extension SchemaCheck {
  /// Where it failed, when it did. `firstMessage` is only read for an unexplained
  /// failure, where libxml2's first line is the one lead there is.
  struct Result: Sendable {
    var causes: [Cause]
    var firstMessage: String?
  }

  /// Fails once, before a run, with what is actually wrong, rather than every document
  /// failing with xmllint's exit status: a schema path that does not resolve from here,
  /// or no xmllint on the path (libxml2-utils, on Linux).
  static func preflight(schema: URL) throws {
    guard FileManager.default.fileExists(atPath: schema.path) else {
      throw CheckError.schemaMissing(schema.path)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xmllint", "--version"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CheckError.xmllintMissing }
  }

  static func check(_ file: URL, schema: URL) async throws -> Result {
    guard try await !validates(file, schema: schema) else { return Result(causes: []) }
    let found = causes(in: try Data(contentsOf: file))
    guard found.isEmpty else { return Result(causes: found) }
    return Result(
      causes: [.unexplained], firstMessage: try await firstMessage(file, schema: schema))
  }

  private static func validates(_ file: URL, schema: URL) async throws -> Bool {
    // Only the exit status is read here: a failing document can write megabytes of
    // messages, and draining them costs more than the validation itself.
    let process = xmllint(file, schema: schema)
    process.standardError = FileHandle.nullDevice
    let status = try await exitStatus(of: process)
    switch status {
    case 0: return true
    case 3: return false  // XMLLINT_ERR_VALID
    default: throw CheckError.xmllintFailed(file.lastPathComponent, status)
    }
  }

  private static func firstMessage(_ file: URL, schema: URL) async throws -> String? {
    let process = xmllint(file, schema: schema)
    let pipe = Pipe()
    process.standardError = pipe
    var data = Data()
    // Drained while it runs, or a document with more messages than the pipe buffers
    // never exits. This blocks a thread, but only for an unexplained failure.
    _ = try await exitStatus(of: process) { data = pipe.fileHandleForReading.readDataToEndOfFile() }
    // Without the path, which differs between runs and would move every report that has one.
    let first = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init)
    return first.map { $0.replacingOccurrences(of: file.path, with: file.lastPathComponent) }
  }

  /// Runs `process` and suspends until it exits, without holding a thread meanwhile.
  /// `waitUntilExit` runs the current run loop until the child is gone -- in
  /// swift-corelibs-foundation, in 50 ms slices -- and it did so on a thread of the
  /// cooperative pool the conversions share, one fewer to parse on per xmllint running.
  private static func exitStatus(of process: Process, whileRunning body: () -> Void = {})
    async throws -> Int32
  {
    try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
        return
      }
      body()
    }
  }

  private static func xmllint(_ file: URL, schema: URL) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xmllint", "--noout", "--relaxng", schema.path, file.path]
    process.standardOutput = FileHandle.nullDevice
    return process
  }

  enum CheckError: Error, CustomStringConvertible {
    case xmllintFailed(String, Int32)
    case schemaMissing(String)
    case xmllintMissing

    var description: String {
      switch self {
      case .xmllintFailed(let file, let status): "xmllint exited \(status) on \(file)"
      case .schemaMissing(let path):
        "no schema at \(path) (relative paths resolve from the working directory)"
      case .xmllintMissing: "xmllint is not on the path; on Linux it is libxml2-utils"
      }
    }
  }
}
