import CoreGraphics

/// How wide the original text's scrollable content is, on iOS.
///
/// A `UITextView` keeps its content as wide as its frame, so the unwrapped
/// 72-column lines of an RFC as published were clipped on an iPhone with no way to
/// reach them (#240). The text view that shows them sets its content width from
/// what TextKit has laid out instead, and this is that width: the widest laid-out
/// line and the insets on either side of it, never narrower than the view, so text
/// that fits does not scroll sideways.
public enum OriginalTextLayout {
  /// - Parameters:
  ///   - usedWidth: the right edge of the laid-out text in the container, its
  ///     `usageBoundsForTextContainer.maxX`, which grows as more is laid out.
  ///   - horizontalInsets: the text container's left and right insets together.
  ///   - viewWidth: the width of the text view's bounds.
  public static func contentWidth(
    usedWidth: CGFloat, horizontalInsets: CGFloat, viewWidth: CGFloat
  ) -> CGFloat {
    // Up to a whole point: a fraction short of the last glyph clips it.
    max(viewWidth, (usedWidth + horizontalInsets).rounded(.up))
  }
}
