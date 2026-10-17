import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What iOS's long-press menu for a link holds (#763): the reader's own actions,
/// never UIKit's items with the reader's `rfc://` URL behind them.
@Suite("Link menu actions")
@MainActor
struct LinkMenuActionsTests {
  private let current = DocumentID.rfc(9110)
  private let index = RFCIndex(
    rfcs: [
      RFCMetadata(
        id: .rfc(7932), title: "Brotli Compressed Data Format",
        date: PublicationDate(year: 2016))
    ],
    series: [])

  private func menu(
    _ string: String, opensNewWindows: Bool = true, opens: Bool = true
  ) -> [LinkMenu.Action]? {
    let items = LinkMenu.items(
      for: URL(string: string)!, from: current, in: index, bibliography: [])
    return LinkMenu.actions(for: items, opensNewWindows: opensNewWindows, opens: opens)
  }

  @Test func `a link to another RFC opens, in a window too, and hands out its public URL`()
    throws
  {
    let actions = try #require(menu("rfc://7932"))
    #expect(actions.count == 4)
    #expect(actions.first == .open)
    guard case .openInNewWindow(let window) = actions[1], case .copyLink(let link) = actions[2],
      case .share(let shared) = actions[3]
    else {
      Issue.record("unexpected actions: \(actions)")
      return
    }
    #expect(window == RFCLink(id: .rfc(7932)))
    #expect(link.url.absoluteString.contains("rfc7932"))
    #expect(link == shared)
  }

  @Test func `a window opens at the place the link names`() throws {
    let actions = try #require(menu("rfc://7932#section-4.2"))
    guard case .openInNewWindow(let window) = actions[1] else {
      Issue.record("unexpected actions: \(actions)")
      return
    }
    #expect(window.id == .rfc(7932))
    #expect(window.place == "4.2")
  }

  /// A bibliography entry that names no URL has nothing anyone else can open.
  @Test func `a reader's link with nothing public to hand out only opens`() {
    #expect(menu("\(ReaderLinkScheme.referenceScheme):Unlinked") == [.open])
  }

  /// An `rfc:` URL that names no document goes nowhere, so there is nothing to open.
  @Test func `a reader's link that names no document offers no Open`() {
    #expect(menu("rfc://nonsense") == [])
  }

  @Test func `without windows to open, there is no Open in New Window`() throws {
    let actions = try #require(menu("rfc://7932", opensNewWindows: false))
    #expect(!actions.contains { if case .openInNewWindow = $0 { true } else { false } })
  }

  /// A place in this document has no window of its own to open in.
  @Test func `an anchor in this document opens and copies, but has no window`() throws {
    let actions = try #require(menu("rfc-anchor:section-4.2"))
    #expect(actions.first == .open)
    #expect(!actions.contains { if case .openInNewWindow = $0 { true } else { false } })
    #expect(actions.contains { if case .copyLink = $0 { true } else { false } })
    #expect(actions.contains { if case .share = $0 { true } else { false } })
  }

  /// A heading's own number links to where the reader already is.
  @Test func `a link to where the reader is offers no Open`() throws {
    let actions = try #require(menu("rfc-anchor:section-4.2", opens: false))
    #expect(!actions.contains(.open))
  }

  /// A web page's URL is anyone's, and its menu is UIKit's own.
  @Test func `a link to the web gets the system's menu`() {
    #expect(menu("https://example.com/") == nil)
  }
}
