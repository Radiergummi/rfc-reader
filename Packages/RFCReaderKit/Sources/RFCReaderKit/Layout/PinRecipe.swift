import CoreGraphics
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What the pin recipe needs of a scrolling text view: where the viewport's top is
/// and a way to move it, both in text-container coordinates, and a way to lay out
/// what the viewport now covers. The App's `ReaderLayoutEngine` is one, over
/// `NSTextView` and `UITextView`; the tests have their own.
@MainActor
public protocol PinSurface: AnyObject {
  var containerTop: CGFloat { get }
  func scroll(toContainerY target: CGFloat)
  func layOutViewport()
}

/// The one way the reader's line is put at the top of the viewport, measured in
/// the probe for the layout engine (see the spec): 40 of 40 random jumps exact, and
/// the line held in 276 of 276 resize steps, on RFC 9000 and RFC 5661.
///
/// Lay out only the anchor's paragraph, scroll so its line meets the top, lay out
/// the viewport, and settle again if the estimates above it moved the paragraph.
/// Not `relocateViewport(to:)`, which from a prior relocation put its target at
/// y = 0 or collapsed the viewport.
public enum PinRecipe {
  public static let maximumPasses = 4
  static let settleTolerance: CGFloat = 0.5

  /// Puts `anchor` at the top of `surface`. Answers how many scrolls it took.
  @MainActor
  @discardableResult
  public static func pin(
    _ anchor: ReaderAnchor, in layout: NSTextLayoutManager, on surface: some PinSurface
  ) -> Int {
    guard let location = layout.location(atOffset: anchor.characterOffset),
      let paragraph = layout.textLayoutFragment(for: location)
    else { return 0 }
    layout.ensureLayout(for: paragraph.rangeInElement)
    var passes = 0
    while passes < maximumPasses, let fragment = layout.textLayoutFragment(for: location) {
      // After TextKit drops its layout, the fragment can come back unlaid, its frame
      // zero: scrolling to it sent the reader to the top of the document.
      layout.ensureLayout(for: fragment.rangeInElement)
      guard fragment.layoutFragmentFrame.height > 0 else { break }
      let start = layout.offset(of: fragment.rangeInElement.location)
      let wanted =
        fragment.layoutFragmentFrame.minY
        + LinePin.fragmentY(of: anchor, in: fragment.textLineFragments, fragmentStart: start)
      if abs(surface.containerTop - wanted) < settleTolerance { break }
      surface.scroll(toContainerY: wanted)
      surface.layOutViewport()
      passes += 1
    }
    return passes
  }

  /// Lays out the document from its start through `anchor`'s paragraph, then pins
  /// it. The line is then where the layout of the whole document puts it, so laying
  /// out what follows never moves it. A pin alone leaves it where TextKit estimated
  /// it, and the viewport in coordinates that the layout from the start later
  /// replaces: on an iPhone, that moved the text under the reader 73,000 characters
  /// of RFC 5661. Laying out to the middle of that document costs about 0.35 s there.
  @MainActor
  @discardableResult
  public static func settle(
    _ anchor: ReaderAnchor, in layout: NSTextLayoutManager, on surface: some PinSurface
  ) -> Int {
    guard let location = layout.location(atOffset: anchor.characterOffset),
      let paragraph = layout.textLayoutFragment(for: location),
      let above = NSTextRange(
        location: layout.documentRange.location, end: paragraph.rangeInElement.endLocation)
    else { return 0 }
    layout.ensureLayout(for: above)
    return pin(anchor, in: layout, on: surface)
  }

  /// The anchor at the viewport's top, `top` in container coordinates, read from the
  /// fragments laid out from `start` on: the viewport's own, never a point lookup,
  /// which can answer with a stale fragment. Nil when nothing is laid out there, and
  /// when the fragments from `start` begin below the top: after TextKit drops its
  /// layout, the viewport range can start far past it for a pass.
  @MainActor
  public static func anchor(
    atContainerTop top: CGFloat, in layout: NSTextLayoutManager, from start: any NSTextLocation
  ) -> (anchor: ReaderAnchor, line: NSRange)? {
    var found: (anchor: ReaderAnchor, line: NSRange)?
    layout.enumerateTextLayoutFragments(from: start, options: []) { fragment in
      let frame = fragment.layoutFragmentFrame
      guard frame.maxY > top else { return true }
      guard frame.minY <= top else { return false }
      found = LinePin.anchor(
        atFragmentY: max(0, top - frame.minY), in: fragment.textLineFragments,
        fragmentStart: layout.offset(of: fragment.rangeInElement.location))
      return false
    }
    return found
  }
}
