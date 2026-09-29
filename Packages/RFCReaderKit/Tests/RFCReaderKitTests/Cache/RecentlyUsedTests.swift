import RFCKit
import Testing

@testable import RFCReaderKit

/// The document store's memo of parsed documents: bounded, and what goes when it is
/// full is what was used longest ago.
@Suite("Recently used")
struct RecentlyUsedTests {
  @Test func `a value is found by its key until it is removed`() {
    var recent = RecentlyUsed<DocumentID, String>(capacity: 2)
    recent.insert("HTTP Semantics", for: .rfc(9110))
    #expect(recent.value(for: .rfc(9110)) == "HTTP Semantics")
    recent.remove(.rfc(9110))
    #expect(recent.value(for: .rfc(9110)) == nil)
  }

  @Test func `past its capacity, the least recently used goes`() {
    var recent = RecentlyUsed<DocumentID, String>(capacity: 2)
    recent.insert("one", for: .rfc(1))
    recent.insert("two", for: .rfc(2))
    recent.insert("three", for: .rfc(3))
    #expect(recent.keys == [.rfc(2), .rfc(3)])
    #expect(recent.value(for: .rfc(1)) == nil)
    #expect(recent.value(for: .rfc(2)) == "two")
    #expect(recent.value(for: .rfc(3)) == "three")
  }

  @Test func `asking for a value counts as using it`() {
    var recent = RecentlyUsed<DocumentID, String>(capacity: 2)
    recent.insert("one", for: .rfc(1))
    recent.insert("two", for: .rfc(2))
    _ = recent.value(for: .rfc(1))
    recent.insert("three", for: .rfc(3))
    #expect(recent.value(for: .rfc(1)) == "one")
    #expect(recent.value(for: .rfc(2)) == nil)
  }

  @Test func `inserting a key again replaces its value and takes no second place`() {
    var recent = RecentlyUsed<DocumentID, String>(capacity: 2)
    recent.insert("one", for: .rfc(1))
    recent.insert("two", for: .rfc(2))
    recent.insert("one again", for: .rfc(1))
    recent.insert("three", for: .rfc(3))
    #expect(recent.value(for: .rfc(1)) == "one again")
    #expect(recent.value(for: .rfc(2)) == nil)
    #expect(recent.value(for: .rfc(3)) == "three")
  }
}
