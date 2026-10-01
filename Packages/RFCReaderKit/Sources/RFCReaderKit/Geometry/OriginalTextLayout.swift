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
  /// The text container's size: unbounded down, and wider than any line, so lines
  /// never wrap (#240).
  ///
  /// The height is unbounded because UIKit clamps a touch into the container
  /// before it looks for the character under it, and a container of no height put
  /// every selection on the first line. The width is not, because a `UITextView`
  /// takes a container 10,000,000 points wide or more as having no width and cuts
  /// the selection's highlight at the view's own width: past the right edge of an
  /// iPhone a selection had no highlight, and its end handle stayed at that edge.
  /// A million points is still some 40,000 columns at the largest text size.
  public static let containerSize = CGSize(
    width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)

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

  /// Where a view scrolled sideways is scrolled to once its content has changed
  /// width, as it does when the text size changes: the same place in the lines,
  /// scaled to the new width, and no further than the content scrolls.
  ///
  /// - Parameters:
  ///   - offset: the horizontal content offset before the change.
  ///   - previousContentWidth: the content width before the change.
  ///   - contentWidth: the content width after it.
  ///   - viewWidth: the width of the view's bounds.
  public static func horizontalOffset(
    _ offset: CGFloat, scaledFrom previousContentWidth: CGFloat, to contentWidth: CGFloat,
    viewWidth: CGFloat
  ) -> CGFloat {
    guard previousContentWidth > 0 else { return 0 }
    let scaled = offset * contentWidth / previousContentWidth
    let furthest = max(0, contentWidth - viewWidth)
    return min(max(0, scaled), furthest)
  }
}
