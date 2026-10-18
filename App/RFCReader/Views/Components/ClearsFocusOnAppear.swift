import SwiftUI

extension View {
  /// Gives up the focus this view takes as it appears, so its first control shows no
  /// focus ring before anyone has pressed a key, while the system's ring stays for
  /// whoever then moves focus into it (#760): disabling the ring for good left a Full
  /// Keyboard Access or Switch Control user unable to see what has focus.
  func clearsFocusOnAppear() -> some View {
    modifier(ClearsFocusOnAppear())
  }
}

private struct ClearsFocusOnAppear: ViewModifier {
  /// Whether focus is anywhere in the view: a container's focus state is its
  /// descendants'.
  @FocusState private var focused: Bool

  func body(content: Content) -> some View {
    content
      .focused($focused)
      .onAppear {
        // A turn later: the focus is given after the view appears, and clearing it
        // in `onAppear` itself leaves it where it lands.
        Task { focused = false }
      }
  }
}
