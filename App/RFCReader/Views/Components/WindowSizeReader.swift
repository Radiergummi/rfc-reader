#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// Reports the size of the window a view is in, which SwiftUI does not say: a
  /// context menu's preview is shown over the whole window and sized against it, as
  /// the reader's own previews are (`LinkPreview.documentSize(fitting:)`, #580).
  struct WindowSizeReader: UIViewRepresentable {
    let report: (CGSize) -> Void

    func makeUIView(context: Context) -> ReaderView {
      ReaderView()
    }

    func updateUIView(_ view: ReaderView, context: Context) {
      view.report = report
    }

    final class ReaderView: UIView {
      var report: (CGSize) -> Void = { _ in }
      private var reported: CGSize?

      override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
      }

      /// Laid out again whenever the view it is the background of is, which a
      /// window's resize does.
      override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = window?.bounds.size, size != reported else { return }
        reported = size
        // Not during the layout SwiftUI's update is part of.
        let report = report
        Task { report(size) }
      }
    }
  }
#endif
