import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension RFCTextViewCoordinator {
  /// Puts the anchor's line at the top of the viewport.
  ///
  /// A jump can arrive — as a deep link, or as the reading position restored on
  /// the way in — before background completion has reached the section it names.
  /// So the jump pays for its own target: the engine settles it, laying out
  /// everything above it first, which is what makes its y the real one.
  /// `extra` characters past the anchor, as a saved reading position has it; a
  /// stale one stays inside the anchor's block (`ReadingPlace.documentOffset`).
  func scroll(to anchor: String, offset extra: Int = 0, animated: Bool) {
    // Deferred: this runs inside SwiftUI's update, where mutating state is illegal.
    defer { Task { self.onScrollHandled() } }
    guard let built,
      let offset = ReadingPlace(anchor: anchor, offset: extra).documentOffset(
        in: built.anchors, length: built.text.length)
    else { return }
    #if canImport(UIKit)
      chrome.jumped()
      reportChrome()
    #endif
    // Into folded text, the section opens and the line lands there in one layout.
    if !show(offset) {
      engine.jump(toOffset: offset)
    }
    reportVisibleAnchor()
  }

  /// Reads the reader's place from the engine, which reads it from the viewport's
  /// own fragments, and reports the section it is in.
  func reportVisibleAnchor() {
    // Everything that reports where the viewport is comes through here — scrolls,
    // jumps, restored places — which is every time the title's position can move.
    updateToolbarTitle()
    #if !canImport(UIKit)
      // The outline's and Implementer's arrows are cursor rects over the viewport's
      // headings and captions.
      if folding.mode.discloses, let textView {
        textView.window?.invalidateCursorRects(for: textView)
      }
    #endif
    guard let built, textView?.textLayoutManager != nil else { return }
    let offset = engine.userScrolled() ?? 0
    lastVisibleAnchor?.place = engine.keeper.readingPlace(in: built.anchors)
    // The abstract is the first prose in the storage and sits ahead of section
    // one, so while it is on screen the reader is, as far as every consumer of
    // this is concerned, in section one — which is what the old view reported too.
    // The box tells the two apart for the one that must not scroll there: the
    // reader's text made again, which starts at the top (#449).
    let section = sectionIndex.anchor(at: offset)
    lastVisibleAnchor?.isAheadOfSections = section == nil
    guard let anchor = section ?? sectionIndex.entries.first?.anchor,
      anchor != lastReportedAnchor
    else { return }
    lastReportedAnchor = anchor
    lastVisibleAnchor?.anchor = anchor
    // Deferred for the same reason as `onScrollHandled`: installing a document
    // reports from inside SwiftUI's update, where mutating state is illegal.
    Task { self.onVisibleAnchorChange(anchor) }
  }

  /// Reports where the reader is and where the title is, as if neither had been
  /// reported: for a reader back on top of the stack on iOS, whose reports the
  /// readers pushed over it replaced (#263).
  func reportAgain() {
    lastToolbarTitle = nil
    lastReportedAnchor = nil
    reportVisibleAnchor()
  }

  func updateToolbarTitle() {
    guard let textView, let header = headerHost?.view, let bottom = heading?.bottom else {
      return
    }
    let edge = textView.unobscuredTop
    let state = ToolbarTitleState(
      reveal: ToolbarTitleReveal.progress(
        headingBottom: header.frame.minY + bottom,
        visibleTop: edge,
        distance: headingLineHeight
      ),
      runningHeading: runningHeading(
        atEdge: edge - textView.containerTop, in: textView.textLayoutManager)
    )
    // Steady for almost all of a document; only a change is news.
    guard state != lastToolbarTitle else { return }
    lastToolbarTitle = state
    onToolbarTitle(state, self)
  }

  /// The section the toolbar's subtitle names, from the paragraph under the
  /// toolbar's edge — `edge` is in container coordinates.
  private func runningHeading(atEdge edge: CGFloat, in layout: NSTextLayoutManager?)
    -> RunningHeading.State
  {
    // Above the container is the header, which belongs to no section.
    guard edge >= 0, let layout,
      let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: edge))
    else { return .steady(nil) }
    let frame = fragment.layoutFragmentFrame
    return RunningHeading.state(
      in: sectionIndex,
      topFragmentStart: layout.offset(of: fragment.rangeInElement.location),
      crossing: RunningHeading.crossing(
        edge: edge,
        fragmentTop: frame.minY,
        fragmentHeight: frame.height,
        lastLine: fragment.textLineFragments.last?.typographicBounds
      )
    )
  }

  /// The height of one line of the header's heading, which is set in the large
  /// title style (`DocumentHeaderView`): the distance the reveal runs over.
  private var headingLineHeight: CGFloat {
    #if canImport(UIKit)
      // Per tick, against the view's traits: Dynamic Type changes the style's size
      // while the app runs. UIKit caches the font for a trait collection.
      let font = UIFont.preferredFont(
        forTextStyle: .largeTitle, compatibleWith: textView?.traitCollection)
    #else
      let font = Self.largeTitle
    #endif
    return ceil(font.ascender - font.descender + font.leading)
  }

  #if !canImport(UIKit)
    /// Once, not per scroll tick: macOS text styles do not change size at run time.
    private static let largeTitle = NSFont.preferredFont(forTextStyle: .largeTitle)
  #endif
}
