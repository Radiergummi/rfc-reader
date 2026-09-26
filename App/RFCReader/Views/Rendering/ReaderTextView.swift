import RFCReaderKit

#if canImport(UIKit)
  import UIKit

  /// The reader's text view, which copies what it means rather than what it holds.
  ///
  /// See `SelectionText`: a chip's symbol lives in the storage as an
  /// object-replacement character and its brackets do not live there at all, so the
  /// characters under a selection are not the text that selection stands for.
  final class ReaderTextView: UITextView {
    override func copy(_ sender: Any?) {
      guard let attributed = attributedText, let range = selectedTextRange, !range.isEmpty else {
        super.copy(sender)
        return
      }
      let selection = NSRange(
        location: offset(from: beginningOfDocument, to: range.start),
        length: offset(from: range.start, to: range.end)
      )
      guard selection.location != NSNotFound, NSMaxRange(selection) <= attributed.length else {
        super.copy(sender)
        return
      }
      UIPasteboard.general.string = SelectionText.plainText(
        of: attributed.attributedSubstring(from: selection))
    }
  }

#elseif canImport(AppKit)
  import AppKit

  /// The reader's text view, which copies what it means rather than what it holds.
  ///
  /// See `SelectionText`: a chip's symbol lives in the storage as an
  /// object-replacement character and its brackets do not live there at all, so the
  /// characters under a selection are not the text that selection stands for.
  final class ReaderTextView: NSTextView {
    /// Force click on a reference previews it; answers whether it did. Set by the
    /// representable, and a closure rather than the coordinator so this view stays
    /// about text.
    var quickLookReference: (NSEvent) -> Bool = { _ in false }
    /// Told before a click is tracked, so a force click's pending mouse-up is not
    /// mistaken for part of the next click.
    var willTrackMouseDown: () -> Void = {}

    /// Only a reference is taken over. Everywhere else a force click is AppKit's
    /// Look Up, which a reader of dense technical prose uses on any word.
    ///
    /// Unverified on Force Touch hardware: `NSTextView` runs its own immediate-action
    /// recognizer, which may claim the gesture before this is reached. If it does,
    /// the fallback is `pressureChange(with:)` at stage 2; see ARCHITECTURE.md.
    override func quickLook(with event: NSEvent) {
      guard !quickLookReference(event) else { return }
      super.quickLook(with: event)
    }

    /// Before `super`, which runs the whole click — `clickedOnLink` included — in its
    /// own tracking loop and does not return until the button is up.
    override func mouseDown(with event: NSEvent) {
      willTrackMouseDown()
      super.mouseDown(with: event)
    }

    /// AppKit asks for each declared type in turn. Only the plain-text flavour is
    /// rewritten -- that is the one a terminal, a mail body or a code editor reads,
    /// and the one the chip's characters are wrong for. The rich flavours stay
    /// AppKit's, because a rich target receives the attachment as an image, which is
    /// the chip's symbol and is what it looks like on screen.
    override func writeSelection(
      to pboard: NSPasteboard,
      type: NSPasteboard.PasteboardType
    ) -> Bool {
      guard type == .string else { return super.writeSelection(to: pboard, type: type) }
      let selection = attributedString().attributedSubstring(from: selectedRange())
      pboard.setString(SelectionText.plainText(of: selection), forType: .string)
      return true
    }
  }
#endif
