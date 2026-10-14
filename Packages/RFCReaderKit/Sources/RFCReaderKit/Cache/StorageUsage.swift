import Foundation

/// What a storage tier holds, as Settings' Storage tab states it (#358): how many
/// documents have a body there, and how much disk their bodies take.
public struct StorageUsage: Sendable, Equatable {
  public var documents: Int
  public var bytes: Int

  public init(documents: Int, bytes: Int) {
    self.documents = documents
    self.bytes = bytes
  }

  /// Over a tier's entries, each a document's bodies together.
  public init(_ entries: [CacheEviction.Entry]) {
    self.init(documents: entries.count, bytes: entries.reduce(0) { $0 + $1.bytes })
  }
}

/// What Settings' Storage tab states (#358): what each tier holds, and what of the
/// reading cache Clear Cache would remove, which is less than all of it while a
/// document there is open or wanted offline.
public struct StorageReport: Sendable, Equatable {
  public var kept: StorageUsage
  public var cache: StorageUsage
  public var clearable: StorageUsage

  public init(kept: StorageUsage, cache: StorageUsage, clearable: StorageUsage) {
    self.kept = kept
    self.cache = cache
    self.clearable = clearable
  }
}
