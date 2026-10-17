#if canImport(UIKit)
  import UIKit

  extension UITextView {
    /// Makes this the text view `reader`'s Find opens over (#763), while it is in a
    /// window: a reader the stack keeps below its top is not, and must not take Find
    /// from the one on screen. Weakly, so a text view that has gone opens nothing.
    /// A text view installs itself again as it comes back into a window
    /// (`didMoveToWindow`), so a reader shown again takes Find back at once.
    func installsFind(in reader: ReaderState?) {
      guard let reader, window != nil else { return }
      reader.presentFind = { [weak self] in
        self?.findInteraction?.presentFindNavigator(showingReplace: false)
      }
    }
  }
#endif
