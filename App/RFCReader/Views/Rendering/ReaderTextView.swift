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
        UIPasteboard.general.string = SelectionText.plainText(of: attributed.attributedSubstring(from: selection))
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
    /// AppKit asks for each declared type in turn. Only the plain-text flavour is
    /// rewritten -- that is the one a terminal, a mail body or a code editor reads,
    /// and the one the chip's characters are wrong for. The rich flavours stay
    /// AppKit's, because a rich target receives the attachment as an image, which is
    /// the chip's symbol and is what it looks like on screen.
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
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
        guard let figure = FigureCopy.figure(at: clicked, in: text) ?? FigureCopy.figure(in: selectedRange(), of: text) else {
            return standard
        }
        // A copy, so the item is never left behind in a menu AppKit hands out again.
        let result = (standard?.copy() as? NSMenu) ?? NSMenu()
        let item = NSMenuItem(title: "Copy Figure", action: #selector(copyFigure(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = FigureCopy.pasteboardText(for: figure)
        if !result.items.isEmpty {
            result.insertItem(.separator(), at: 0)
        }
        result.insertItem(item, at: 0)
        return result
    }

    @objc private func copyFigure(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif
