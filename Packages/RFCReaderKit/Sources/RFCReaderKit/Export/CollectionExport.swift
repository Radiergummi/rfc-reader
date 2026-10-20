import Foundation
import Observation
import RFCKit

/// Every RFC of a collection saved at once, in one format, into a folder named
/// after the collection (#385). Decided 2026-10-07: a folder on both platforms,
/// each file named as a single export names it, one progress for the whole export
/// that can be canceled, and a document that fails skipped and named at the end,
/// never the export abandoned.
public struct CollectionExport: Sendable {
  /// The folder's name: the collection's, made safe for a file's.
  public let folderName: String
  /// Each document and its file's name, in the collection's order.
  public let files: [File]
  public let format: ExportFormat

  public struct File: Sendable, Equatable {
    public let document: DocumentID
    public let name: String
  }

  /// The collection's RFCs, which are what its list shows.
  public init(_ collection: CollectionSnapshot.Entry, format: ExportFormat) {
    self.format = format
    folderName = Self.safeName(collection.name)
    files = collection.rfcNumbers.map(DocumentID.rfc).map {
      File(document: $0, name: format.fileName(for: $0))
    }
  }

  /// The formats a collection is exported in: every one each document has, which
  /// a grammar is not.
  public static let formats = ExportFormat.everyDocument

  /// The longest name a folder can have, in UTF-8 bytes, as the file systems the
  /// app saves to allow.
  static let longestName = 255

  /// `name` as a folder's: no `/` or `:`, which name a path, no leading dot, which
  /// hides it, no longer than a file system allows, and never empty.
  static func safeName(_ name: String) -> String {
    let replaced = String(name.map { $0 == "/" || $0 == ":" ? "-" : $0 })
    // Dots and spaces both, in any order: `. .notes` would be hidden too.
    var safe = String(replaced.drop { $0 == "." || $0.isWhitespace })
      .trimmingCharacters(in: .whitespacesAndNewlines)
    while safe.utf8.count > longestName { safe.removeLast() }
    safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
    return safe.isEmpty ? "RFCs" : safe
  }

  /// The folder in `parent` the export makes: named after the collection, or
  /// `HTTP 2`, `HTTP 3` and on, as the Finder names a copy, when that is there, so
  /// an earlier export's files are never written over.
  public func unusedFolder(in parent: URL) -> URL {
    var number = 1
    while true {
      let name = number == 1 ? folderName : "\(folderName) \(number)"
      let folder = parent.appending(path: name, directoryHint: .isDirectory)
      if !FileManager.default.fileExists(atPath: folder.path) { return folder }
      number += 1
    }
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
    /// Whether the export was canceled before it had made every file.
    public var wasCanceled = false

    public init() {}

    /// `RFC 9110: The resource could not be found.`, one per skipped document.
    public var skippedLines: [String] {
      skipped.map { "\($0.document.displayName): \($0.reason)" }
    }
  }

  /// Makes each file with `make` and writes it into `folder`, which is created,
  /// telling `progress` after each, off the caller's actor. A document `make` fails
  /// on is skipped and reported, whatever the error; only the task's own
  /// cancellation stops the export, before the next document, and the report says
  /// what was made.
  @concurrent
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
        report.wasCanceled = true
        break
      }
      do {
        let data = try await make(file.document)
        try data.write(to: folder.appending(path: file.name), options: .atomic)
        report.exported.append(file.document)
      } catch {
        if Task.isCancelled {
          report.wasCanceled = true
          break
        }
        report.skipped.append((file.document, error.localizedDescription))
      }
      await progress(Progress(done: index + 1, total: files.count))
    }
    return report
  }
}

/// A collection export under way, for the sheet that shows it (#385): its phase,
/// and the task writing its files straight into the folder the reader chose, so
/// that what is exported is where they asked for it, with nothing left to save.
@MainActor
@Observable
public final class CollectionExportSession {
  public enum Phase {
    case choosing
    case exporting(CollectionExport.Progress)
    case finished(CollectionExport.Report)
  }

  public private(set) var phase = Phase.choosing
  /// The folder the export made, once anything is in it: what the sheet names.
  public private(set) var folder: URL?
  private var task: Task<Void, Never>?

  public init() {}

  public var isExporting: Bool {
    if case .exporting = phase { true } else { false }
  }

  /// Makes `plan`'s files with `make`, in a folder of their own in `parent`, which
  /// the reader picked and may be outside the sandbox. A failure to start, such as
  /// a folder that cannot be made, is every document skipped for it; a folder
  /// nothing was written into is removed.
  public func start(
    _ plan: CollectionExport, in parent: URL,
    make: @escaping @Sendable (DocumentID) async throws -> Data
  ) {
    let folderURL = plan.unusedFolder(in: parent)
    phase = .exporting(CollectionExport.Progress(done: 0, total: plan.files.count))
    task = Task {
      let isAccessing = parent.startAccessingSecurityScopedResource()
      defer { if isAccessing { parent.stopAccessingSecurityScopedResource() } }
      let report: CollectionExport.Report
      do {
        report = try await plan.run(
          into: folderURL, progress: { progress in await self.show(progress) }, make: make)
      } catch {
        var failed = CollectionExport.Report()
        failed.skipped = plan.files.map { ($0.document, error.localizedDescription) }
        report = failed
      }
      if report.exported.isEmpty {
        // Made by this export a moment ago, and empty: nothing of the reader's.
        try? FileManager.default.removeItem(at: folderURL)
      } else {
        folder = folderURL
      }
      phase = .finished(report)
    }
  }

  private func show(_ progress: CollectionExport.Progress) {
    if isExporting { phase = .exporting(progress) }
  }

  /// Stops the export under way before its next document; it finishes with a
  /// report of what it wrote, which stays where it was written.
  public func cancel() {
    task?.cancel()
  }

  /// Waits for the export under way, for a test.
  func settle() async {
    await task?.value
  }
}
