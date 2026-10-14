#if canImport(UIKit)
  import RFCReaderKit
  import SwiftUI
  import UIKit

  extension RFCTextViewCoordinator {
    /// The long-press menu of a defined term's gloss (#396): its card lifted, as a
    /// reference's is, over Go to Definition. Nil where the item is no gloss's.
    func glossMenu(for textItem: UITextItem, in textView: UITextView)
      -> UITextItem.MenuConfiguration?
    {
      guard let environment, let (box, _) = gloss(at: textItem.range.location) else { return nil }
      var children: [UIMenuElement] = []
      if let follow = goToDefinition(of: box.gloss) {
        children.append(
          UIAction(
            title: String(localized: "Go to Definition"),
            image: UIImage(systemName: "arrow.turn.down.right")
          ) { _ in follow() })
      }
      let host = UIHostingController(
        rootView: AnyView(GlossCard(gloss: box.gloss).readerEnvironment(environment)))
      // Sized here, as a reference's card is: a hosting controller's view is not
      // sized to its content until something lays it out.
      host.view.frame.size = host.sizeThatFits(
        in: CGSize(width: ReferencePreview.width, height: CGFloat.greatestFiniteMagnitude))
      return UITextItem.MenuConfiguration(
        preview: .view(previewView(hosting: host)), menu: UIMenu(title: "", children: children))
    }
  }
#endif
