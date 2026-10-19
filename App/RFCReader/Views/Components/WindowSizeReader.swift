#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// The size of the window a view is in, read when it is asked for, which SwiftUI
  /// does not say: a context menu's preview is shown over the whole window and sized
  /// against it at the press, as the reader's own previews are
  /// (`LinkPreview.documentSize(fitting:)`, #580). Put in place with `reading(_:)`.
  final class WindowSizeReader {
    fileprivate weak var view: UIView?

    var size: CGSize? { view?.window?.bounds.size }
  }

  extension View {
    /// Lets `reader` find the window this view is in.
    func reading(_ reader: WindowSizeReader) -> some View {
      background(WindowSizeReaderView(reader: reader))
    }
  }

  private struct WindowSizeReaderView: UIViewRepresentable {
    let reader: WindowSizeReader

    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.isUserInteractionEnabled = false
      reader.view = view
      return view
    }

    func updateUIView(_ view: UIView, context: Context) {
      reader.view = view
    }
  }
#endif
