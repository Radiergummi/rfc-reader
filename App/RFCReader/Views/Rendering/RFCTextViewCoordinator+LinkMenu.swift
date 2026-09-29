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

    /// One pasteboard item in every form an app might take: the URL as text and as
    /// a URL, and the label linked to it as HTML and RTF.
    private static func copyAction(like action: UIAction, link: LinkCopy) -> UIAction {
      UIAction(title: action.title, image: action.image) { _ in
        var item: [String: Any] = [
          UTType.plainText.identifier: link.url.absoluteString,
          UTType.url.identifier: link.url,
          UTType.html.identifier: link.html,
        ]
        if let rtf = link.rtf { item[UTType.rtf.identifier] = rtf }
        UIPasteboard.general.setItems([item])
      }
    }

    private func share(
      like action: UIAction, link: LinkCopy, from textView: UITextView, at range: NSRange
    ) -> UIAction {
      UIAction(title: action.title, image: action.image) { [weak textView] _ in
        guard let textView, var presenter = textView.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(
          activityItems: [SharedLink(link)], applicationActivities: nil)
        // A popover on iPad, pointing at the reference.
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
#endif
