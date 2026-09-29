import Foundation
import RFCKit
import SwiftUI
import Testing

@testable import RFCReaderKit

/// The bound and the order kept builds leave in (#374): a repeated preview is a
/// lookup, and the cache never holds more than it was made for.
@Suite("Recent values")
struct RecentValuesTests {
  @Test func `a stored value comes back for its key`() {
    var recent = RecentValues<String, Int>(capacity: 2)
    recent.store(1, for: "a")
    #expect(recent.value(for: "a") == 1)
    #expect(recent.value(for: "b") == nil)
  }

  @Test func `past the bound the least recently used goes first`() {
    var recent = RecentValues<String, Int>(capacity: 2)
    recent.store(1, for: "a")
    recent.store(2, for: "b")
    recent.store(3, for: "c")
    #expect(recent.value(for: "a") == nil)
    #expect(recent.keys == ["b", "c"])
  }

  @Test func `reading a value makes it the most recent`() {
    var recent = RecentValues<String, Int>(capacity: 2)
    recent.store(1, for: "a")
    recent.store(2, for: "b")
    _ = recent.value(for: "a")
    recent.store(3, for: "c")
    #expect(recent.keys == ["a", "c"])
  }

  @Test func `storing a key again replaces its value and makes it the most recent`() {
    var recent = RecentValues<String, Int>(capacity: 2)
    recent.store(1, for: "a")
    recent.store(2, for: "b")
    recent.store(10, for: "a")
    #expect(recent.keys == ["b", "a"])
    #expect(recent.value(for: "a") == 10)
  }

  /// What a removed download leaves: the document is parsed again on its next
  /// open, and a kept preview of the old parse must not be paired with it.
  @Test func `removing entries leaves the rest in their order`() {
    var recent = RecentValues<String, Int>(capacity: 3)
    recent.store(1, for: "a")
    recent.store(2, for: "b")
    recent.store(3, for: "c")
    recent.removeAll { $0 == "b" }
    #expect(recent.keys == ["a", "c"])
    #expect(recent.value(for: "b") == nil)
  }
}
