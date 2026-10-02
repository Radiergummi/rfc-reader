#if os(macOS)
  import AppKit

  /// Reports a column being dragged, so the toolbar can cap the title to the list it
  /// sits over.
  final class ReaderSplitViewController: NSSplitViewController {
    var didResizeSubviews: (() -> Void)?

    override func splitViewDidResizeSubviews(_ notification: Notification) {
      super.splitViewDidResizeSubviews(notification)
      didResizeSubviews?()
    }
  }
#endif
