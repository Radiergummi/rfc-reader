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
  /// The bound the app applies. How many documents it holds depends on their size,
  /// which the cache's `StorageUsage` reports.
  public static let defaultBound = 500 * 1024 * 1024

  /// How long a document read stays pinned.
  public static let readWindow: TimeInterval = 30 * 86_400

  /// What was read since this is pinned at `now`.
  public static func readCutoff(now: Date) -> Date {
    now.addingTimeInterval(-readWindow)
  }

  /// What eviction never removes: bookmarks, a bookmark being a promise to keep the
  /// document offline, and so is a document with annotations, which the Annotations
  /// tab relocates against (#522); what was read since `readCutoff`; a document
  /// marked Keep Offline, whose cached body waits for the keeper to move it (#358);
  /// and whatever a window has open, which includes the document just fetched. A
  /// bookmarked, read or marked series stands for its members (`withMembers`,
  /// #656); what is open is the document a window shows, already a member.
  public static func pinned(
    bookmarked: Set<DocumentID>, read: Set<DocumentID>, marked: Set<DocumentID>,
    open: Set<DocumentID>, withMembers: (Set<DocumentID>) -> Set<DocumentID>
  ) -> Set<DocumentID> {
    withMembers(bookmarked.union(read).union(marked)).union(open)
  }

  /// What Clear Cache leaves in the reading cache: the marks, what is wanted
  /// offline, whose body waits there for the keeper to move it, and what a window
  /// has open.
  public static func spared(
    marked: Set<DocumentID>, wantedOffline: Set<DocumentID>, open: Set<DocumentID>
  ) -> Set<DocumentID> {
    marked.union(wantedOffline).union(open)
  }

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
