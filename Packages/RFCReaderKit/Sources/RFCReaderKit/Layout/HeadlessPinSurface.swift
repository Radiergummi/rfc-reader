import CoreGraphics
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A scroll view without a view: a top, and a viewport of a window's height that
/// lays out the fragments it covers, as a text view's viewport layout controller
/// does. What the tests and the layout benchmarks pin on, in place of a text view.
@MainActor
public final class HeadlessPinSurface: PinSurface {
  public let layout: NSTextLayoutManager
  public let viewportHeight: CGFloat
  public var containerTop: CGFloat = 0
  /// Set through a live resize, as AppKit sets a text view's; see `layOutViewport()`.
  public var isInLiveResize = false

  public init(layout: NSTextLayoutManager, viewportHeight: CGFloat = 900) {
    self.layout = layout
    self.viewportHeight = viewportHeight
  }

  public func scroll(toContainerY target: CGFloat) {
    containerTop = max(0, target)
  }

  /// Lays out the fragments the viewport covers. During a live resize, what stands in
  /// for AppKit's own display pass after a step.
  public func forceViewportLayout() {
    let top = containerTop
    guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
    layout.enumerateTextLayoutFragments(
      from: first.rangeInElement.location, options: [.ensuresLayout]
    ) { fragment in
      fragment.layoutFragmentFrame.minY < top + self.viewportHeight
    }
  }
}
