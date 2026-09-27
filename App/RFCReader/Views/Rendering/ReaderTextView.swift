import RFCKit
import RFCReaderKit

#if canImport(UIKit)
  import UIKit

  /// The reader's text view, which copies what it means rather than what it holds.
  ///
  /// See `SelectionText`: a chip's symbol lives in the storage as an
  /// object-replacement character and its brackets do not live there at all, so the
  /// characters under a selection are not the text that selection stands for.
  final class ReaderTextView: UITextView {
    /// The reader runs under the home indicator (`DocumentView` lets it into the
    /// bottom safe area), so the strip that area covers becomes room to scroll the
    /// last line clear of it rather than a place the text stops at.
    ///
    /// By hand, because `contentInsetAdjustmentBehavior` is `.never`: automatic
    /// adjustment would move `contentOffset`'s origin away from the top of the
    /// content, which is what the anchor arithmetic is expressed in. Only the
    /// bottom is set here, and a bottom inset leaves that origin where it is.
    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      guard contentInset.bottom != safeAreaInsets.bottom else { return }
      contentInset.bottom = safeAreaInsets.bottom
      verticalScrollIndicatorInsets.bottom = safeAreaInsets.bottom
    }

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

    /// "Copy Figure" for the figure under the click, or else the one the selection
    /// holds (issue #15). First in the menu, because on a figure it is what the
    /// menu was opened for. Which figure and what it copies are `FigureCopy`'s.
    override func menu(for event: NSEvent) -> NSMenu? {
      let standard = super.menu(for: event)
      let text = attributedString()
      let clicked = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
      guard
        let figure = FigureCopy.figure(at: clicked, in: text)
          ?? FigureCopy.figure(in: selectedRange(), of: text)
      else {
        return standard
      }
      // A copy, so the item is never left behind in a menu AppKit hands out again.
      let result = (standard?.copy() as? NSMenu) ?? NSMenu()
      let item = NSMenuItem(
        title: "Copy Figure", action: #selector(copyFigure(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = figure
      if !result.items.isEmpty {
        result.insertItem(.separator(), at: 0)
      }
      result.insertItem(item, at: 0)
      return result
    }

    @objc private func copyFigure(_ sender: NSMenuItem) {
      guard let figure = sender.representedObject as? Preformatted else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(FigureCopy.pasteboardText(for: figure), forType: .string)
    }

    // MARK: - What VoiceOver reads (#12)

    /// A diagram is said as its label, not read out one box-drawing character at a
    /// time. `AccessibleReading` decides what each part of `range` becomes; the text
    /// parts come from `super`, so they keep every attribute AppKit gives VoiceOver.
    ///
    /// Only the per-range accessors. `accessibilityValue` stays the real text, because
    /// its length is the character count every range VoiceOver asks for is measured
    /// in.
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
      AccessibleReading.reading(
        range,
        in: attributedString(),
        text: { super.accessibilityAttributedString(for: $0) },
        label: { NSAttributedString(string: $0) },
        join: { parts in
          let joined = NSMutableAttributedString()
          parts.forEach(joined.append)
          return joined
        })
    }

    /// Each accessor asks its own `super` for the text, never the other override:
    /// whether AppKit builds one from the other is not ours to know, and if it did,
    /// the two overrides would call each other forever.
    override func accessibilityString(for range: NSRange) -> String? {
      AccessibleReading.reading(
        range,
        in: attributedString(),
        text: { super.accessibilityString(for: $0) },
        label: { $0 },
        join: { $0.joined() })
    }
  }
#endif
