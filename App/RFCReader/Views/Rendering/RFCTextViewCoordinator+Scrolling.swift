import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension RFCTextViewCoordinator: ReaderTextDriving {
  /// Reports to `controller` from now on, and is asked through it.
  func drive(_ controller: ReaderController) {
    guard controller !== self.controller else { return }
    self.controller = controller
    controller.driver = self
  }

  /// Stops reporting to the controller, which no longer asks this text view: it is
  /// going away. What it placed goes with it, so the Annotations tab says why nothing
  /// is placed while the original text is shown in its place (#522).
  func releaseController() {
    guard controller?.driver === self else { return }
    controller?.driver = nil
    controller?.reportHighlights(nil)
  }

  var isInstalled: Bool { built != nil && textView != nil }

  func headingDidMove() {
    updateToolbarTitle()
  }

  /// Puts the anchor's line at the top of the viewport.
  ///
  /// A jump can arrive — as a deep link, or as the reading position restored on
  /// the way in — before background completion has reached the section it names.
  /// So the jump pays for its own target: the engine settles it, laying out
  /// everything above it first, which is what makes its y the real one.
  /// `extra` characters past the anchor, as a saved reading position has it; a
  /// stale one stays inside the anchor's block (`ReadingPlace.documentOffset`).
  func scroll(to anchor: String, offset extra: Int) {
    guard let built,
      let offset = ReadingPlace(anchor: anchor, offset: extra).documentOffset(
        in: built.anchors, length: built.text.length)
    else { return }
    #if canImport(UIKit)
      bars.jumped()
    #endif
    // Into folded text, the section opens and the line lands there in one layout.
    if !show(offset) {
      engine.jump(toOffset: offset)
    }
    reportVisibleAnchor()
  }

  /// Reads the reader's place from the engine, which reads it from the viewport's
  /// own fragments, and reports the section it is in. `placed` when the engine has
  /// just put the line where it is, so that its place is the line and there is
  /// nothing to read: following the other reader of a side-by-side reading (#187),
  /// where reading it walks the fragments from where the viewport was, on every
  /// tick of the other reader's scroll.
  func reportVisibleAnchor(placed: Bool = false) {
    // Everything that reports where the viewport is comes through here — scrolls,
    // jumps, restored places — which is every time the title's position can move.
    updateToolbarTitle()
    #if !canImport(UIKit)
      // The arrows are cursor rects over the viewport's copy buttons, and its headings
      // and captions in the outline and Implementer.
      if folding.mode.discloses || hasCopyButtons, let textView {
        textView.window?.invalidateCursorRects(for: textView)
      }
    #endif
    guard let built, textView?.textLayoutManager != nil else { return }
    let line = placed ? engine.placeOffset : engine.userScrolled()
    // The other reader of a side-by-side reading follows, if this one leads (#187).
    if let documentID { coupling?.moved(documentID, to: line) }
    controller?.reportPlace(
      engine.keeper.readingPlace(in: built.anchors), line: line ?? 0, in: sectionIndex)
  }

  /// Reports where the reader is, and where the title is as if it had not been
  /// reported: for a reader back on top of the stack on iOS, whose title the readers
  /// pushed over it replaced (#263). Its section `DocumentView` writes again itself,
  /// from `ReaderController.section`.
  func reportAgain() {
    lastToolbarTitle = nil
    reportVisibleAnchor()
  }

  /// What the toolbar's title shows; see `ToolbarTitleState`. Told on every scroll
  /// tick that changes it, at once: the title is coupled to the scroll, and a hop
  /// would leave it a frame behind the text. Told with this coordinator, which owns
  /// what it reports until `releaseDocument()` withdraws it (#281): the reader is
  /// made per document, and the last one's teardown can come after the next one's
  /// report.
  func updateToolbarTitle() {
    guard let textView, let header = headerHost?.view, let bottom = controller?.headingBottom
    else { return }
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
    controller?.reportTitle(state, from: self)
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
