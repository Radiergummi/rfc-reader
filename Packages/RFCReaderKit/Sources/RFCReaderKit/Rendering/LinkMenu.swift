#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import RFCKit

  /// The context menu of a link in the reader, on macOS (#776): NSTextView's own,
  /// with its Copy Link handing out the URL `LinkCopy` gives instead of the link's,
  /// which is the reader's (`rfc://9110`, an anchor in this document, a bibliography
  /// entry) and opens nowhere else. The iOS menu does the same with UIKit's items.
  @MainActor
  public enum LinkMenu {
    public enum CopyLink: Equatable {
      /// NSTextView's own: the link is to the web, and its URL is anyone's.
      case system
      /// The reader's link, as a URL anyone can open.
      case publicLink(LinkCopy)
      /// The reader's link, with nothing of ours to hand out for it.
      case none

      public var publicLink: LinkCopy? {
        guard case .publicLink(let link) = self else { return nil }
        return link
      }
    }

    public struct Items: Equatable {
      public var copyLink: CopyLink
      /// Whether the link names a document, which a tab of its own can show. As a
      /// Command-click: an anchor or a bibliography entry stays in this document.
      public var opensInNewTab: Bool
    }

    public static func items(
      for link: URL, from currentDocument: DocumentID, in index: RFCIndex?,
      bibliography: [ReferenceGroup]
    ) -> Items {
      let destination = LinkDestination.resolve(
        link, from: currentDocument, activation: .newTab(inBackground: false))
      let copyLink: CopyLink
      if destination == .unhandled {
        copyLink = .system
      } else if let shared = LinkCopy.forLink(
        link, from: currentDocument, in: index, bibliography: bibliography)
      {
        copyLink = .publicLink(shared)
      } else {
        copyLink = .none
      }
      guard case .document = destination else {
        return Items(copyLink: copyLink, opensInNewTab: false)
      }
      return Items(copyLink: copyLink, opensInNewTab: true)
    }

    /// What becomes of NSTextView's Copy Link item.
    public enum CopyLinkItem {
      case system
      case replaced(NSMenuItem)
      case removed
    }

    /// `menu` with its Copy Link item, matched by its `copyLink:` action, kept,
    /// replaced in place or removed, and `items` above it, where Safari puts its own
    /// ways to open a link; at the top where there is no Copy Link. A copy, so
    /// nothing is left changed in a menu AppKit hands out again.
    public static func adapting(
      _ menu: NSMenu, copyLink: CopyLinkItem, adding items: [NSMenuItem]
    ) -> NSMenu {
      let result = (menu.copy() as? NSMenu) ?? NSMenu()
      let position = result.items.firstIndex { $0.action == copyLinkAction }
      if let index = position {
        switch copyLink {
        case .system:
          break
        case .replaced(let item):
          result.removeItem(at: index)
          result.insertItem(item, at: index)
        case .removed:
          result.removeItem(at: index)
        }
      }
      for item in items.reversed() {
        result.insertItem(item, at: position ?? 0)
      }
      return result
    }

    private static let copyLinkAction = Selector(("copyLink:"))
  }
#endif
