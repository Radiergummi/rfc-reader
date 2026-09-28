import SwiftUI

#if !os(macOS)
  extension View {
    /// Moves a section header out to the edge of the cards below it, where Notes
    /// sets its headers, from the inset an inset-grouped list gives them.
    ///
    /// By padding, because `.listRowInsets` does not reach a section header in these
    /// lists: measured on an iPhone, the header did not move. The distances are
    /// measured too, against Notes on the same phone: the header's leading edge sits
    /// 16 pt in from the cards', and a trailing control 8 pt further in than Notes'.
    func levelWithCards() -> some View {
      padding(.leading, -16).padding(.trailing, -8)
    }
  }
#endif
