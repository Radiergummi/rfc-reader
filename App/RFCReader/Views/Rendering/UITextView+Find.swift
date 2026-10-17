#if canImport(UIKit)
  import UIKit

  extension UITextView {
    /// Makes this the text view `reader`'s Find opens over while it is in a window
    /// (#763), and gives Find up as it leaves one: a reader the stack keeps below its
    /// top must not take Find from the one on screen. Called again as the text view
    /// comes back into a window (`didMoveToWindow`), so a reader shown again takes
    /// Find back at once.
    func installsFind(in reader: ReaderState?) {
      guard let reader else { return }
      if window != nil {
        reader.findTextView = self
      } else if reader.findTextView === self {
        reader.findTextView = nil
      }
    }
  }
#endif
