import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which tab a link from outside the app lands in.
@Suite("Link routing")
struct LinkRoutingTests {
  /// A tab, by name, and what it shows.
  private struct Tab {
    let name: String
    let selection: DocumentID?
  }

  private func target(
    for document: DocumentID, in tabs: [Tab], preferring preferred: Tab? = nil
  ) -> String? {
    LinkRouting.target(
      for: document, in: tabs, showing: \.selection,
      preferring: { $0.name == preferred?.name }
    )?.name
  }

  @Test func `a tab already showing the document takes the link, however long ago it was used`() {
    let tabs = [
      Tab(name: "front", selection: .rfc(9110)),
      Tab(name: "empty", selection: nil),
      Tab(name: "behind", selection: .rfc(2119)),
    ]
    #expect(target(for: .rfc(2119), in: tabs) == "behind")
  }

  @Test func `otherwise the most recently used tab takes it`() {
    let tabs = [Tab(name: "front", selection: .rfc(9110)), Tab(name: "behind", selection: nil)]
    #expect(target(for: .rfc(2119), in: tabs) == "front")
  }

  @Test func `of two tabs showing the document, the more recently used takes it`() {
    let tabs = [
      Tab(name: "front", selection: nil),
      Tab(name: "second", selection: .rfc(2119)),
      Tab(name: "third", selection: .rfc(2119)),
    ]
    #expect(target(for: .rfc(2119), in: tabs) == "second")
  }

  /// On macOS the tab of the window that was key last, which a tab opened behind it
  /// or a script navigating another window must not displace (#277).
  @Test func `a preferred tab takes it over the most recently used`() {
    let key = Tab(name: "key", selection: .rfc(791))
    let tabs = [Tab(name: "front", selection: .rfc(793)), key]
    #expect(target(for: .rfc(9110), in: tabs, preferring: key) == "key")
  }

  @Test func `a tab already showing the document takes it over the preferred one`() {
    let key = Tab(name: "key", selection: .rfc(791))
    let tabs = [Tab(name: "front", selection: .rfc(9110)), key]
    #expect(target(for: .rfc(9110), in: tabs, preferring: key) == "front")
  }

  @Test func `of two tabs showing the document, the preferred one takes it`() {
    let key = Tab(name: "key", selection: .rfc(9110))
    let tabs = [Tab(name: "front", selection: .rfc(9110)), key]
    #expect(target(for: .rfc(9110), in: tabs, preferring: key) == "key")
  }

  @Test func `with no tab open nothing takes it`() {
    #expect(target(for: .rfc(2119), in: []) == nil)
  }

  @Test func `a preferred tab that is not open does not take it`() {
    let closed = Tab(name: "closed", selection: .rfc(791))
    #expect(target(for: .rfc(2119), in: [], preferring: closed) == nil)
  }
}
