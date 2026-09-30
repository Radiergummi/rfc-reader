#if canImport(UIKit)
  import RFCReaderKit
  import UIKit

  extension RFCTextViewCoordinator {
    /// The edit menu of a selection, after the standard actions: "Copy as Quote" for
    /// any selection (#186), and "Copy Figure" where it holds one figure (issue #15).
    /// Nil keeps the standard menu where there is neither. Which figure and what it
    /// copies are `FigureCopy`'s, and the quote is `QuoteCitation`'s; macOS offers the
    /// same items from `ReaderTextView.menu(for:)`.
    func textView(
      _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
      var extra: [UIMenuElement] = []
      if range.length > 0, let reader = textView as? ReaderTextView {
        extra.append(
          UIAction(title: "Copy as Quote", image: UIImage(systemName: "text.quote")) { _ in
            reader.copyAsQuote()
          })
      }
      if let box = FigureCopy.box(in: range, of: textView.textStorage) {
        extra.append(
          UIAction(title: "Copy Figure", image: UIImage(systemName: "doc.on.doc")) { _ in
            UIPasteboard.general.string = FigureCopy.pasteboardText(for: box.content)
          })
        if box.shown != .plain {
          let shown: FigureControl.Segment = box.shown == .rendered ? .figure : .source
          extra.append(
            UIAction(
              title: FigureControl.title(offeredFrom: shown),
              image: UIImage(systemName: FigureControl.symbol(offeredFrom: shown))
            ) { [weak self] _ in self?.onToggleSource(box.ordinal) })
        }
      }
      return extra.isEmpty ? nil : UIMenu(children: suggestedActions + extra)
    }
  }
#endif
