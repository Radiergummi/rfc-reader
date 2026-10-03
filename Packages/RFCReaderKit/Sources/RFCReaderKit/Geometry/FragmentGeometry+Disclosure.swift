import CoreGraphics

extension FragmentGeometry {
  /// The three points of a heading's disclosure chevron in the outline (#698), in the
  /// fragment's coordinates: in the gutter, left of the column, centered on the
  /// heading's first line, and sized by it. Closed, it points right, at the heading;
  /// open, it points down, at the section it shows.
  public static func disclosureChevron(open: Bool, firstLine: CGRect) -> [CGPoint] {
    let size = firstLine.height * 0.16
    // Close to the heading: an iPhone's gutter is barely wider than the chevron.
    let center = CGPoint(x: firstLine.minX - size * 1.8, y: firstLine.midY)
    if open {
      return [
        CGPoint(x: center.x - size, y: center.y - size / 2),
        CGPoint(x: center.x, y: center.y + size / 2),
        CGPoint(x: center.x + size, y: center.y - size / 2),
      ]
    }
    return [
      CGPoint(x: center.x - size / 2, y: center.y - size),
      CGPoint(x: center.x + size / 2, y: center.y),
      CGPoint(x: center.x - size / 2, y: center.y + size),
    ]
  }

  /// What the fragment draws the chevron in: its points, with the slack its stroke's
  /// width and antialiasing need. Everything a fragment draws outside its glyphs has to
  /// be inside its rendering surface, or it is clipped away.
  public static func disclosureBounds(open: Bool, firstLine: CGRect) -> CGRect {
    let points = disclosureChevron(open: open, firstLine: firstLine)
    let across = points.map(\.x)
    let down = points.map(\.y)
    return CGRect(
      x: across.min() ?? 0, y: down.min() ?? 0,
      width: (across.max() ?? 0) - (across.min() ?? 0),
      height: (down.max() ?? 0) - (down.min() ?? 0)
    )
    .insetBy(dx: -2, dy: -2)
  }

  /// Where a click or tap in the gutter left of the column finds the heading it is
  /// beside: on the column's edge, at the same height. Nil for a point in the column,
  /// which is the text's: its links, its selection.
  public static func disclosureHit(atContainerPoint point: CGPoint) -> CGPoint? {
    point.x < 0 ? CGPoint(x: 0, y: point.y) : nil
  }

  /// Where the pointer is the arrow beside a heading the outline discloses, in the
  /// text view's coordinates: the gutter left of the column, the height of the
  /// heading's fragment. Exactly what a click toggles, since `disclosureHit` takes
  /// every point of it to the column's edge at a height inside the fragment.
  public static func disclosureCursorRect(fragmentFrame: CGRect, containerOrigin: CGPoint)
    -> CGRect
  {
    CGRect(
      x: 0, y: containerOrigin.y + fragmentFrame.minY, width: containerOrigin.x,
      height: fragmentFrame.height)
  }
}
