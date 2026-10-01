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
  /// The text container's size: unbounded across, so lines never wrap, and
  /// unbounded down. UIKit clamps a touch into the container before it looks for
  /// the character under it, so a container of no height put every selection on
  /// the first line (#240).
  public static let containerSize = CGSize(
    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

  /// - Parameters:
  ///   - usedWidth: the right edge of the laid-out text in the container, its
  ///     `usageBoundsForTextContainer.maxX`, which grows as more is laid out.
  ///   - horizontalInsets: the text container's left and right insets together.
  ///   - viewWidth: the width of the text view's bounds.
  public static func contentWidth(
    usedWidth: CGFloat, horizontalInsets: CGFloat, viewWidth: CGFloat
  ) -> CGFloat {
    let needed = usedWidth + horizontalInsets
    // Compared before rounding, so text that fits a view a fraction of a point wide
    // does not scroll sideways by that fraction; rounded up past it, since a
    // fraction short of the last glyph clips it.
    return needed <= viewWidth ? viewWidth : needed.rounded(.up)
  }
}
