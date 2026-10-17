import Foundation
import RFCKit

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#endif

/// The context menu of a link in the reader. On macOS (#776) it is NSTextView's own,
/// with its Copy Link handing out the URL `LinkCopy` gives instead of the link's,
/// which is the reader's (`rfc://9110`, an anchor in this document, a bibliography
/// entry) and opens nowhere else. On iOS (#763) a reader's link gets a menu of the
/// reader's own actions (`actions(for:opensNewWindows:opens:)`), rather than UIKit's with
/// its items found by private identifiers and replaced.
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
    /// The document the link names, which a tab or a window of its own can show; nil
    /// for an anchor or a bibliography entry, which stay in this document, as a
    /// Command-click does.
    public var document: RFCLink?

    /// Whether the link names a document, which a tab of its own can show.
    public var opensInNewTab: Bool { document != nil }
  }

  public static func items(
    for link: URL, from currentDocument: DocumentID, in index: RFCIndex?,
    bibliography: [ReferenceGroup]
  ) -> Items {
    let destination = LinkDestination.resolve(
      link, from: currentDocument, activation: .newTab(inBackground: false))
    let copyLink: CopyLink
    if !LinkCopy.isReaders(link) {
      copyLink = .system
    } else if let shared = LinkCopy.forLink(
      link, from: currentDocument, in: index, bibliography: bibliography)
    {
      copyLink = .publicLink(shared)
    } else {
      copyLink = .none
    }
    guard case .document(let document) = destination else {
      return Items(copyLink: copyLink, document: nil)
    }
    return Items(copyLink: copyLink, document: document)
  }

  /// What iOS's menu for a reader's link holds, in order (#763). Nil for a link to
  /// the web, whose URL is anyone's, and whose menu is UIKit's own.
  public enum Action: Equatable {
    /// As a tap does.
    case open
    case openInNewWindow(RFCLink)
    case copyLink(LinkCopy)
    case share(LinkCopy)
  }

  /// The menu for `items`: Open, a window of its own where the device has windows to
  /// open and the link names a document, and the public URL to copy and share where
  /// there is one. `opens` is false for a link to where the reader already is, a
  /// heading's own number (#433).
  public static func actions(
    for items: Items, opensNewWindows: Bool, opens: Bool = true
  ) -> [Action]? {
    guard items.copyLink != .system else { return nil }
    var actions: [Action] = opens ? [.open] : []
    if opensNewWindows, let document = items.document {
      actions.append(.openInNewWindow(document))
    }
    if let link = items.copyLink.publicLink {
      actions += [.copyLink(link), .share(link)]
    }
    return actions
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  extension LinkMenu {
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
