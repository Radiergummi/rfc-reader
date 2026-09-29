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

  private func target(for document: DocumentID, in tabs: [Tab]) -> String? {
    LinkRouting.target(for: document, in: tabs, showing: \.selection)?.name
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

  @Test func `with no tab open nothing takes it`() {
    #expect(target(for: .rfc(2119), in: []) == nil)
  }
}
