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

  /// The list for the chip at `offset`; nil when there is none there.
  func errataList(at offset: Int) -> (list: ErrataList, range: NSRange)? {
    guard let (anchor, range) = errataChip(at: offset), let items = built?.errata(of: anchor),
      !items.isEmpty
    else { return nil }
    return (ErrataList(items: items), range)
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator {
    /// A sheet, the texts being long, with a title and a Done button.
    func showErrata(at offset: Int) {
      guard let textView, var presenter = textView.window?.rootViewController,
        let (list, _) = errataList(at: offset)
      else { return }
      while let presented = presenter.presentedViewController { presenter = presented }
      let host = UIHostingController(rootView: ErrataSheet(list: list))
      host.sheetPresentationController?.detents = [.medium(), .large()]
      host.sheetPresentationController?.prefersGrabberVisible = true
      presenter.present(host, animated: true)
    }
  }

  /// `ErrataList` in a sheet of its own.
  private struct ErrataSheet: View {
    let list: ErrataList
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        list
          .navigationTitle("Errata")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { dismiss() }
            }
          }
      }
    }
  }

#else
  extension RFCTextViewCoordinator {
    /// In the popover the backlinks use, opened by the click.
    func showErrata(at offset: Int) {
      guard let (list, range) = errataList(at: offset), let rect = referenceRect(for: range)
      else { return }
      let host = NSHostingController(rootView: list)
      host.sizingOptions = []
      let fitting = host.sizeThatFits(
        in: CGSize(width: ErrataList.width, height: .greatestFiniteMagnitude))
      let size = CGSize(width: fitting.width, height: min(fitting.height, ErrataList.maximumHeight))
      hover.showBacklinks(ReferenceHoverController.Popover(content: host, size: size, anchor: rect))
    }
  }
#endif
