#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension NSTextLayoutManager {
  /// Keeps every layout fragment once it is laid out, however many the document
  /// has. The reader lays its documents out whole, and calls this before it does.
  ///
  /// `NSTextLayoutManager` keeps at most 2,000 fragments (its
  /// `maximumNumberOfCachedTextLayoutFragments`, which no header declares), on both
  /// platforms. Past that, moving the viewport far throws away the layout on one
  /// side of it, and `UITextView` lays out what it shows there again from
  /// estimates. A phone's column gives RFC 9000 2,523 fragments and RFC 9110 4,074.
  /// Measured on Mac Catalyst's `UITextView`, with this left at 2,000: 10 of 15
  /// jumps in RFC 9000 landed somewhere else, the end of the document among them
  /// landing on its abstract, and 200 drags of the scroll indicator saw 200
  /// different content heights. With every fragment kept, every jump landed and the
  /// content height stayed at one value. `FragmentCacheTests` pins the trap and the
  /// fix.
  ///
  /// Through key-value coding, and only where the property answers, so a system
  /// that drops it leaves the default rather than raising.
  public func keepEveryLaidOutFragment() {
    let key = "maximumNumberOfCachedTextLayoutFragments"
    guard responds(to: NSSelectorFromString("setMaximumNumberOfCachedTextLayoutFragments:"))
    else { return }
    setValue(Int.max, forKey: key)
  }
}
