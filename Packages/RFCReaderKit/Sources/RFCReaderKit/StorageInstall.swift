import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension NSTextContentStorage {
  /// Replaces the whole text, keeping the backing `NSTextStorage`. The one way a
  /// document goes into the reader.
  ///
  /// Never by assigning `attributedString`. That assignment *discards* the
  /// `NSTextStorage` — measured: non-nil before, nil immediately after, and
  /// `textView.textStorage` nil with it. TextKit 2 lays out and draws from
  /// `attributedString` alone, so the document still renders perfectly and the
  /// damage is invisible: what breaks is everything AppKit still routes through the
  /// text storage. Dragging computed a correct selection and then discarded it at
  /// mouse-up, and `clickedOnLink` never fired, so the reader could be read but not
  /// selected, copied, or clicked. `StorageInstallTests` pins both halves.
  public func install(_ text: NSAttributedString) {
    performEditingTransaction {
      textStorage?.setAttributedString(text)
    }
  }
}
