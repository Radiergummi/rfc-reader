import CoreGraphics

extension FragmentGeometry {
  /// The three points of a heading's disclosure chevron in the outline (#698), in the
  /// fragment's coordinates: in the gutter, left of the column, centered on the
  /// heading's first line, and sized by it. Closed, it points right, at the heading;
  /// open, it points down, at the section it shows.
  public static func disclosureChevron(open: Bool, firstLine: CGRect) -> [CGPoint] {
    let size = firstLine.height * 0.22
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
}
