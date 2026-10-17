import SwiftUI

extension EnvironmentValues {
  /// Whether a control in a view that `focusRingAfterKey()` holds shows the system's
  /// focus ring: once a key has been pressed in that view, and always elsewhere.
  @Entry var showsFocusRing = true
}

extension View {
  /// Shows the system's focus ring in this view only once a key is pressed in it
  /// (#760). A pane or popover takes focus as it opens, which drew a ring round its
  /// first control before anyone had pressed a key; disabling the ring for good left
  /// a Full Keyboard Access or Switch Control user unable to see what has focus.
  ///
  /// The first Tab reveals the ring where focus already is, the first control,
  /// rather than moving it on: that is where Tab's first stop belongs.
  func focusRingAfterKey() -> some View {
    modifier(FocusRingAfterKey())
  }

  /// The system's focus ring on this control, unless `focusRingAfterKey()` is still
  /// holding it back.
  func focusRingWhenShown() -> some View {
    modifier(FocusRingWhenShown())
  }
}

private struct FocusRingAfterKey: ViewModifier {
  @State private var showsRing = false

  func body(content: Content) -> some View {
    content
      .environment(\.showsFocusRing, showsRing)
      .onKeyPress(phases: .down) { press in
        guard !showsRing else { return .ignored }
        showsRing = true
        return press.key == .tab ? .handled : .ignored
      }
  }
}

private struct FocusRingWhenShown: ViewModifier {
  @Environment(\.showsFocusRing) private var showsFocusRing

  func body(content: Content) -> some View {
    content.focusEffectDisabled(!showsFocusRing)
  }
}
