import CoreGraphics

extension FragmentGeometry {
  /// The corner radius of a reference chip, in the reader and wherever a chip is
  /// drawn to look like one.
  public static let chipRadius: CGFloat = 6

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
