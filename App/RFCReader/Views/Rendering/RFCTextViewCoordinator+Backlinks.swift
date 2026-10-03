import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// A heading's backlink caption (#183, #584): a click or a tap lists the sections that
// refer to the section, beside the caption, and a row goes there. What the list holds
// is `BuiltDocument.backlinks(of:)`, and where the caption is `backlinkCaption(at:)`;
// this is only where it is shown.

extension RFCTextViewCoordinator {
  /// The caption at `offset` in the reader's text.
  func backlinkCaption(at offset: Int) -> (anchor: String, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.backlinkCaption(at: offset)
  }

  /// The list for the section at `anchor`, whose rows call `follow` with where
  /// they go; nil when nothing refers there.
  func backlinksList(of anchor: String, follow: @escaping (String) -> Void) -> BacklinksList? {
    guard let entries = built?.backlinks(of: anchor), !entries.isEmpty else { return nil }
    return BacklinksList(entries: entries, onSelect: follow)
  }

  /// A row's jump, the way a click on a reference to that section makes it.
  func followBacklink(to anchor: String) {
    guard let url = DocumentTextBuilder.url(anchor, scheme: DocumentTextBuilder.anchorScheme)
    else { return }
    _ = onLink(url, .current)
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator: UIPopoverPresentationControllerDelegate {
    /// A popover pointing at the caption, on iPad as on iPhone, where it would
    /// otherwise become a sheet for a list of a few rows.
    func showBacklinks(at offset: Int) {
      guard let textView, var presenter = textView.window?.rootViewController,
        let (anchor, range) = backlinkCaption(at: offset),
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
        let end = textView.position(from: start, offset: range.length),
        let textRange = textView.textRange(from: start, to: end)
      else { return }
      while let presented = presenter.presentedViewController { presenter = presented }
      let host = UIHostingController<BacklinksList?>(rootView: nil)
      guard
        let list = backlinksList(
          of: anchor,
          follow: { [weak self, weak host] section in
            host?.presentingViewController?.dismiss(animated: true)
            self?.followBacklink(to: section)
          })
      else { return }
      host.rootView = list
      host.modalPresentationStyle = .popover
      host.preferredContentSize = host.sizeThatFits(
        in: CGSize(width: BacklinksList.width, height: .greatestFiniteMagnitude))
      host.popoverPresentationController?.sourceView = textView
      host.popoverPresentationController?.sourceRect = textView.firstRect(for: textRange)
      host.popoverPresentationController?.delegate = self
      presenter.present(host, animated: true)
    }

    func adaptivePresentationStyle(
      for controller: UIPresentationController, traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
      .none
    }
  }
#else
  extension RFCTextViewCoordinator {
    /// In the popover a reference card uses, but opened by the click, and kept open
    /// as the pointer leaves the caption for it, as a document preview is: its rows are
    /// buttons.
    func showBacklinks(at offset: Int) {
      guard let (anchor, range) = backlinkCaption(at: offset),
        let rect = referenceRect(for: range),
        let list = backlinksList(
          of: anchor,
          follow: { [weak self] section in
            guard let self else { return }
            // Committed as a document preview is: the list closes, and the scroll
            // the jump causes previews nothing that lands under the pointer.
            self.hover.send(.previewCommitted(pointer: NSEvent.mouseLocation))
            self.followBacklink(to: section)
          })
      else { return }
      // Measured before it is shown, as on iOS, and held at that size. Left to
      // report its own size, the list was placed at a taller first guess; opened
      // above a caption near the bottom of the window, it then shrank towards its
      // top, and its arrow rose off the caption it points at.
      let host = NSHostingController(rootView: list)
      host.sizingOptions = []
      let size = host.sizeThatFits(
        in: CGSize(width: BacklinksList.width, height: .greatestFiniteMagnitude))
      hover.showBacklinks(ReferenceHoverController.Popover(content: host, size: size, anchor: rect))
    }
  }
#endif
