import Foundation
import RFCKit

/// Which cached bodies go when the cache outgrows its bound (#39).
///
/// By size, not age: a document read once a year is worth keeping if there is room,
/// and evicting it by age alone saves nothing. Past the bound, the least recently
/// opened go first, until what is left fits. A pinned document — bookmarked, read in
/// the last month, open in a window — is never one of them: a bookmark is a promise
/// to keep the document offline. When the pinned documents alone are over the
/// bound, everything else goes and the cache stays over it.
///
/// Here rather than in the store because the App target has no test bundle.
public enum CacheEviction {
  /// The bound the app applies: about 1,350 documents at the ~370 KB measured.
  public static let defaultBound = 500 * 1024 * 1024

  public struct Entry: Sendable, Equatable {
    public let id: DocumentID
    /// All of the document's bodies together.
    public let bytes: Int
    public let lastOpened: Date

    public init(id: DocumentID, bytes: Int, lastOpened: Date) {
      self.id = id
      self.bytes = bytes
      self.lastOpened = lastOpened
    }
  }

  /// The documents to remove, in the order they go.
  public static func victims(of entries: [Entry], pinned: Set<DocumentID>, bound: Int)
    -> [DocumentID]
  {
    var total = entries.reduce(0) { $0 + $1.bytes }
    guard total > bound else { return [] }
    let candidates = entries.filter { !pinned.contains($0.id) }.sorted {
      $0.lastOpened != $1.lastOpened ? $0.lastOpened < $1.lastOpened : $0.id < $1.id
    }
    var victims: [DocumentID] = []
    for entry in candidates {
      guard total > bound else { break }
      victims.append(entry.id)
      total -= entry.bytes
    }
    return victims
  }

  /// What the cache in `directory` holds: one entry per document, its bodies'
  /// sizes summed, and the most recent of their modification dates as when it was
  /// last opened. The store sets that date on every open; a body is otherwise
  /// never modified after it is written.
  ///
  /// Only the files `DocumentCacheIndex` counts as bodies. An enumeration, so it is
  /// asked once per download rather than per question.
  public static func entries(in directory: URL) -> [Entry] {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: keys)) ?? []
    var found: [DocumentID: (bytes: Int, date: Date)] = [:]
    for url in urls {
      guard let id = DocumentCacheIndex.document(named: url.lastPathComponent),
        let values = try? url.resourceValues(forKeys: Set(keys))
      else {
        continue
      }
      let bytes = values.fileSize ?? 0
      let date = values.contentModificationDate ?? .distantPast
      let previous = found[id]
      found[id] = ((previous?.bytes ?? 0) + bytes, max(previous?.date ?? .distantPast, date))
    }
    return found.map { Entry(id: $0.key, bytes: $0.value.bytes, lastOpened: $0.value.date) }
  }
}
