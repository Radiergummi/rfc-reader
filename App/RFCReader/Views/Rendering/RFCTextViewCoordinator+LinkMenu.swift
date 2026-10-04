#if canImport(UIKit)
  import LinkPresentation
  import RFCReaderKit
  import UIKit
  import UniformTypeIdentifiers

  extension RFCTextViewCoordinator {
    /// The long-press menu under a reference's preview (#431): UIKit's own, with
    /// Copy and Share handing out `link` instead of the reference's URL, which is
    /// the reader's `rfc://` and opens nowhere else. Without a link to hand out
    /// they go. Untitled, because UIKit titles it with that same URL and the
    /// preview names the reference better.
    ///
    /// UIKit's two actions are found by their data detector identifiers, and each
    /// is replaced in place, keeping its title, image and position. Anything they
    /// fail to match stays UIKit's, so the menu never shows both.
    func referenceMenu(
      _ defaultMenu: UIMenu, sharing link: LinkCopy?, from textView: UITextView, at range: NSRange
    ) -> UIMenu {
      func replaced(_ elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element in
          if let menu = element as? UIMenu {
            return menu.replacingChildren(replaced(menu.children))
          }
          guard let action = element as? UIAction else { return element }
          let identifier = action.identifier.rawValue
          if identifier.contains("DDCopyAction") {
            return link.map { Self.copyAction(like: action, link: $0) }
          }
          if identifier.contains("DDShareAction") {
            return link.map { share(like: action, link: $0, from: textView, at: range) }
          }
          return action
        }
      }
      return UIMenu(
        title: "", options: defaultMenu.options, children: replaced(defaultMenu.children))
    }

    /// The link in every form an app might take (`PasteboardContent.link`).
    private static func copyAction(like action: UIAction, link: LinkCopy) -> UIAction {
      UIAction(title: action.title, image: action.image) { _ in
        Clipboard.write(.link(link), announcing: .link)
      }
    }

    private func share(
      like action: UIAction, link: LinkCopy, from textView: UITextView, at range: NSRange
    ) -> UIAction {
      UIAction(title: action.title, image: action.image) { [weak textView] _ in
        guard let textView else { return }
        Self.share([SharedLink(link)], from: textView, at: range)
      }
    }

    /// The share sheet for `items`, over whatever is presented: a popover on iPad,
    /// pointing at `range`'s first line.
    static func share(_ items: [Any], from textView: UITextView, at range: NSRange) {
      guard var presenter = textView.window?.rootViewController else { return }
      while let presented = presenter.presentedViewController { presenter = presented }
      let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = textView
      if let start = textView.position(
        from: textView.beginningOfDocument, offset: range.location),
        let end = textView.position(from: start, offset: range.length),
        let textRange = textView.textRange(from: start, to: end)
      {
        sheet.popoverPresentationController?.sourceRect = textView.firstRect(for: textRange)
      }
      presenter.present(sheet, animated: true)
    }
  }

  /// The web URL, with the label as the share sheet's title and a message's subject.
  private final class SharedLink: NSObject, UIActivityItemSource {
    let link: LinkCopy

    init(_ link: LinkCopy) {
      self.link = link
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
      link.url
    }

    func activityViewController(
      _ controller: UIActivityViewController,
      itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
      link.url
    }

    func activityViewController(
      _ controller: UIActivityViewController,
      subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
      link.label
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController)
      -> LPLinkMetadata?
    {
      let metadata = LPLinkMetadata()
      metadata.originalURL = link.url
      metadata.url = link.url
      metadata.title = link.label
      return metadata
    }
  }
#else
  import AppKit
  import RFCReaderKit

  extension RFCTextViewCoordinator {
    /// NSTextView's menu for the link at `characterIndex` (#776): Copy Link hands
    /// out the URL anyone can open, as iOS's does, and above it Open in New Tab and
    /// Preview do what a Command-click and a force click do, for whoever doesn't
    /// know those gestures. Which items a link gets is `LinkMenu`'s.
    func linkMenu(_ menu: NSMenu, at characterIndex: Int) -> NSMenu {
      // A backlink caption's link is ours alone, and Copy Link would copy a URL
      // nothing else can open; the rest of the menu stays.
      if backlinkCaption(at: characterIndex) != nil {
        return LinkMenu.adapting(menu, copyLink: .removed, adding: [])
      }
      guard let documentID, let url = link(at: characterIndex) else { return menu }
      let items = LinkMenu.items(
        for: url, from: documentID, in: environment?.library.index, bibliography: bibliography)
      var added: [NSMenuItem] = []
      if items.opensInNewTab {
        added.append(item("Open in New Tab", #selector(openInNewTab(_:)), url))
      }
      if let forceClick = forceClick(at: characterIndex) {
        added.append(item("Preview", #selector(preview(_:)), forceClick))
      }
      let copyLink: LinkMenu.CopyLinkItem =
        switch items.copyLink {
        case .system: .system
        case .none: .removed
        case .publicLink(let link): .replaced(item("Copy Link", #selector(copyLink(_:)), link))
        }
      return LinkMenu.adapting(menu, copyLink: copyLink, adding: added)
    }

    private func item(_ title: String, _ action: Selector, _ value: Any) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      item.representedObject = value
      return item
    }

    /// As a Command-click opens it: behind this tab.
    @objc private func openInNewTab(_ sender: NSMenuItem) {
      guard let url = sender.representedObject as? URL else { return }
      _ = onLink(url, .newTab(inBackground: true))
    }

    /// A card stays, as a force click's need not: the pointer is on the menu item,
    /// not on the reference it would leave.
    @objc private func preview(_ sender: NSMenuItem) {
      guard let forceClick = sender.representedObject as? ReferenceHover.Event else { return }
      if case .forceClickCard(let target) = forceClick {
        hover.send(.cardChosen(target))
      } else {
        hover.send(forceClick)
      }
    }

    /// As the iOS menu's Copy writes it (`PasteboardContent.link`).
    @objc private func copyLink(_ sender: NSMenuItem) {
      guard let link = sender.representedObject as? LinkCopy else { return }
      Clipboard.write(.link(link), announcing: .link)
    }
  }
#endif
