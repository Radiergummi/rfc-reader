import SwiftUI

extension View {
  /// Puts `value` back to `resting` a while after it leaves it: a check for a moment
  /// after a copy, a warning after a download that failed, and then the control's own
  /// icon again. One modifier rather than a sleep and a reset written out at each
  /// such control (#604).
  func resets<Value: Equatable>(
    _ value: Binding<Value>, to resting: Value, after delay: Duration
  ) -> some View {
    modifier(ResetAfterDelay(value: value, resting: resting, delay: delay))
  }
}

/// The wait is a task per value, so a new value starts it again and it ends with the
/// view. A wait cut short still resets, as the sites it replaced did, but only the
/// value it was waiting on: a newer one has a wait of its own, and resetting it from
/// here would take it off screen the moment it was shown.
private struct ResetAfterDelay<Value: Equatable>: ViewModifier {
  @Binding var value: Value
  let resting: Value
  let delay: Duration

  func body(content: Content) -> some View {
    content.task(id: value) {
      let waitingOn = value
      guard waitingOn != resting else { return }
      try? await Task.sleep(for: delay)
      guard value == waitingOn else { return }
      value = resting
    }
  }
}
