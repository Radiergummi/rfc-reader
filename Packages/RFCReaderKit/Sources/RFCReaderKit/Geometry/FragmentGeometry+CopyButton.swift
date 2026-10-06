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
}
