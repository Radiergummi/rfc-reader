import RFCReaderKit

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
  ///
  /// The top of the part the bars leave uncovered. On iOS the reader runs under
  /// the navigation bar, whose height is the top content inset
  /// (`ReaderTextView.safeAreaInsetsDidChange`); on macOS the window's content runs
  /// under the toolbar and the tab bar, so the clip view's own top edge is behind
  /// them. Measured from there, a jump put its heading under the
  /// toolbar and tracking named the section scrolled past as the one being read.
  /// `scroll(toY:)` and `viewportHeight` are measured the same way, so a jump
  /// lands where tracking then reads.
  var viewportTop: CGFloat {
    unobscuredTop - containerTop
  }

  /// The top of the part of the viewport nothing covers — the bar's bottom edge —
  /// in the text view's own coordinates. On iOS that is the top inset's edge, the
  /// navigation bar's height below the offset. On macOS, not `visibleRect.minY`
  /// moved by an inset: the text view's `visibleRect` stops at its own top, so at
  /// the top of a document it reads 0 where the clip view is showing the toolbar's
  /// height above it.
  var unobscuredTop: CGFloat {
    #if canImport(UIKit)
      return contentOffset.y + contentInset.top
    #else
      guard let clip = enclosingScrollView?.contentView else { return visibleRect.minY }
      return convert(clip.bounds.origin, from: clip).y + clip.contentInsets.top
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

  /// The padding below the last line, and on iOS the room under the home indicator
  /// the reader scrolls it clear of (`ReaderTextView.safeAreaInsetsDidChange`):
  /// together, what UIKit lets the view scroll past the end of the text.
  var containerBottom: CGFloat {
    #if canImport(UIKit)
      return textContainerInset.bottom + contentInset.bottom
    #else
      // AppKit's inset is symmetric, so the top inset is also the bottom padding.
      return textContainerInset.height
    #endif
  }

  var viewportHeight: CGFloat {
    #if canImport(UIKit)
      return bounds.height - contentInset.top
    #else
      guard let clip = enclosingScrollView?.contentView else { return bounds.height }
      return clip.bounds.height - clip.contentInsets.top
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

  /// Never above the top; past the end only while `knowsEnd` is false, the end
  /// being an estimate (`ReaderLayout.scrollOrigin`).
  func scroll(toY y: CGFloat, knowsEnd: Bool = false) {
    #if canImport(UIKit)
      // `y` is where the uncovered viewport starts; see `viewportTop`.
      let offset = ReaderLayout.scrollOrigin(
        y - contentInset.top, contentHeight: knowsEnd ? contentSize.height : nil,
        viewportHeight: bounds.height, topInset: contentInset.top,
        bottomInset: contentInset.bottom)
      setContentOffset(CGPoint(x: 0, y: offset), animated: false)
    #else
      guard let scroll = enclosingScrollView else { return }
      let clip = scroll.contentView
      // `y` is where the uncovered viewport starts; see `viewportTop`.
      let target = NSPoint(
        x: 0,
        y: ReaderLayout.scrollOrigin(
          y - clip.contentInsets.top, contentHeight: knowsEnd ? frame.height : nil,
          viewportHeight: clip.bounds.height, topInset: clip.contentInsets.top,
          bottomInset: clip.contentInsets.bottom))
      clip.scroll(to: target)
      scroll.reflectScrolledClipView(clip)
    #endif
  }
}
