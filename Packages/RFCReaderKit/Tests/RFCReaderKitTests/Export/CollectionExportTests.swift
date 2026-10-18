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

  @Test func `the folder is the collection's, and each file is named as one export names it`() {
    let export = CollectionExport(
      collection: "HTTP", members: [.rfc(9110), .rfc(9111)], format: .pdf)
    #expect(export.folderName == "HTTP")
    #expect(export.files.map(\.name) == ["RFC-9110.pdf", "RFC-9111.pdf"])
  }

  @Test func `a name that would make a path or hide the folder is made safe`() {
    #expect(CollectionExport.safeName("TLS/QUIC: notes") == "TLS-QUIC- notes")
    #expect(CollectionExport.safeName(".hidden") == "hidden")
    #expect(CollectionExport.safeName("  ") == "RFCs")
  }

  /// A collection's list shows its RFCs; a series it holds is not exported, and
  /// nothing is exported twice.
  @Test func `only the RFCs are exported, each once, in order`() {
    let export = CollectionExport(
      collection: "C", members: [.rfc(2), DocumentID(series: .bcp, number: 14), .rfc(1), .rfc(2)],
      format: .markdown)
    #expect(export.files.map(\.document) == [.rfc(2), .rfc(1)])
  }

  @Test func `a grammar is not offered for a collection`() {
    #expect(!CollectionExport.formats.contains(.abnf))
  }

  @Test func `a document that fails is skipped and named, and the rest are written`() async throws {
    let folder = Self.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let export = CollectionExport(
      collection: "C", members: [.rfc(1), .rfc(2), .rfc(3)], format: .markdown)
    let seen = Mutex<[CollectionExport.Progress]>([])
    let report = try await export.run(into: folder) { progress in
      seen.withLock { $0.append(progress) }
    } make: { id in
      if id == .rfc(2) { throw Unreachable() }
      return Data(id.displayName.utf8)
    }
    #expect(report.exported == [.rfc(1), .rfc(3)])
    #expect(report.skippedLines == ["RFC 2: It could not be reached."])
    #expect(!report.wasCancelled)
    #expect(seen.withLock { $0.map(\.done) } == [0, 1, 2, 3])
    let written = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(written == ["RFC-1.md", "RFC-3.md"])
  }

  @Test func `a cancelled export stops and says so`() async throws {
    let folder = Self.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let export = CollectionExport(
      collection: "C", members: [.rfc(1), .rfc(2), .rfc(3)], format: .markdown)
    let report = try await export.run(into: folder) { _ in
    } make: { id in
      if id == .rfc(2) { throw CancellationError() }
      return Data()
    }
    #expect(report.exported == [.rfc(1)])
    #expect(report.wasCancelled)
  }
}
