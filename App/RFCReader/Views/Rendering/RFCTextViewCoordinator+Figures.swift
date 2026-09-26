#if canImport(UIKit)
import RFCReaderKit
import UIKit

extension RFCTextViewCoordinator {
    /// "Copy Figure" in the edit menu of a selection that holds one figure (issue
    /// #15), after the standard actions. Nil keeps the standard menu everywhere
    /// else. Which figure and what it copies are `FigureCopy`'s; macOS offers the
    /// same item from `ReaderTextView.menu(for:)`.
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let figure = FigureCopy.figure(in: range, of: textView.attributedText) else { return nil }
        let text = FigureCopy.pasteboardText(for: figure)
        let copy = UIAction(title: "Copy Figure", image: UIImage(systemName: "doc.on.doc")) { _ in
            UIPasteboard.general.string = text
        }
        return UIMenu(children: suggestedActions + [copy])
    }
}
#endif
