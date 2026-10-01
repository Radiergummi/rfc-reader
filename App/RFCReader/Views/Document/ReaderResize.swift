import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Whether the reader's pane is in a resize that is still under way, which is what
/// decides whether a new column builds at once or waits to settle
/// (`ColumnChange`, `LoadState.buildDelay(for:)`).
///
/// A window edge being dragged on the Mac is live: AppKit says so for as long as
/// the drag lasts. On iOS a rotation is one size transition with nothing to settle,
/// and UIKit says so through the transition's coordinator, which only a view
/// controller is told of; `SizeTransitionObserver` is that controller. A column
/// change that comes with no transition at all is taken as live, as every column
/// change was before.
@MainActor
final class ReaderResize {
  #if canImport(UIKit)
    /// The size transitions under way that are not interactive. A count rather
    /// than a flag, so a transition that ends inside another leaves it standing.
    fileprivate var discreteTransitions = 0

    var isLive: Bool { discreteTransitions == 0 }
  #else
    var isLive: Bool { NSApp.windows.contains { $0.inLiveResize } }
  #endif
}

#if canImport(UIKit)
  /// Tells `ReaderResize` when a size transition that is not interactive — a
  /// rotation — begins and ends. Invisible: a controller in the reader's
  /// hierarchy only because UIKit forwards `viewWillTransition(to:with:)` down the
  /// view controller hierarchy and nowhere else.
  struct SizeTransitionObserver: UIViewControllerRepresentable {
    let resize: ReaderResize

    func makeUIViewController(context: Context) -> Controller {
      let controller = Controller()
      controller.resize = resize
      return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
      controller.resize = resize
    }

    final class Controller: UIViewController {
      var resize: ReaderResize?

      override func loadView() {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        self.view = view
      }

      override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
      ) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !coordinator.isInteractive, let resize else { return }
        resize.discreteTransitions += 1
        coordinator.animate(alongsideTransition: nil) { _ in
          resize.discreteTransitions -= 1
        }
      }
    }
  }
#endif
