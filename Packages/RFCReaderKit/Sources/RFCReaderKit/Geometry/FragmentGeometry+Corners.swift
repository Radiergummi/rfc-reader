import CoreGraphics

extension FragmentGeometry {
  /// The corner radius of a reference chip, in the reader and wherever a chip is
  /// drawn to look like one.
  public static let chipRadius: CGFloat = 6
  /// The hairline an informative chip is drawn with, and every chip under Increase
  /// Contrast (#457): a point, which holds 3:1 where a pixel-wide line would read
  /// fainter than its color.
  public static let chipOutlineWidth: CGFloat = 1

  /// Where a chip's outline is stroked, in device pixels: `chip`, a chip's box in
  /// device pixels, with its edges on whole pixels, and in by half the `lineWidth`,
  /// in device pixels too, so the stroke covers whole pixels inside the box. A
  /// hairline across two half-covered pixels is antialiased to half its color, and
  /// an outline held to 3:1 then draws fainter than that.
  public static func chipOutlineRect(_ chip: CGRect, lineWidth: CGFloat) -> CGRect {
    let minX = chip.minX.rounded()
    let minY = chip.minY.rounded()
    let snapped = CGRect(
      x: minX, y: minY, width: chip.maxX.rounded() - minX, height: chip.maxY.rounded() - minY)
    return snapped.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
  }

  /// The outline of a chip's piece on one line (#457): a closed rounded box where
  /// the chip is whole, and open where it continues onto the next line or from the
  /// previous one. A fill there meets nothing; a line there would close a wrapped
  /// chip into two boxes, with a stroke against the glyphs at the break.
  public static func chipOutlinePath(
    in rect: CGRect, cornerRadius: CGFloat, leading: Bool, trailing: Bool
  ) -> CGPath {
    if leading, trailing {
      return roundedPath(
        in: rect, cornerRadius: cornerRadius, corners: Corners(leading: true, trailing: true))
    }
    let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
    let path = CGMutablePath()
    switch (leading, trailing) {
    case (false, true):
      // Along the top, round the trailing end, back along the bottom.
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
      path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    case (true, false):
      // Along the bottom, round the leading end, back along the top.
      path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
      path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    default:
      // A line the chip runs right across: its top and its bottom.
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    }
    return path
  }

  /// The corner radius of a card behind artwork and tables.
  public static let cardRadius: CGFloat = 8

  /// Which corners `roundedPath` rounds.
  public struct Corners: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let topLeft = Corners(rawValue: 1 << 0)
    public static let topRight = Corners(rawValue: 1 << 1)
    public static let bottomLeft = Corners(rawValue: 1 << 2)
    public static let bottomRight = Corners(rawValue: 1 << 3)
    public static let top: Corners = [.topLeft, .topRight]
    public static let bottom: Corners = [.bottomLeft, .bottomRight]
    public static let left: Corners = [.topLeft, .bottomLeft]
    public static let right: Corners = [.topRight, .bottomRight]

    /// A band that runs down the page: rounded where the run starts and ends,
    /// square where it continues into the next fragment.
    public init(first: Bool, last: Bool) {
      self = []
      if first { formUnion(.top) }
      if last { formUnion(.bottom) }
    }

    /// A chip that runs along a line: rounded at the ends of the run, square where
    /// it continues onto the next line.
    public init(leading: Bool, trailing: Bool) {
      self = []
      if leading { formUnion(.left) }
      if trailing { formUnion(.right) }
    }
  }

  /// `rect`, rounded only on the corners named — square where a decoration's band
  /// continues into the next or previous fragment, rounded where the band starts
  /// or ends. `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)` has no
  /// per-corner variant, hence the manual path. The reference chip needs this at
  /// a finer grain than the card and the rule do: a chip that wraps across a
  /// line break rounds the left two corners on its first line and the right two
  /// on its last, which top/bottom rounding alone cannot express.
  ///
  /// The radius is cut to half the shorter side, so a thin band ends in half
  /// circles rather than a path that crosses itself.
  public static func roundedPath(in rect: CGRect, cornerRadius: CGFloat, corners: Corners)
    -> CGPath
  {
    let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
    let topLeftRadius = corners.contains(.topLeft) ? radius : 0
    let topRightRadius = corners.contains(.topRight) ? radius : 0
    let bottomRightRadius = corners.contains(.bottomRight) ? radius : 0
    let bottomLeftRadius = corners.contains(.bottomLeft) ? radius : 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + topLeftRadius))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY),
      tangent2End: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY), radius: topLeftRadius)
    path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRightRadius), radius: topRightRadius)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY),
      radius: bottomRightRadius)
    path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeftRadius), radius: bottomLeftRadius)
    path.closeSubpath()
    return path
  }
}
