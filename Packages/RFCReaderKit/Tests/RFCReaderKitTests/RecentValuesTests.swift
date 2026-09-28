import Foundation
import RFCKit
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

  /// A build is for one style: the same document at another size, width or link
  /// style is another build.
  @Test func `a build key differs by document and by every part of the style`() {
    let style = ReadingStyle()
    let document = DocumentID(series: .rfc, number: 9110)
    let key = BuildKey(document: document, style: style)
    #expect(key == BuildKey(document: document, style: style))
    #expect(key != BuildKey(document: DocumentID(series: .rfc, number: 9111), style: style))
    var wider = style
    wider.measure += 1
    #expect(key != BuildKey(document: document, style: wider))
    var underlined = style
    underlined.underlinesLinks.toggle()
    #expect(key != BuildKey(document: document, style: underlined))
    #expect(key != BuildKey(document: document, style: style.scaled(by: 1.1)))
  }
}
