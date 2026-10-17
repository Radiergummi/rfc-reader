#if canImport(UIKit)
  import UIKit

  extension UITextView {
    /// Makes this the text view `reader`'s Find opens over (#763). Weakly, so a text
    /// view that has gone opens nothing until the next one installs itself.
    func installsFind(in reader: ReaderState) {
      reader.presentFind = { [weak self] in
        self?.findInteraction?.presentFindNavigator(showingReplace: false)
      }
    }
  }
#endif
