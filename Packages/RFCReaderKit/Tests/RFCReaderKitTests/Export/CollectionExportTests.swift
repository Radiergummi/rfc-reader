import Foundation
import RFCKit
import Synchronization
import Testing

@testable import RFCReaderKit

/// A collection exported into a folder of its own (#385).
@Suite("Export: a collection")
struct CollectionExportTests {
  private struct Unreachable: LocalizedError {
    var errorDescription: String? { "It could not be reached." }
  }

  private static func folder() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "CollectionExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private static func collection(_ members: [DocumentID], name: String = "C")
    -> CollectionSnapshot.Entry
  {
    CollectionSnapshot.Entry(id: UUID(), name: name, color: .default, members: members)
  }

  @Test func `the folder is the collection's, and each file is named as one export names it`() {
    let export = CollectionExport(
      Self.collection([.rfc(9110), .rfc(9111)], name: "HTTP"), format: .pdf)
    #expect(export.folderName == "HTTP")
    #expect(export.files.map(\.name) == ["RFC-9110.pdf", "RFC-9111.pdf"])
  }

  @Test func `a name that would make a path, hide the folder or run too long is made safe`() {
    #expect(CollectionExport.safeName("TLS/QUIC: notes") == "TLS-QUIC- notes")
    #expect(CollectionExport.safeName(". hidden") == "hidden")
    #expect(CollectionExport.safeName("  ") == "RFCs")
    let long = CollectionExport.safeName(String(repeating: "é", count: 300))
    #expect(long.utf8.count <= 255)
    #expect(!long.isEmpty)
  }

  /// A collection's list shows its RFCs; a series it holds is not exported.
  @Test func `only the RFCs are exported, in order`() {
    let export = CollectionExport(
      Self.collection([.rfc(2), DocumentID(series: .bcp, number: 14), .rfc(1)]), format: .markdown)
    #expect(export.files.map(\.document) == [.rfc(2), .rfc(1)])
  }

  @Test func `a grammar is not offered for a collection`() {
    #expect(!CollectionExport.formats.contains(.abnf))
  }

  @Test func `a document that fails is skipped and named, and the rest are written`() async throws {
    let folder = Self.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let export = CollectionExport(Self.collection([.rfc(1), .rfc(2), .rfc(3)]), format: .markdown)
    let seen = Mutex<[CollectionExport.Progress]>([])
    let report = try await export.run(into: folder) { progress in
      seen.withLock { $0.append(progress) }
    } make: { id in
      if id == .rfc(2) { throw Unreachable() }
      return Data(id.displayName.utf8)
    }
    #expect(report.exported == [.rfc(1), .rfc(3)])
    #expect(report.skippedLines == ["RFC 2: It could not be reached."])
    #expect(!report.wasCanceled)
    #expect(seen.withLock { $0.map(\.done) } == [0, 1, 2, 3])
    let written = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(written == ["RFC-1.md", "RFC-3.md"])
  }

  /// A cancellation from inside one document's export is that document's failure:
  /// only the export's own task being canceled stops it.
  @Test func `a cancellation error from one document skips only that document`() async throws {
    let folder = Self.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let export = CollectionExport(Self.collection([.rfc(1), .rfc(2), .rfc(3)]), format: .markdown)
    let report = try await export.run(into: folder) { _ in
    } make: { id in
      if id == .rfc(2) { throw CancellationError() }
      return Data()
    }
    #expect(report.exported == [.rfc(1), .rfc(3)])
    #expect(report.skipped.map(\.document) == [.rfc(2)])
    #expect(!report.wasCanceled)
  }

  @MainActor
  @Test func `a session finishes with the folder of what it made`() async throws {
    let workspace = Self.folder()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let session = CollectionExportSession(workspace: workspace)
    session.start(CollectionExport(Self.collection([.rfc(1)]), format: .markdown)) { _ in
      Data("x".utf8)
    }
    #expect(session.isExporting)
    await session.settle()
    guard case .finished(let report) = session.phase else {
      Issue.record("not finished")
      return
    }
    #expect(report.exported == [.rfc(1)])
    #expect(session.folder == workspace.appending(path: "C", directoryHint: .isDirectory))
    session.end()
    #expect(!FileManager.default.fileExists(atPath: workspace.path))
  }

  @MainActor
  @Test func `a session that exported nothing has no folder to save`() async {
    let workspace = Self.folder()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let session = CollectionExportSession(workspace: workspace)
    session.start(CollectionExport(Self.collection([.rfc(1)]), format: .pdf)) { _ in
      throw Unreachable()
    }
    await session.settle()
    #expect(session.folder == nil)
  }

  @MainActor
  @Test func `a session ended while exporting removes what it made`() async {
    let workspace = Self.folder()
    let session = CollectionExportSession(workspace: workspace)
    session.start(CollectionExport(Self.collection([.rfc(1), .rfc(2)]), format: .pdf)) { _ in
      try await Task.sleep(for: .milliseconds(50))
      return Data()
    }
    session.end()
    await session.settle()
    #expect(!FileManager.default.fileExists(atPath: workspace.path))
  }
}
