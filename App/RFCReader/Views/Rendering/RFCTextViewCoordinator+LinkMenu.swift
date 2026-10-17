#if canImport(UIKit)
  import LinkPresentation
  import RFCReaderKit
  import UIKit
  import UniformTypeIdentifiers

  extension RFCTextViewCoordinator {
    /// The long-press menu under a reference's preview (#431, #763): the reader's own
    /// actions for a link of the reader's (`LinkMenu.actions`), Copy Link and Share
    /// handing out the URL anyone can open rather than the reader's `rfc://`, which
    /// opens nowhere else. Untitled, because UIKit titles it with that same URL and
    /// the preview names the reference better. A link to the web keeps UIKit's own
    /// menu. Built rather than edited: UIKit's Copy and Share were found by private
    /// identifiers, and an iOS that renamed them would hand out the `rfc://` again.
    func referenceMenu(
      _ defaultMenu: UIMenu, for url: URL, opens: Bool = true, from textView: UITextView,
      at range: NSRange
    ) -> UIMenu {
      guard let documentID else { return defaultMenu }
      let items = LinkMenu.items(
        for: url, from: documentID, in: environment?.library.index, bibliography: bibliography)
      // UIKit's own for a link to the web; none at all where the reader has nothing to
      // offer, a heading's number with no public URL, rather than an empty menu.
      guard
        let actions = LinkMenu.actions(
          for: items, opensNewWindows: environment?.library.opensNewWindows == true, opens: opens)
      else { return defaultMenu }
      guard !actions.isEmpty else { return UIMenu(title: "", children: []) }
      return UIMenu(
        title: "",
        children: actions.map { action($0, for: url, from: textView, at: range) })
    }

    private func action(
      _ action: LinkMenu.Action, for url: URL, from textView: UITextView, at range: NSRange
    ) -> UIAction {
      switch action {
      case .open:
        return UIAction(title: String(localized: "Open"), image: UIImage(systemName: "doc.text")) {
          [weak self] _ in
          _ = self?.onLink(url, .here)
        }
      case .openInNewWindow(let link):
        return UIAction(
          title: String(localized: "Open in New Window"),
          image: UIImage(systemName: "macwindow.badge.plus")
        ) { [weak self] _ in
          self?.environment?.library.openWindow(for: link)
        }
      case .copyLink(let link):
        // The link in every form an app might take (`PasteboardContent.link`).
        return UIAction(title: String(localized: "Copy Link"), image: UIImage(systemName: "link")) {
          _ in
          Clipboard.write(.link(link), announcing: .link)
        }
      case .share(let link):
        return UIAction(
          title: String(localized: "Share…"), image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak textView] _ in
          guard let textView else { return }
          Self.share([SharedLink(link)], from: textView, at: range)
        }
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

    private func item(
      _ title: String.LocalizationValue, _ action: Selector, _ value: Any
    ) -> NSMenuItem {
      let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
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
