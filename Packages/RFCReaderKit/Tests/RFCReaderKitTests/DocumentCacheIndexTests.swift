import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The in-memory record of which documents the on-disk cache holds (#39). Seeded
/// from one directory scan, then kept current by the store's writes and removals,
/// so the Downloaded filter no longer enumerates the directory on every change.
@Suite("Document cache index")
struct DocumentCacheIndexTests {
  private func temporaryDirectory(containing names: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "DocumentCacheIndexTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in names {
      try Data().write(to: directory.appending(path: name))
    }
    return directory
  }

  @Test func aScanFindsEveryCachedBody() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers == [791, 9110])
    #expect(index.contains(.rfc(791)))
    #expect(index.contains(.rfc(9110)))
    #expect(!index.contains(.rfc(2119)))
  }

  @Test func aDocumentCachedInBothFormatsIsOneDocument() throws {
    let directory = try temporaryDirectory(containing: ["rfc9110.xml", "rfc9110.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers == [9110])
  }

  /// The store keeps the RFC index beside the documents, and `rfc-index` starts with
  /// the same three letters as every cached body.
  @Test func filesTheStoreDidNotNameAreIgnored() throws {
    let directory = try temporaryDirectory(
      containing: ["rfc-index.xml", "RFC 2119.txt", "rfc2119.pdf", "notes.txt", "rfc8174"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers.isEmpty)
  }

  @Test func otherSeriesAreCachedButAreNotRFCNumbers() throws {
    let directory = try temporaryDirectory(containing: ["bcp14.txt", "rfc2119.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.contains(DocumentID(series: .bcp, number: 14)))
    #expect(index.rfcNumbers == [2119])
  }

  @Test func aMissingDirectoryIsAnEmptyCache() {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "DocumentCacheIndexTests-missing-\(UUID().uuidString)")

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers.isEmpty)
  }

  @Test func aWriteAddsTheDocument() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    index.insert(.rfc(9110))

    #expect(index.contains(.rfc(9110)))
    #expect(index.rfcNumbers == [791, 9110])
  }

  @Test func aRemovalRemovesTheDocument() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    index.remove(.rfc(791))

    #expect(!index.contains(.rfc(791)))
    #expect(index.rfcNumbers == [9110])
  }
}
