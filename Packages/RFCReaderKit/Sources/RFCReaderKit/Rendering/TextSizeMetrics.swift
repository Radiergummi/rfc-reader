import CoreGraphics
import SwiftUI

/// The system's text style sizes, in points, at each text size: Apple's Dynamic
/// Type tables for `.body`, `.title2` and `.title3` on iOS. (`.headline` is the
/// body's size throughout.)
///
/// Tabled rather than asked of `UIFontMetrics`, which exists only under UIKit: the
/// Mac has no Dynamic Type and always reports `.large`, and this package's tests
/// run there. The numbers are what `UIFontMetrics` scales to.
enum TextSizeMetrics {
  static func body(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53])
  }

  static func title2(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56])
  }

  static func title3(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55])
  }

  /// `table` has one entry per size, in `DynamicTypeSize.allCases` order: from
  /// `.xSmall` to `.accessibility5`. A size added later reads as `.large`.
  private static func points(_ size: DynamicTypeSize, _ table: [CGFloat]) -> CGFloat {
    guard let index = DynamicTypeSize.allCases.firstIndex(of: size) else {
      return points(.large, table)
    }
    return table[index]
  }
}
