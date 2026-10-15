#if canImport(UIKit)
  import RFCReaderKit
  import UIKit

  /// The reader's bars on iPhone: the UIKit half of `ReaderChrome`, which decides.
  /// This owns what that value cannot — the drag in progress, the tap that shows and
  /// hides them, and the report — the way `ReferenceHoverController` owns the macOS
  /// hover.
  ///
  /// What a tap on the text is for stays the coordinator's, which knows the text: it
  /// is the tap's target, and asks `ReaderChrome.action(for:discloses:isLink:toggles:)`.
  final class ReaderBars: NSObject, UIGestureRecognizerDelegate {
    private var chrome = ReaderChrome()
    private var reportedHidden = false
    /// The finger's drag on the text, from the moment it begins until the scroll it
    /// started stops: a pan moves the bars, a drag of the scroll indicator does not
    /// (`ReaderChrome.Drag`).
    private var drag: ReaderChrome.Drag?
    private weak var textView: ReaderTextView?
    /// The tap that shows and hides the bars, told apart from the text view's own
    /// recognizers in the gesture delegate.
    private weak var tap: UITapGestureRecognizer?
    /// Whether the text had a selection when the tap began, or was still moving
    /// after a flick: that tap clears the selection or stops the scroll, and is not
    /// one for the bars.
    private(set) var tapClearsSelectionOrStopsFling = false
    /// Where the tap touched, in the text view's content. Taken when it begins,
    /// because the tap is recognized only after a double tap has failed, and by then
    /// a link it followed may have scrolled the text away from under it.
    private(set) var tapPoint = CGPoint.zero
    /// Told when the bars go or come back.
    var report: (_ hidden: Bool) -> Void = { _ in }

    /// Adds the tap for the bars to `textView`, which `action` on `target` handles.
    func attach(to textView: ReaderTextView, target: Any, action: Selector) {
      self.textView = textView
      let tap = UITapGestureRecognizer(target: target, action: action)
      tap.delegate = self
      textView.addGestureRecognizer(tap)
      self.tap = tap
    }

    /// Whether the bars may go at all; see `ReaderChrome.isEnabled`.
    func setEnabled(_ enabled: Bool) {
      guard chrome.isEnabled != enabled else { return }
      chrome.isEnabled = enabled
      reportIfChanged()
    }

    /// The text view scrolled; `engineMoving` when the layout engine moved it.
    func scrolled(_ scrollView: UIScrollView, engineMoving: Bool) {
      let offset = scrollView.contentOffset.y
      let finger = scrollView.panGestureRecognizer.translation(in: scrollView).y
      // Not `isDragging`, which can stay set while a flick decelerates: the finger
      // is off the glass then, and the flick's drag is still the one scrolling.
      let touching = scrollView.isTracking
      drag = .following(drag, offset: offset, finger: finger, touching: touching)
      let insets = scrollView.adjustedContentInset
      chrome.scrolled(
        ReaderChrome.Scroll(
          offset: offset, topInset: insets.top, bottomInset: insets.bottom,
          contentHeight: scrollView.contentSize.height,
          viewportHeight: scrollView.bounds.height,
          isUserDriven: drag?.isUserDriven(
            touching: touching, decelerating: scrollView.isDecelerating,
            engineMoving: engineMoving) ?? false,
          isFlinging: scrollView.isDecelerating && !scrollView.isTracking))
      reportIfChanged()
    }

    func willBeginDragging(_ scrollView: UIScrollView) {
      drag = ReaderChrome.Drag(
        offset: scrollView.contentOffset.y,
        finger: scrollView.panGestureRecognizer.translation(in: scrollView).y)
    }

    func didEndDragging(willDecelerate decelerate: Bool) {
      if decelerate {
        drag?.lifted()
      } else {
        drag = nil
      }
    }

    func didEndDecelerating() {
      drag = nil
    }

    /// A jump to a place, which brings the bars back.
    func jumped() {
      chrome.jumped()
      reportIfChanged()
    }

    /// A tap for the bars, on the text or on the header.
    func tapped() {
      chrome.tapped()
      reportIfChanged()
    }

    /// A tap on the header's blank space, as a tap on the text is. Told by a tap
    /// gesture on the header's root (`RFCTextViewCoordinator.hostedHeader(_:in:)`),
    /// which the header's author chips and banner links take precedence over, being
    /// SwiftUI gestures below it: a tap on one of them does only what it does.
    func tappedHeader() {
      guard !tapClearsSelectionOrStopsFling else { return }
      tapped()
    }

    private func reportIfChanged() {
      let hidden = chrome.isHidden
      guard hidden != reportedHidden else { return }
      reportedHidden = hidden
      // Now, not with the report: the safe area follows the bars, which follow the
      // report, and the top inset must already know to hold.
      textView?.barsHidden = hidden
      report(hidden)
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Beside the text view's own recognizers, so a tap on a link still follows it
    /// and a long press still previews it.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // The delegate of `tap` alone, so always that one.
      true
    }

    /// After a double tap has failed: the first tap of one that selects a word is
    /// not a tap for the bars.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      guard gestureRecognizer === tap,
        let other = otherGestureRecognizer as? UITapGestureRecognizer
      else { return false }
      return other.numberOfTapsRequired > 1
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
    ) -> Bool {
      if gestureRecognizer === tap, let textView {
        tapClearsSelectionOrStopsFling =
          textView.selectedRange.length > 0 || textView.isDecelerating
        tapPoint = touch.location(in: textView)
      }
      return true
    }
  }
#endif
