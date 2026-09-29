#if os(macOS)
  import AppKit
  import SwiftUI

  /// The RFC as published on macOS, in an `NSTextView` rather than a SwiftUI `Text`.
  ///
  /// One `Text` held the whole depaginated source: one layout pass over it on the main
  /// thread before anything drew, and no find in the document (#159) -- the reasons the
  /// reader body is TextKit 2 as well (ARCHITECTURE.md, "Decision: TextKit 2 for the
  /// reader body"). A plain text view gets incremental layout, Find and selection from
  /// the platform. It is not `RFCTextView`: none of that view's decorations, chips or
  /// anchors apply to text shown exactly as it was published.
  ///
  /// Lines never wrap, as they did not in the scroll view this replaces: the source is
  /// set in 72 columns, and its artwork only reads at its own width.
  struct OriginalTextBody {
    let text: String
    let fontSize: Double

    /// The monospaced face the text is set in, a little smaller than the reader's
    /// body so a 72-column page fits beside it.
    fileprivate var font: NSFont {
      .monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular)
    }

    fileprivate var attributed: NSAttributedString {
      NSAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    /// What the storage last received, so an update pass that changes neither does
    /// not rewrite a whole RFC's text.
    final class Coordinator {
      var shown: (text: String, fontSize: Double)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
  }

  extension OriginalTextBody: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = NSTextView.scrollableTextView()
      scrollView.hasHorizontalScroller = true
      scrollView.drawsBackground = false
      guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
      textView.isEditable = false
      textView.isSelectable = true
      // Plain text, so Copy puts only the string on the pasteboard. As rich text it
      // also wrote RTF carrying `labelColor` resolved for the current appearance:
      // copied in dark mode, it pasted near-white into a light document.
      textView.isRichText = false
      textView.usesFindBar = true
      textView.isIncrementalSearchingEnabled = true
      textView.drawsBackground = false
      textView.textContainerInset = NSSize(width: 24, height: 24)
      // Not wrapping: the container is unbounded across, and the view grows to it.
      textView.isHorizontallyResizable = true
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      textView.textContainer?.widthTracksTextView = false
      textView.textContainer?.containerSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      if let shown = context.coordinator.shown, shown == (text, fontSize) { return }
      guard let textView = scrollView.documentView as? NSTextView else { return }
      // Through the text storage, never the content storage's `attributedString`,
      // which silently discards the backing store; see `NSTextContentStorage.install(_:)`.
      textView.textStorage?.setAttributedString(attributed)
      context.coordinator.shown = (text, fontSize)
    }

    /// Detaches the text view from its container, so what AppKit keeps of a TextKit 2
    /// text view after it is gone does not hold the whole RFC; see
    /// `RFCTextViewCoordinator.releaseDocument()` (#356).
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
      (scrollView.documentView as? NSTextView)?.textContainer?.textView = nil
    }
  }
#endif
