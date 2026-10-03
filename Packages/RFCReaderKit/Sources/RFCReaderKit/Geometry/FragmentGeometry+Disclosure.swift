import CoreGraphics

extension FragmentGeometry {
  /// Where a heading's text sits on its first line, in the fragment's coordinates:
  /// its baseline, and how tall its capitals are, which is what the eye centers a
  /// mark beside a heading on.
  public struct HeadingText: Sendable, Equatable {
    public var baseline: CGFloat
    public var capHeight: CGFloat

    public init(baseline: CGFloat, capHeight: CGFloat) {
      self.baseline = baseline
      self.capHeight = capHeight
    }
  }

  /// The three points of a heading's disclosure chevron in the outline (#698), in the
  /// fragment's coordinates: in the gutter, left of the column and clear of it,
  /// centered on the middle of the heading's capitals, and sized by them. Closed, it
  /// points right, at the heading; open, it points down, at the section it shows.
  public static func disclosureChevron(open: Bool, firstLine: CGRect, text: HeadingText)
    -> [CGPoint]
  {
    let size = text.capHeight * 0.32
    // Far enough from the heading to read as its own mark, near enough for an
    // iPhone's gutter, which is barely wider than the chevron.
    let center = CGPoint(x: firstLine.minX - size * 2.6, y: text.baseline - text.capHeight / 2)
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
  public static func disclosureBounds(open: Bool, firstLine: CGRect, text: HeadingText)
    -> CGRect
  {
    let points = disclosureChevron(open: open, firstLine: firstLine, text: text)
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
