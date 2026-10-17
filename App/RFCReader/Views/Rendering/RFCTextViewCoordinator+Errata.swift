import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// A heading's errata chip (#387): a click or a tap lists the section's errata. What
// the list holds is `BuiltDocument.errata(of:)`, and where the chip is
// `errataChip(at:)`; this is only where it is shown.

extension RFCTextViewCoordinator {
  /// The errata chip at `offset` in the reader's text.
  func errataChip(at offset: Int) -> (anchor: String, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.errataChip(at: offset)
  }

  /// Whether the link at `offset` lists something beside it rather than going
  /// anywhere: a backlink caption or an errata chip, whose links are ours alone, so
  /// no menu offers to copy or share them.
  func listsRatherThanGoes(at offset: Int) -> Bool {
    backlinkCaption(at: offset) != nil || errataChip(at: offset) != nil
  }

  /// What the chip at `offset` lists, and its extent; nil when there is none there.
  func errata(at offset: Int) -> (items: [ErrataSummary.Item], range: NSRange)? {
    guard let (anchor, range) = errataChip(at: offset), let items = built?.errata(of: anchor),
      !items.isEmpty
    else { return nil }
    return (items, range)
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator {
    /// A sheet, the texts being long, with a title and a Done button.
    func showErrata(at offset: Int) {
      guard let textView, var presenter = textView.window?.rootViewController,
        let (items, _) = errata(at: offset)
      else { return }
      while let presented = presenter.presentedViewController { presenter = presented }
      let host = UIHostingController(rootView: ErrataSheet(items: items))
      // Presented by UIKit, which does not read the sheet's `presentationDetents`.
      host.sheetPresentationController?.detents = [.medium(), .large()]
      presenter.present(host, animated: true)
    }
  }

#else
  extension RFCTextViewCoordinator {
    /// In the popover the backlinks use, opened by the click.
    func showErrata(at offset: Int) {
      guard let (items, range) = errata(at: offset), let rect = referenceRect(for: range)
      else { return }
      let host = NSHostingController(rootView: ErrataList(items: items))
      host.sizingOptions = []
      let size = host.sizeThatFits(
        in: CGSize(width: ErrataList.width, height: .greatestFiniteMagnitude))
      hover.showBacklinks(ReferenceHoverController.Popover(content: host, size: size, anchor: rect))
    }
  }
#endif
