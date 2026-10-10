import Foundation

/// The last few values asked for, the least recently used going first once there
/// are more than `capacity`.
///
/// Kept builds are what it is for (#374): a force-click preview built its document
/// again every time, the same reference twice in a row included, and the spinner
/// waited for the build — 15 to 55 ms in release on the largest RFCs. A build holds
/// 4.5 to 8 MB, so only a few are kept.
///
/// A handful of entries, so a list in order of use rather than a dictionary with a
/// linked list beside it: every operation is a scan of at most `capacity`.
public struct RecentValues<Key: Hashable, Value> {
  public let capacity: Int
  /// Least recently used first.
  private var entries: [(key: Key, value: Value)] = []

  public init(capacity: Int) {
    precondition(capacity > 0, "a cache that keeps nothing is not a cache")
    self.capacity = capacity
  }

  /// The keys held, least recently used first; for the tests.
  var keys: [Key] { entries.map(\.key) }

  /// The value for `key`, which then counts as the most recently used.
  public mutating func value(for key: Key) -> Value? {
    guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
    let entry = entries.remove(at: index)
    entries.append(entry)
    return entry.value
  }

  /// Keeps `value` as the most recently used, in place of any value `key` had, and
  /// lets the least recently used go if that takes the count past `capacity`.
  public mutating func store(_ value: Value, for key: Key) {
    entries.removeAll { $0.key == key }
    entries.append((key, value))
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
  }

  /// Lets go of every value whose key matches, leaving the rest in their order.
  public mutating func removeAll(where matches: (Key) -> Bool) {
    entries.removeAll { matches($0.key) }
  }
}
