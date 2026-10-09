import CoreGraphics

extension FragmentGeometry {
  /// Where the pointer is the arrow over a code block's copy button on the Mac
  /// (#724), in the text view's coordinates, where cursor rects are: the button's
  /// own box, laid out in the text container, moved by the container's origin.
  public static func copyButtonCursorRect(buttonFrame: CGRect, containerOrigin: CGPoint)
    -> CGRect
  {
    buttonFrame.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
  }

  /// Where the "Link copied" badge over a heading's hung number goes (#433), in the
  /// text view's coordinates: just above the number, its trailing edge on the
  /// number's, since a badge is wider than a number and the gutter is to its left.
  /// `numberFrame` is the number's box in the text container. Never past the view's
  /// leading edge, which a gutter only just wide enough for the hang would put a
  /// long badge over.
  public static func linkCopiedBadgeFrame(
    numberFrame: CGRect, badgeSize: CGSize, containerOrigin: CGPoint
  ) -> CGRect {
    CGRect(
      x: max(0, containerOrigin.x + numberFrame.maxX - badgeSize.width),
      y: containerOrigin.y + numberFrame.minY - badgeSize.height - badgeGap,
      width: badgeSize.width, height: badgeSize.height)
  }

  /// Between the badge's bottom and the number's top.
  static let badgeGap: CGFloat = 2
}
