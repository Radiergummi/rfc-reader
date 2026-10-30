#if canImport(UIKit)
  import RFCReaderKit
  import UIKit

  extension RFCTextViewCoordinator {
    /// The edit menu of a selection, after the standard actions: "Copy as Quote" for
    /// any selection (#186), or "Copy as Text" where Copy copies a quote, "Copy
    /// Citation" (#712) and Highlight's colors (#522); and "Copy Figure" where it holds
    /// one figure (issue #15).
    /// Nil keeps the standard menu where there is neither. Which figure and what it
    /// copies are `FigureCopy`'s, and the quote is `QuoteCitation`'s; macOS offers the
    /// same items from `ReaderTextView.menu(for:)`.
    func textView(
      _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
      var extra: [UIMenuElement] = []
      if range.length > 0, let reader = textView as? ReaderTextView, !reader.isTranslation() {
        if ReaderSettings(defaults: .standard).copyFormat == .quote {
          extra.append(
            UIAction(
              title: String(localized: "Copy as Text"), image: UIImage(systemName: "doc.on.doc")
            ) { _ in
              reader.copyAsText()
            })
        } else {
          extra.append(
            UIAction(
              title: String(localized: "Copy as Quote"), image: UIImage(systemName: "text.quote")
            ) { _ in
              reader.copyAsQuote()
            })
        }
        if reader.citeSelection(range) != nil {
          extra.append(
            UIAction(
              title: String(localized: "Copy Citation"),
              image: UIImage(systemName: "quote.opening")
            ) { _ in
              reader.copyCitation(nil)
            })
        }
        extra.append(highlightMenu(for: range))
        // A highlight and a note on it (#523), as Books makes one.
        extra.append(
          UIAction(
            title: String(localized: "Add Note"), image: UIImage(systemName: "square.and.pencil")
          ) { [weak self] _ in
            self?.addNote(onSelection: range)
          })
        // A note on the block the selection starts in, or on its section from a
        // heading: iOS has no context menu on unselected text to offer it from.
        if let block = noteBlock(at: range.location) {
          extra.append(
            UIAction(title: Self.addNoteTitle(block)) { [weak self] _ in
              self?.addNote(on: block, at: range.location)
            })
        }
      }
      if let box = FigureCopy.box(in: range, of: textView.textStorage) {
        extra.append(
          UIAction(
            title: String(localized: "Copy Figure"), image: UIImage(systemName: "doc.on.doc")
          ) { [weak self, weak textView] _ in
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
