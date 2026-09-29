import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// A heading's backlink chip (#183): a click or a tap lists the sections that refer
// to the section, beside the chip, and a row goes there. What the list holds is
// `BuiltDocument.backlinks(of:)`; this is only where it is shown.

extension RFCTextViewCoordinator {
  /// The chip's extent around `offset`, space included: the attribute's run, not
  /// the storage run, which is a third of the chip.
  func backlinkChipRange(at offset: Int) -> NSRange? {
    guard let text = textView?.textLayoutManager?.attributedText,
      offset >= 0, offset < text.length
    else { return nil }
    var range = NSRange(location: 0, length: 0)
    let value = text.attribute(
      .rfcBacklinks, at: offset, longestEffectiveRange: &range,
      in: NSRange(location: 0, length: text.length))
    return value == nil ? nil : range
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
    _ = onLink(url, .here)
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator: UIPopoverPresentationControllerDelegate {
    /// A popover pointing at the chip, on iPad as on iPhone, where it would
    /// otherwise become a sheet for a list of a few rows.
    func showBacklinks(of anchor: String, at offset: Int) {
      guard let textView, var presenter = textView.window?.rootViewController,
        let range = backlinkChipRange(at: offset),
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
    /// In the popover a reference card uses, but opened by the click: its rows are
    /// buttons, which a hover card closes before the pointer can reach.
    func showBacklinks(of anchor: String, at offset: Int) {
      guard let range = backlinkChipRange(at: offset), let rect = referenceRect(for: range),
        let list = backlinksList(
          of: anchor,
          follow: { [weak self] section in
            self?.cancelHover()
            self?.followBacklink(to: section)
          })
      else { return }
      present(NSHostingController(rootView: list), size: nil, at: rect)
    }
  }
#endif
