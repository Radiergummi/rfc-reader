import RFCReaderKit
import SwiftUI

/// Lays its children out left to right, starting a new line wherever the next one
/// would not fit; where each lands is `WrappingRow`'s. The cache holds each child's
/// own size, which does not depend on the width, so a layout pass measures a child
/// again only when it is wider than the line.
///
/// For chips and tags: the Info pane's related documents and keywords (#25), and
/// the header's authors (#19).
struct WrappingRowLayout: Layout {
  let spacing: CGFloat

  func makeCache(subviews: Subviews) -> [CGSize] {
    subviews.map { $0.sizeThatFits(.unspecified) }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize])
    -> CGSize
  {
    WrappingRow.size(of: frames(subviews, width: proposal.width ?? .infinity, cache: cache))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]
  ) {
    for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width, cache: cache)) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        proposal: ProposedViewSize(frame.size))
    }
  }

  /// Each child at its own width, or the line's when it is wider: a chip is never
  /// wider than the column, and its name truncates instead.
  private func frames(_ subviews: Subviews, width: CGFloat, cache: [CGSize]) -> [CGRect] {
    let sizes = zip(subviews, cache).map { subview, ideal in
      ideal.width > width
        ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
    return WrappingRow.frames(for: sizes, width: width, spacing: spacing)
  }
}
