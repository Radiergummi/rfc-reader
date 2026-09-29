/// A bounded memo that, once full, forgets whatever was used longest ago.
///
/// The document store keeps the documents it parsed in one, so reopening a
/// document skips the parse without every document opened in a session staying in
/// memory until the app quits.
///
/// Here rather than in the store because the App target has no test bundle.
public struct RecentlyUsed<Key: Hashable, Value> {
  public let capacity: Int
  private var values: [Key: Value] = [:]
  /// Every key held, the least recently used first.
  private var order: [Key] = []

  public init(capacity: Int) {
    precondition(capacity > 0, "A memo that holds nothing is not a memo.")
    self.capacity = capacity
  }

  /// The value for `key`, which is then the most recently used.
  public mutating func value(for key: Key) -> Value? {
    guard let value = values[key] else { return nil }
    markUsed(key)
    return value
  }

  /// Holds `value` for `key` as the most recently used, forgetting the least
  /// recently used when that takes the memo past its capacity.
  public mutating func insert(_ value: Value, for key: Key) {
    if values.updateValue(value, forKey: key) == nil {
      order.append(key)
    } else {
      markUsed(key)
    }
    if order.count > capacity {
      let leastRecentlyUsed = order.removeFirst()
      values[leastRecentlyUsed] = nil
    }
  }

  public mutating func remove(_ key: Key) {
    guard values.removeValue(forKey: key) != nil else { return }
    order.removeAll { $0 == key }
  }

  /// A linear search, which at the capacities used here costs nothing next to what
  /// the memo saves.
  private mutating func markUsed(_ key: Key) {
    order.removeAll { $0 == key }
    order.append(key)
  }
}

extension RecentlyUsed: Sendable where Key: Sendable, Value: Sendable {}
