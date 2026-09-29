import CoreGraphics

/// Where the Go to RFC palette's panel goes, in screen coordinates.
///
/// Centred on its window and hanging from `top`, the way Spotlight hangs from the
/// menu bar, then pulled back onto the screen. A child window is not constrained to
/// the screen the way a titled one is, so a reader window dragged half off the edge
/// would otherwise take half the field being typed into with it.
public enum QuickOpenPlacement {
  /// - Parameters:
  ///   - size: the panel's frame size.
  ///   - window: the reader window's frame.
  ///   - top: where the panel's top edge goes, as a screen y.
  ///   - screen: the visible frame of the screen the window is on, if known.
  public static func origin(
    of size: CGSize,
    over window: CGRect,
    below top: CGFloat,
    screen: CGRect?
  ) -> CGPoint {
    var origin = CGPoint(x: window.midX - size.width / 2, y: top - size.height)
    if let screen {
      origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
      origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
    }
    return origin
  }
}
