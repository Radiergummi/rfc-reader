import CSQLite
import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The corpus-build binary, run as `make` and the corpus workflow run it. What is
/// tested here is the command line itself: which flags it accepts, and that `--only`
/// reaches the conversion. Which files it picks is `ConversionPlan`, and what a
/// conversion produces is `DocumentConverter`.
@Suite("Command line")
struct CommandLineTests {
  /// SwiftPM builds corpus-build beside the test bundle, because the test target depends
  /// on it. On Linux the bundle is the directory itself.
  private static let binary: URL = {
    let bundle = Bundle(for: BundleToken.self).bundleURL
    let directory =
      bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : bundle
    return directory.appending(path: "corpus-build")
  }()

  private final class BundleToken {}

  private static func run(_ arguments: [String]) throws -> (status: Int32, standardError: String) {
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    let pipe = Pipe()
    process.standardError = pipe
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    let standardError = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: standardError, as: UTF8.self))
  }

  private static func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "corpus-build-\(UUID().uuidString)")
  }

  /// The misspelling a lenient parser once ran with: `convert` without overrides, and
  /// exit status 0.
  @Test func `an unknown flag is rejected`() throws {
    let out = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: out) }

    let result = try Self.run([
      "convert", "--in", Fixtures.directory.path, "--out", out.path, "--overides",
      "corpus/overrides",
    ])
    #expect(result.status == 64, "EX_USAGE")
    #expect(result.standardError.contains("--overides"), "\(result.standardError)")
    #expect(!FileManager.default.fileExists(atPath: out.path), "nothing was converted")
  }

  /// A report from `--only` holds only the named documents. Written over the corpus
  /// report, it would become the next full run's baseline, and every document it left
  /// out would count as newly checked rather than as one that stopped validating.
  @Test func `only refuses a report`() throws {
    let out = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: out) }

    let result = try Self.run([
      "convert", "--in", Fixtures.directory.path, "--out", out.path, "--only", "2119",
      "--report", out.appending(path: "report.json").path,
    ])
    #expect(result.status == 64, "EX_USAGE")
    #expect(result.standardError.contains("--report"), "\(result.standardError)")
    #expect(!FileManager.default.fileExists(atPath: out.path), "nothing was converted")
  }

  @Test func `only converts the named documents`() throws {
    let out = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: out) }

    let result = try Self.run([
      "convert", "--in", Fixtures.directory.path, "--out", out.path, "--only", "2119", "1149",
    ])
    #expect(result.status == 0, "\(result.standardError)")
    let written = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
    #expect(written == ["rfc1149.xml", "rfc2119.xml"])

    let text = LegacyTextParser.text(
      decoding: try Data(contentsOf: Fixtures.url("rfc2119.txt")))
    let expected = DocumentConverter().convert(text: text, stem: "rfc2119", metadata: nil).xml
    #expect(try Data(contentsOf: out.appending(path: "rfc2119.xml")) == expected)
  }

  /// `--out` is where both files go; without it there is nowhere to write, and
  /// nothing may be fetched first.
  @Test func `revisions requires out`() throws {
    let result = try Self.run(["revisions"])
    #expect(result.status == 64, "EX_USAGE")
    #expect(result.standardError.contains("--out"), "\(result.standardError)")
  }

  /// `index` over the fixtures, whose XML is RFCs and also a sample of the RFC index
  /// and an RSS feed: the RFCs are indexed, and the rest is said and passed over.
  @Test func `index writes the citations of every RFC it reads`() throws {
    let out = Self.temporaryDirectory()
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: out) }
    let database = out.appending(path: "indexes.sqlite")

    let result = try Self.run([
      "index", "--in", Fixtures.directory.path, "--out", database.path, "--version", "test",
    ])
    #expect(result.status == 0, "\(result.standardError)")
    #expect(result.standardError.contains("rfcrss.xml"), "\(result.standardError)")

    var connection: OpaquePointer?
    #expect(sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    let sql = "SELECT count(*) FROM citations WHERE citing = 'RFC9290' AND cited = 'RFC7252'"
    #expect(sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 4)
  }
}
