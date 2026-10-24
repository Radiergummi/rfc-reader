import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Tab and Shift-Tab through the reader's links (#711): which link the keyboard's
/// focus moves to. Return follows the focused link and Space previews it
/// (`ReaderKeys`); the text view draws a ring around it.
public enum LinkFocus {
  /// The link after `focused`, or before it, in `text`; with none focused, the first
  /// link on `screen`, or the last, so that the focus starts where the reader is. A
  /// link is a whole `.link` run, one the screen's edge cuts included, and one that
  /// starts in text `hidden` folds is passed over. Nil with no link that way.
  public static func link(
    _ step: Folding.FocusStep, from focused: NSRange?, on screen: NSRange,
    in text: NSAttributedString, hidden: HiddenText
  ) -> NSRange? {
    let searched: NSRange
    switch step {
    case .next:
      let start = min(focused.map(NSMaxRange) ?? screen.location, text.length)
      searched = NSRange(location: start, length: text.length - start)
    case .previous:
      let end = min(focused?.location ?? NSMaxRange(screen), text.length)
      searched = NSRange(location: 0, length: end)
    }
    var found: NSRange?
    text.enumerateAttribute(
      .link, in: searched, options: step == .previous ? .reverse : []
    ) { value, run, stop in
      guard value != nil, !hidden.contains(run.location) else { return }
      found = run
      stop.pointee = true
    }
    // The whole run, where the range searched cut it.
    guard let found else { return nil }
    var link = found
    _ = text.attribute(
      .link, at: found.location, longestEffectiveRange: &link,
      in: NSRange(location: 0, length: text.length))
    return link
  }
}
