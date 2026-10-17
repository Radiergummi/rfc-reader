import SwiftUI

extension DynamicTypeSize {
  /// `lines` as a line limit, or none at an accessibility size, where a card's title
  /// cut at two lines shows a word or two of it (#760).
  func lines(_ lines: Int) -> Int? {
    isAccessibilitySize ? nil : lines
  }
}
