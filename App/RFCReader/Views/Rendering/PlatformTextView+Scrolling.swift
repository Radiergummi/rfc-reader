#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The things the reader asks of a scrolling text view, spelled once per
/// platform here so that the parts with real reasoning in them — where an anchor
/// lands, and why an unknown document end must not clamp to the top — are written
/// once, not twice inside interleaved `#if` blocks.
///
/// `UITextView` is a scroll view; `NSTextView` is a document inside one. That is the
/// whole of the difference, and it stops here.
extension PlatformTextView {
  /// The top of the viewport, in text-container coordinates.
  var viewportTop: CGFloat {
    #if canImport(UIKit)
      return contentOffset.y - textContainerInset.top
    #else
      return visibleRect.minY - textContainerOrigin.y
    #endif
  }

  /// Where the text container's origin sits inside the scrolled content.
  var containerTop: CGFloat {
    #if canImport(UIKit)
      return textContainerInset.top
    #else
      return textContainerOrigin.y
    #endif
  }

  /// The padding below the last line.
  var containerBottom: CGFloat {
    #if canImport(UIKit)
      return textContainerInset.bottom
    #else
      // AppKit's inset is symmetric, so the top inset is also the bottom padding.
      return textContainerInset.height
    #endif
  }

  var viewportHeight: CGFloat {
    #if canImport(UIKit)
      return bounds.height
    #else
      return enclosingScrollView?.contentView.bounds.height ?? bounds.height
    #endif
  }

  /// Brings the view's own frames up to date. The text is laid out already, so
  /// this only syncs geometry — but an offset set against a content size the
  /// platform has not published yet is clamped to it.
  func syncLayout() {
    #if canImport(UIKit)
      layoutIfNeeded()
    #else
      enclosingScrollView?.layoutSubtreeIfNeeded()
    #endif
  }

  func scroll(toY y: CGFloat) {
    #if canImport(UIKit)
      setContentOffset(CGPoint(x: 0, y: y), animated: false)
    #else
      guard let scroll = enclosingScrollView else { return }
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
    #endif
  }
}
