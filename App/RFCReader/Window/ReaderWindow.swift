#if os(macOS)
  import AppKit
  import RFCReaderKit

  /// The window, which is also where focus is decided.
  ///
  /// Every split item is its own `NSHostingController`, and SwiftUI's focus does not
  /// cross one: the list setting its own `@FocusState` cannot take first responder off
  /// the sidebar's search field, because those are two hosting views with two focus
  /// stores of their own. Measured — clicking a row selected it and left first
  /// responder exactly where it already was, so the list drew its selection in the
  /// inactive grey and the arrow keys went to whoever did hold it. Under
  /// `NavigationSplitView` the question never arose: one hosting view is one focus
  /// scope, and SwiftUI moved focus between the columns itself.
  ///
  /// AppKit can move first responder between them, and a click is the one moment the
  /// window knows which root the reader means. `NSTableView` and `NSTextView` each do
  /// this for themselves from `mouseDown`; SwiftUI's list does not, so the window does
  /// it on their behalf, for whatever was clicked. Measured on a click that landed on
  /// a list row while the sidebar's search field held focus:
  ///
  ///     hit              CellHostingView<...>
  ///     was              SwiftUI...SystemTextFieldFieldEditor
  ///     made             SwiftUIOutlineListView -> true
  ///     0.8 s later      SwiftUIOutlineListView
  ///
  /// -- so SwiftUI does not take it back, and the arrow keys walk the list from there.
  ///
  /// Which view to hand it to is `FirstResponderSearch`, in `RFCReaderKit`, because
  /// that part is a pure function of a view tree and this target has no test bundle.
  /// What stays here is the AppKit half: the event hook, the hit test, and
  /// `makeFirstResponder`.
  final class ReaderWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
      if event.type == .leftMouseDown { giveFocus(toViewUnder: event) }
      super.sendEvent(event)
    }

    private func giveFocus(toViewUnder event: NSEvent) {
      guard let content = contentView else { return }
      let point = content.convert(event.locationInWindow, from: nil)
      // Not a click on the toolbar. `.fullSizeContentView` runs the content view up
      // under the titlebar, and the toolbar's items are AppKit's, in a sibling of
      // the content view — so a click on the bookmark button or on Back hit-tests
      // straight through to whichever column happens to lie beneath it, and would
      // hand that column first responder. Arrow-keying the list and then clicking
      // a toolbar button would quietly move the keys into the reader.
      //
      // `contentLayoutRect` is the band below the titlebar and toolbar. Measured
      // on the built window, it and the content view's own space coincide, so the
      // converted point can be tested against it directly:
      //
      //     contentLayoutRect  (0, 0, 1400, 848)
      //     contentView.bounds (0, 0, 1400, 900)   isFlipped = false
      //
      // -- the toolbar is the top 52 pt, which in an unflipped view is the y the
      // rect excludes.
      guard contentLayoutRect.contains(point) else { return }
      guard let hit = content.hitTest(point) else { return }
      let target = FirstResponderSearch.target(from: hit, upTo: content, skipping: firstResponder)
      guard let target else { return }
      makeFirstResponder(target)
    }

    /// Puts first responder inside `view` when the window opens, so the arrow keys
    /// walk the library without a click to wake them first.
    ///
    /// Reports whether it found anything to focus. A window becomes key before
    /// SwiftUI has necessarily built the list's table, and the caller retries on the
    /// next activation rather than guessing at a delay — the same reason the panel's
    /// rule is applied where a tab is made rather than a run loop turn later.
    func giveFocus(inside view: NSView) -> Bool {
      guard let target = FirstResponderSearch.innermostTarget(in: view) else { return false }
      return makeFirstResponder(target)
    }
  }
#endif
