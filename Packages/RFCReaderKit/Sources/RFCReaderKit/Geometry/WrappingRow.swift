import CoreGraphics

/// Where the header's author chips land (#19): left to right, starting a new line
/// wherever the next one would not fit, each centered on its line. The sizes are
/// the chips' own, already clamped to the line by the caller, which alone can ask
/// a view how it fits a narrower width.
public enum WrappingRow {
  /// One frame per size, in order, with the first line's top-left at the origin.
  public static func frames(for sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [CGRect] {
    var frames: [CGRect] = []
    var line: [CGSize] = []
    var lineWidth: CGFloat = 0
    var top: CGFloat = 0

    func finishLine() {
      let height = line.map(\.height).max() ?? 0
      var x: CGFloat = 0
      for size in line {
        frames.append(
          CGRect(origin: CGPoint(x: x, y: top + (height - size.height) / 2), size: size))
        x += size.width + spacing
      }
      top += height + spacing
      line = []
    }

    for size in sizes {
      let needed = line.isEmpty ? size.width : lineWidth + spacing + size.width
      if needed > width, !line.isEmpty {
        finishLine()
        lineWidth = size.width
      } else {
        lineWidth = needed
      }
      line.append(size)
    }
    if !line.isEmpty {
      finishLine()
    }
    return frames
  }

  /// The room the frames take: the widest line and the bottom of the last.
  public static func size(of frames: [CGRect]) -> CGSize {
    CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
  }
}
