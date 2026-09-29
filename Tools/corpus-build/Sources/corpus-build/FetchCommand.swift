import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

struct FetchCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "fetch",
    abstract:
      "Download the RFC index, and every RFC it lists in one format that is not yet in --out."
  )

  /// The two disjoint halves of the corpus, fetched the same way (`FetchPlan`).
  enum Format: String, ExpressibleByArgument, CaseIterable {
    case text
    case xml

    var fileFormat: FileFormat {
      switch self {
      case .text: .text
      case .xml: .xml
      }
    }

    /// The directory inside `--out` this half of the corpus lands in.
    var directoryName: String {
      switch self {
      case .text: "text.noindex"
      case .xml: "xml.noindex"
      }
    }
  }

  private static let logger = Logger(command: "fetch")

  @Option(help: "The corpus directory. Documents land in text.noindex or xml.noindex inside it.")
  var out: String

  @Option(help: "Which half of the corpus to fetch.")
  var format: Format = .text

  @Option(help: "Read the RFC index from here instead of downloading it into --out.")
  var index: String?

  @Option(help: "Fetch only the first this many documents of the index.")
  var limit: Int?

  @Option(help: "How many downloads to run at once.")
  var concurrency = 6

  func run() async throws {
    let outDirectory = URL(fileURLWithPath: out)
    let fileFormat = format.fileFormat
    let directory = outDirectory.appending(path: format.directoryName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let index: RFCIndex
    if let path = self.index {
      Self.logger.info("reading index", metadata: ["path": "\(path)"])
      index = try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: path))
    } else {
      Self.logger.info("downloading index", metadata: ["url": "\(RFCEditorEndpoints.index)"])
      let data = try await Self.client.fetchIndexData()
      try data.write(to: outDirectory.appending(path: "rfc-index.xml"), options: .atomic)
      index = try RFCIndexParser.parse(data)
    }

    let wanted = FetchPlan.wanted(in: index, format: fileFormat, limit: limit)
    let suffix = fileFormat.pathExtension
    let missing = wanted.filter {
      !FileManager.default.fileExists(
        atPath: directory.appending(path: "\($0.fileStem).\(suffix)").path)
    }
    Self.logger.info(
      "planned",
      metadata: [
        "format": "\(self.format.rawValue)", "wanted": "\(wanted.count)",
        "missing": "\(missing.count)",
      ])

    var failures = 0
    var completed = 0
    try await withThrowingTaskGroup(of: (DocumentID, Result<Data, any Error>).self) { group in
      var iterator = missing.makeIterator()
      func enqueue() {
        guard let id = iterator.next() else { return }
        group.addTask {
          do {
            return (
              id,
              .success(try await Self.client.fetchDocumentData(id, format: fileFormat))
            )
          } catch { return (id, .failure(error)) }
        }
      }
      for _ in 0..<concurrency { enqueue() }
      while let (id, result) = try await group.next() {
        switch result {
        case .success(let data):
          try data.write(
            to: directory.appending(path: "\(id.fileStem).\(suffix)"), options: .atomic)
        case .failure(let error):
          failures += 1
          Self.logger.error("download failed", error: error, metadata: ["document": "\(id)"])
        }
        completed += 1
        if completed % 250 == 0 {
          Self.logger.info(
            "progress", metadata: ["completed": "\(completed)", "total": "\(missing.count)"])
        }
        enqueue()
      }
    }
    Self.logger.info(
      "done", metadata: ["fetched": "\(completed - failures)", "failures": "\(failures)"])
    if failures > 0 { throw ExitCode.failure }
  }

  /// The RFC Editor's client, naming this tool in its User-Agent and retrying what
  /// can pass (`RetryingTransport`).
  private static let client = RFCEditorClient(
    transport: RetryingTransport(URLSessionTransport(userAgent: RetryingTransport.userAgent)))
}
