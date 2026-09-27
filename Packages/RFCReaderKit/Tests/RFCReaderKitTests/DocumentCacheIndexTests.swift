import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The in-memory record of which documents the on-disk cache holds (#39). Seeded
/// from one directory scan, then kept current by the store's writes and removals
/// and scanned again only when the directory's date says something else changed
/// it, so the Downloaded filter no longer enumerates the directory on every change.
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

  @Test func `a scan finds every cached body`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers == [791, 9110])
    #expect(index.contains(.rfc(791)))
    #expect(index.contains(.rfc(9110)))
    #expect(!index.contains(.rfc(2119)))
  }

  @Test func `a document cached in both formats is one document`() throws {
    let directory = try temporaryDirectory(containing: ["rfc9110.xml", "rfc9110.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers == [9110])
  }

  /// The store keeps the RFC index beside the documents, and `rfc-index` starts with
  /// the same three letters as every cached body.
  @Test func `files the store did not name are ignored`() throws {
    let directory = try temporaryDirectory(
      containing: ["rfc-index.xml", "RFC 2119.txt", "rfc2119.pdf", "notes.txt", "rfc8174"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers.isEmpty)
  }

  /// `rfc0791` parses as RFC 791, but the store names it `rfc791.txt`, so a zero-padded
  /// file is not one of its bodies: counting it would answer for a file `remove` never
  /// deletes.
  @Test func `a zero padded number is not the stores name`() throws {
    let directory = try temporaryDirectory(containing: ["rfc0791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(!index.contains(.rfc(791)))
    #expect(index.rfcNumbers == [9110])
  }

  @Test func `other series are cached but are not RFC numbers`() throws {
    let directory = try temporaryDirectory(containing: ["bcp14.txt", "rfc2119.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.contains(DocumentID(series: .bcp, number: 14)))
    #expect(index.rfcNumbers == [2119])
  }

  @Test func `a missing directory is an empty cache`() {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "DocumentCacheIndexTests-missing-\(UUID().uuidString)")

    let index = DocumentCacheIndex(scanning: directory)

    #expect(index.rfcNumbers.isEmpty)
  }

  @Test func `a write adds the document`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    try index.update(.rfc(9110)) {
      try Data().write(to: directory.appending(path: "rfc9110.xml"), options: .atomic)
    }

    #expect(index.contains(.rfc(9110)))
    #expect(index.rfcNumbers == [791, 9110])
  }

  @Test func `a removal removes the document`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    try index.update(.rfc(791)) {
      try FileManager.default.removeItem(at: directory.appending(path: "rfc791.txt"))
    }

    #expect(!index.contains(.rfc(791)))
    #expect(index.rfcNumbers == [9110])
  }

  /// The store removes both formats and ignores a failure, so a body that could not
  /// be deleted — only the XML went here — is still on disk and still cached.
  @Test func `a removal that leaves a body keeps the document`() throws {
    let directory = try temporaryDirectory(containing: ["rfc9110.xml", "rfc9110.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    try index.update(.rfc(9110)) {
      try FileManager.default.removeItem(at: directory.appending(path: "rfc9110.xml"))
    }

    #expect(index.contains(.rfc(9110)))

    try index.update(.rfc(9110)) {
      try FileManager.default.removeItem(at: directory.appending(path: "rfc9110.txt"))
    }

    #expect(!index.contains(.rfc(9110)))
  }

  /// A file deleted in Finder. The directory's date is set by hand because two
  /// changes inside one tick of the file system's clock would share a date.
  @Test func `a change made behind the store is seen on revalidation`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    try FileManager.default.removeItem(at: directory.appending(path: "rfc791.txt"))
    try setModificationDate(Date(timeIntervalSince1970: 1_000_000_000), of: directory)
    index.revalidate()

    #expect(index.rfcNumbers == [9110])
  }

  /// The point of the index: a directory whose date has not moved is not read
  /// again. Putting the date back after deleting a file hides the deletion, which
  /// is how the test can tell no scan happened. The date is a whole second because
  /// setting one is not guaranteed to keep the nanoseconds reading it returns.
  @Test func `an unchanged directory is not scanned again`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt", "rfc9110.xml"])
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 1_000_000_000)
    try setModificationDate(date, of: directory)
    var index = DocumentCacheIndex(scanning: directory)

    try FileManager.default.removeItem(at: directory.appending(path: "rfc791.txt"))
    try setModificationDate(date, of: directory)
    index.revalidate()

    #expect(index.rfcNumbers == [791, 9110])
  }

  /// The store's own write records the directory's new date, and must not absorb
  /// a deletion made behind its back before it.
  @Test func `a write does not hide an earlier change`() throws {
    let directory = try temporaryDirectory(containing: ["rfc791.txt"])
    defer { try? FileManager.default.removeItem(at: directory) }
    var index = DocumentCacheIndex(scanning: directory)

    try FileManager.default.removeItem(at: directory.appending(path: "rfc791.txt"))
    try setModificationDate(Date(timeIntervalSince1970: 1_000_000_000), of: directory)
    try index.update(.rfc(9110)) {
      try Data().write(to: directory.appending(path: "rfc9110.xml"), options: .atomic)
    }
    index.revalidate()

    #expect(index.rfcNumbers == [9110])
  }

  private func setModificationDate(_ date: Date, of directory: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
  }
}
