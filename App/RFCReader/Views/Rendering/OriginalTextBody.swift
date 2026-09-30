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

#if os(iOS)
  import RFCReaderKit
  import SwiftUI
  import UIKit

  /// The RFC as published on iOS, in a `UITextView` rather than a SwiftUI `Text`, for
  /// the reasons the macOS one is an `NSTextView`: incremental layout and Find
  /// (#159, #240).
  ///
  /// Lines never wrap, so the view has to scroll sideways, which a `UITextView` does
  /// not: it keeps its content as wide as its frame, whatever its container. The
  /// text view below widens its content to what has been laid out.
  struct OriginalTextBody {
    let text: String
    let fontSize: Double

    /// The monospaced face the text is set in, as on macOS.
    fileprivate var font: UIFont {
      .monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular)
    }

    fileprivate var attributed: NSAttributedString {
      NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
    }

    /// What the storage last received, so an update pass that changes neither does
    /// not rewrite a whole RFC's text.
    final class Coordinator {
      var shown: (text: String, fontSize: Double)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
  }

  extension OriginalTextBody: UIViewRepresentable {
    func makeUIView(context: Context) -> SidewaysTextView {
      let textView = SidewaysTextView(usingTextLayoutManager: true)
      textView.isEditable = false
      textView.isSelectable = true
      textView.isFindInteractionEnabled = true
      textView.backgroundColor = .clear
      textView.alwaysBounceVertical = true
      textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
      // Not wrapping: the container is unbounded across, and the content grows to
      // what is laid out in it.
      textView.textContainer.lineFragmentPadding = 0
      textView.textContainer.widthTracksTextView = false
      textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0)
      return textView
    }

    func updateUIView(_ textView: SidewaysTextView, context: Context) {
      if let shown = context.coordinator.shown, shown == (text, fontSize) { return }
      // Through the text storage, never the content storage's `attributedString`,
      // which silently discards the backing store; see `NSTextContentStorage.install(_:)`.
      textView.textStorage.setAttributedString(attributed)
      context.coordinator.shown = (text, fontSize)
    }
  }

  /// A `UITextView` whose content is as wide as its laid-out text, so unwrapped lines
  /// scroll sideways rather than being clipped at the frame.
  ///
  /// UIKit keeps the content size's width at the frame's; this replaces that width
  /// on its way in, and asks again after each layout pass, since incremental layout
  /// widens what has been laid out as the text scrolls.
  final class SidewaysTextView: UITextView {
    override var contentSize: CGSize {
      get { super.contentSize }
      set { super.contentSize = CGSize(width: laidOutWidth, height: newValue.height) }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      // UIKit narrows the container to the frame although it does not track the
      // view's width: on an iPhone the lines wrapped at 345 pt until this put the
      // unbounded width back (#240).
      if textContainer.size.width != Self.unbounded {
        textContainer.size = CGSize(width: Self.unbounded, height: 0)
      }
      if contentSize.width != laidOutWidth { contentSize = super.contentSize }
    }

    /// Plain text, so Copy puts only the string on the pasteboard, as on macOS: as
    /// rich text it carries `label` resolved for the current appearance, and text
    /// copied in dark mode pastes near-white into a light document.
    override func copy(_ sender: Any?) {
      guard let range = selectedTextRange, let selected = text(in: range) else { return }
      UIPasteboard.general.string = selected
    }

    private static let unbounded = CGFloat.greatestFiniteMagnitude

    private var laidOutWidth: CGFloat {
      OriginalTextLayout.contentWidth(
        usedWidth: textLayoutManager?.usageBoundsForTextContainer.maxX ?? 0,
        horizontalInsets: textContainerInset.left + textContainerInset.right,
        viewWidth: bounds.width)
    }
  }
#endif
