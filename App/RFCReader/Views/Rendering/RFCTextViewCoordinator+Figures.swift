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
          UIAction(title: "Copy Figure", image: UIImage(systemName: "doc.on.doc")) {
            [weak self, weak textView] _ in
            // The drawing too, where it shows, as the figure's own menu copies it (#778).
            let drawn =
              box.presentation == .figure
              ? FigureMenu.itemRange(of: box, touching: range, in: textView?.textStorage ?? .init())
              : nil
            let png = drawn.flatMap { drawn in
              textView.flatMap { self?.figureImage(of: drawn, in: $0)?.pngData() }
            }
            Clipboard.write(.figure(box.content, png: png), announcing: .figure)
          })
        if let action = presentationAction(for: box) { extra.append(action) }
      }
      return extra.isEmpty ? nil : UIMenu(children: suggestedActions + extra)
    }
  }
#endif
