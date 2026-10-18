import Foundation
import RFCKit

/// Every RFC of a collection saved at once, in one format, into a folder named
/// after the collection (#385). Decided 2026-10-07: a folder on both platforms,
/// each file named as a single export names it, one progress for the whole export
/// that can be cancelled, and a document that fails skipped and named at the end,
/// never the export abandoned.
public struct CollectionExport: Sendable {
  /// The folder's name: the collection's, made safe for a file's.
  public let folderName: String
  /// Each document and its file's name, in the collection's order, each once.
  public let files: [File]
  public let format: ExportFormat

  public struct File: Sendable, Equatable {
    public let document: DocumentID
    public let name: String
  }

  /// - Parameter members: the collection's documents in its order; only its RFCs
  ///   are exported, which are what its list shows.
  public init(collection name: String, members: [DocumentID], format: ExportFormat) {
    self.format = format
    folderName = Self.safeName(name)
    var seen: Set<DocumentID> = []
    files = members.filter { $0.series == .rfc && seen.insert($0).inserted }.map {
      File(document: $0, name: format.fileName(for: $0))
    }
  }

  /// The formats a collection is exported in: every one each document has, which
  /// a grammar is not.
  public static let formats = ExportFormat.everyDocument

  /// `name` as a folder's: no `/` or `:`, which name a path, no leading dot, which
  /// hides it, and never empty.
  static func safeName(_ name: String) -> String {
    let replaced = name.map { $0 == "/" || $0 == ":" ? "-" : $0 }
    let trimmed = String(replaced).trimmingCharacters(in: .whitespacesAndNewlines)
      .drop { $0 == "." }
    return trimmed.isEmpty ? "RFCs" : String(trimmed)
  }

  /// How far an export has come: what the progress shows.
  public struct Progress: Sendable, Equatable {
    public var done: Int
    public let total: Int

    public init(done: Int, total: Int) {
      self.done = done
      self.total = total
    }
  }

  /// What an export ended with.
  public struct Report: Sendable {
    public var exported: [DocumentID] = []
    /// Each document that could not be exported, and why, in words.
    public var skipped: [(document: DocumentID, reason: String)] = []
    /// Whether the export was cancelled before it had made every file.
    public var wasCancelled = false

    public init() {}

    /// `RFC 9110: The resource could not be found.`, one per skipped document.
    public var skippedLines: [String] {
      skipped.map { "\($0.document.displayName): \($0.reason)" }
    }
  }

  /// Makes each file with `make` and writes it into `folder`, which is created,
  /// telling `progress` after each. A document `make` fails on is skipped and
  /// reported; a cancelled task stops before the next document and reports what was
  /// made.
  public func run(
    into folder: URL,
    progress: @Sendable (Progress) async -> Void,
    make: @Sendable (DocumentID) async throws -> Data
  ) async throws -> Report {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var report = Report()
    await progress(Progress(done: 0, total: files.count))
    for (index, file) in files.enumerated() {
      if Task.isCancelled {
        report.wasCancelled = true
        break
      }
      do {
        let data = try await make(file.document)
        try data.write(to: folder.appending(path: file.name), options: .atomic)
        report.exported.append(file.document)
      } catch is CancellationError {
        report.wasCancelled = true
        break
      } catch {
        report.skipped.append((file.document, error.localizedDescription))
      }
      await progress(Progress(done: index + 1, total: files.count))
    }
    return report
  }
}
