import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which cached bodies go when the cache outgrows its bound (#39): the least
/// recently opened first, never a pinned one.
@Suite("Cache eviction")
struct CacheEvictionTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func entry(_ number: Int, bytes: Int, daysAgo: Double) -> CacheEviction.Entry {
    CacheEviction.Entry(id: .rfc(number), bytes: bytes, lastOpened: now - daysAgo * 86_400)
  }

  @Test func `a cache within its bound keeps everything`() {
    let entries = [entry(1, bytes: 100, daysAgo: 9), entry(2, bytes: 100, daysAgo: 1)]
    #expect(CacheEviction.victims(of: entries, pinned: [], bound: 200).isEmpty)
  }

  @Test func `the least recently opened go first, until the cache fits`() {
    let entries = [
      entry(1, bytes: 100, daysAgo: 1),
      entry(2, bytes: 100, daysAgo: 30),
      entry(3, bytes: 100, daysAgo: 10),
      entry(4, bytes: 100, daysAgo: 20),
    ]
    #expect(CacheEviction.victims(of: entries, pinned: [], bound: 250) == [.rfc(2), .rfc(4)])
  }

  /// A bookmark is a promise to keep the document offline, however long ago it was
  /// last opened.
  @Test func `a pinned document is never evicted, even the oldest`() {
    let entries = [
      entry(1, bytes: 100, daysAgo: 300),
      entry(2, bytes: 100, daysAgo: 5),
      entry(3, bytes: 100, daysAgo: 1),
    ]
    #expect(CacheEviction.victims(of: entries, pinned: [.rfc(1)], bound: 200) == [.rfc(2)])
  }

  /// When the pinned documents alone are over the bound, everything else goes and
  /// the cache stays over it; the settings panel is where that gets said.
  @Test func `pinned documents alone may exceed the bound`() {
    let entries = [
      entry(1, bytes: 300, daysAgo: 3),
      entry(2, bytes: 100, daysAgo: 2),
      entry(3, bytes: 100, daysAgo: 1),
    ]
    #expect(CacheEviction.victims(of: entries, pinned: [.rfc(1)], bound: 200) == [.rfc(2), .rfc(3)])
  }

  @Test func `documents opened at the same moment go in a fixed order`() {
    let entries = [entry(7, bytes: 100, daysAgo: 1), entry(3, bytes: 100, daysAgo: 1)]
    #expect(CacheEviction.victims(of: entries, pinned: [], bound: 100) == [.rfc(3)])
  }

  /// A document is its bodies together: both formats go, or neither, and its size
  /// is their sum.
  @Test func `the cache is read from the directory, one entry per document`() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func write(_ name: String, bytes: Int, daysAgo: Double) throws {
      let url = directory.appending(path: name)
      try Data(count: bytes).write(to: url)
      try FileManager.default.setAttributes(
        [.modificationDate: now - daysAgo * 86_400], ofItemAtPath: url.path)
    }
    try write("rfc1.xml", bytes: 300, daysAgo: 5)
    try write("rfc1.txt", bytes: 200, daysAgo: 2)
    try write("rfc2.txt", bytes: 50, daysAgo: 9)
    try write("rfc-index.xml", bytes: 999, daysAgo: 0)
    try write("notes.md", bytes: 10, daysAgo: 0)

    let entries = CacheEviction.entries(in: directory).sorted { $0.id < $1.id }
    #expect(entries.map(\.id) == [.rfc(1), .rfc(2)])
    #expect(entries.map(\.bytes) == [500, 50])
    // The more recent of a document's two bodies is when it was last opened.
    #expect(entries.first?.lastOpened == now - 2 * 86_400)
  }
}
