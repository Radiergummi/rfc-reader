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
    #expect(CollectionExport.safeName(". .notes") == "notes")
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

  @Test func `a folder already there is never written into`() throws {
    let parent = Self.folder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let export = CollectionExport(Self.collection([.rfc(1)]), format: .pdf)
    #expect(export.unusedFolder(in: parent).lastPathComponent == "C")
    try FileManager.default.createDirectory(
      at: parent.appending(path: "C"), withIntermediateDirectories: true)
    #expect(export.unusedFolder(in: parent).lastPathComponent == "C 2")
    try FileManager.default.createDirectory(
      at: parent.appending(path: "C 2"), withIntermediateDirectories: true)
    #expect(export.unusedFolder(in: parent).lastPathComponent == "C 3")
  }

  @MainActor
  @Test func `a session writes into a folder of its own in the one chosen`() async throws {
    let parent = Self.folder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let session = CollectionExportSession()
    session.start(CollectionExport(Self.collection([.rfc(1)]), format: .markdown), in: parent) {
      _ in Data("x".utf8)
    }
    #expect(session.isExporting)
    await session.settle()
    guard case .finished(let report) = session.phase else {
      Issue.record("not finished")
      return
    }
    #expect(report.exported == [.rfc(1)])
    let folder = parent.appending(path: "C", directoryHint: .isDirectory)
    #expect(session.folder == folder)
    let file = folder.appending(path: ExportFormat.markdown.fileName(for: .rfc(1)))
    #expect(FileManager.default.fileExists(atPath: file.path))
  }

  @MainActor
  @Test func `a session that exported nothing leaves no folder`() async throws {
    let parent = Self.folder()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let session = CollectionExportSession()
    session.start(CollectionExport(Self.collection([.rfc(1)]), format: .pdf), in: parent) { _ in
      throw Unreachable()
    }
    await session.settle()
    #expect(session.folder == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
  }

  /// Cancel stops the export and says how far it came; what it wrote stays where
  /// it was written.
  @MainActor
  @Test func `a session canceled while exporting keeps what it wrote`() async throws {
    let parent = Self.folder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let session = CollectionExportSession()
    // Canceled while the first is made: it is kept, and the second never made.
    let plan = CollectionExport(Self.collection([.rfc(1), .rfc(2)]), format: .pdf)
    session.start(plan, in: parent) { id in
      #expect(id == .rfc(1))
      await session.cancel()
      return Data("x".utf8)
    }
    await session.settle()
    guard case .finished(let report) = session.phase else {
      Issue.record("not finished")
      return
    }
    #expect(report.wasCanceled)
    #expect(report.exported == [.rfc(1)])
    #expect(report.skipped.isEmpty)
    let file = try #require(session.folder).appending(path: ExportFormat.pdf.fileName(for: .rfc(1)))
    #expect(FileManager.default.fileExists(atPath: file.path))
  }
}
