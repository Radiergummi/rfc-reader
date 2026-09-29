import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit

  typealias PlatformTextView = UITextView
  typealias PlatformHostingController = UIHostingController
#else
  import AppKit

  typealias PlatformTextView = NSTextView
  typealias PlatformHostingController = NSHostingController
#endif

/// The last anchor section tracking computed, outside SwiftUI's observation.
///
/// Reporting to `DocumentView` goes through a `Task`, because it can fire from
/// inside a view update where mutating state is illegal — and a `Task` has no
/// ordering guarantee against `onDisappear`, so a scroll immediately followed by
/// navigating away would persist the section before last. `saveReadingPosition`
/// reads this instead: it is written the moment the anchor is computed.
final class VisibleAnchorBox {
  var anchor: String?
}

/// Where the header's heading ends, in the hosted header's own coordinates, as
/// `DocumentHeaderView` measured it. A box for the same reason as
/// `VisibleAnchorBox`: the header is hosted outside SwiftUI's diffing and built
/// once, so it writes into something both sides already hold rather than calling
/// through to a coordinator it was built before.
final class HeadingBox {
  var bottom: CGFloat? {
    didSet { if bottom != oldValue { didChange() } }
  }

  /// The reader can report its viewport before the header has measured its
  /// heading — a text view made afresh on the way back from the original text
  /// does — and nothing scrolls afterwards to report it again.
  var didChange: () -> Void = {}
}

/// Everything the two representables share. Both platforms drive the same anchor
/// jumping, viewport tracking and link handling; only the scroll plumbing differs,
/// and that difference lives here rather than in the representables so the pair
/// stays reviewable side by side.
final class RFCTextViewCoordinator: NSObject {
  /// The text view this coordinator drives. Weak: SwiftUI owns both, and the view
  /// outlives no part of this. AppKit's hover preview needs a tracking area the
  /// moment the view exists, hence the `didSet`; UIKit needs no such setup.
  weak var textView: PlatformTextView? {
    didSet {
      #if !canImport(UIKit)
        setUpHover()
      #endif
      setUpAccessibilityRotors()
    }
  }

  /// Retained deliberately: `UIHostingController().view` does not keep its
  /// controller alive, and a released controller takes trait propagation — and so
  /// Dynamic Type — with it.
  var headerHost: PlatformHostingController<AnyView>?

  /// What the hosted header currently displays; see `ReaderInputs.apply`.
  var headerIdentity: DocumentHeaderView.Identity?

  /// Retained for the same reason as `headerHost`: the iOS long-press preview's
  /// hosting controller must outlive the `UITargetedPreview` that wraps its view.
  var referencePreviewHost: PlatformHostingController<ReferencePreview>?

  /// Injected explicitly: a hosting controller the coordinator builds — the
  /// reference preview, on both platforms — sits outside SwiftUI's environment
  /// chain, so `@Environment(LibraryModel.self)` inside it would come back empty
  /// rather than crash. `ReferencePreview` takes the library directly instead.
  var library: LibraryModel?

  var onVisibleAnchorChange: (String) -> Void = { _ in }
  var onScrollHandled: () -> Void = {}
  var onLink: (URL, LinkActivation) -> Bool = { _, _ in false }
  /// See `RFCTextView.bibliography`.
  var bibliography: [ReferenceGroup] = []
  /// The document on screen; see `RFCTextView.documentID`.
  var documentID: DocumentID?
  /// See `RFCTextView.commitsOnClick`.
  var commitsOnClick: (() -> Void)? {
    didSet {
      #if !canImport(UIKit)
        hover.isPreviewReader = commitsOnClick != nil
      #endif
    }
  }
  /// What the toolbar's title shows; see `ToolbarTitleState`. Called
  /// synchronously, on every scroll tick that changes it: the title is coupled to
  /// the scroll, and a hop through a `Task` would leave it a frame behind the text.
  /// That is safe where `onVisibleAnchorChange` is not because it touches no
  /// SwiftUI state.
  var onToolbarTitle: (ToolbarTitleState) -> Void = { _ in }
  var heading: HeadingBox?
  private var lastToolbarTitle: ToolbarTitleState?

  /// Where section tracking last put the reader, written the moment it is computed.
  /// `visibleAnchor` in `DocumentView` is the observable copy and lags this by a
  /// main-actor hop, which `onDisappear` cannot afford to wait for.
  var lastVisibleAnchor: VisibleAnchorBox?

  private(set) var built: BuiltDocument?
  /// The anchors tracking may report. The full index covers *every* anchor —
  /// paragraphs, figures, tables, reference rows — because `scroll(to:)` has to
  /// reach all of them, but every consumer of the reader's visible anchor resolves
  /// it with `RFCDocument.section(anchor:)`, so reporting a paragraph anchor would
  /// silently break all of them. The builder marks which entries are sections; this
  /// is just that subset.
  private var sectionIndex = AnchorIndex([])
  private var lastReportedAnchor: String?
  /// The line at the top of the viewport, as a position that survives a rebuild.
  /// Tracked on every scroll and carried into the next `install`, which puts the
  /// same line back at the top of the new storage. The tracker decides when the
  /// top of the viewport is the reader's place at all; see `ReadingPlaceTracker`.
  private var tracker = ReadingPlaceTracker()
  private var laidOutColumn: CGFloat?
  /// Tracked separately from the column, because above the breakpoint the two move
  /// independently: the column pins at the ideal measure and the gutter takes the
  /// whole resize. The inset is the gutter, so the gutter is what invalidates it.
  private var laidOutGutter: CGFloat?
  private var laidOutHeaderHeight: CGFloat?

  /// The bottom of the last laid-out fragment, in container coordinates. The text
  /// view's own `contentSize`/`frame` are republished by *its* layout pass, not by
  /// `ensureLayout`, so they can still read near zero in the same update that
  /// installed the document — and clamping a deep jump against that would land at
  /// the top and overwrite the reading position with section one.
  private var laidOutEnd: CGFloat?
  /// How far into the document layout has reached, in characters. Everything
  /// before it has real fragment frames; everything after it has none yet.
  private var laidOutThrough = 0
  /// The slices after the first one, running between frames until the document is
  /// laid out. Canceled by the next `install` — and by a change of column, which
  /// invalidates every frame it has computed.
  private var layoutTask: Task<Void, Never>?
  /// Characters per slice: about 8 ms of layout on this machine, so a slice fits
  /// inside a frame.
  private static let layoutSlice = 20_000

  // MARK: - Accessibility

  /// The headings, links and diagrams rotors search — cached by
  /// `deriveAccessibilityItems()` in `RFCTextViewCoordinator+Accessibility.swift`.
  var accessibilityHeadings: [AccessibilityRotorItem] = []
  var accessibilityLinks: [AccessibilityRotorItem] = []
  var accessibilityDiagrams: [AccessibilityRotorItem] = []

  #if !canImport(UIKit)
    /// The hover and force-click previews; see `ReferenceHover` for their rules.
    let hover = ReferenceHoverController()
    /// Short, so following a preview to another document feels immediate: the old
    /// reader and the new one cross-fade rather than cut.
    static let documentCrossFade = Animation.easeInOut(duration: 0.1)
  #endif

  // MARK: - Storage

  /// Swaps in a document and starts laying it out.
  ///
  /// The whole document does get laid out — viewport layout would be cheaper here
  /// and wrong afterwards: `usageBoundsForTextContainer` keeps moving as the
  /// viewport does, which the scroller shows as jitter, and estimated fragment
  /// heights run well above the laid-out ones, so an anchor's y is a guess. The
  /// document is immutable once built, so laying all of it out buys a stable
  /// content size, an exact anchor → y mapping and correct hit-testing for the
  /// rest of its life.
  ///
  /// What is *not* done here is all of it at once. One `ensureLayout` over the
  /// document range measured 547 ms on RFC 5661 — the main thread, and therefore
  /// the whole interface, frozen for that long every time a document opens. It is
  /// spread over run-loop turns instead; see `beginLayout()`.
  func install(_ built: BuiltDocument) {
    guard let textView,
      let layout = textView.textLayoutManager,
      let storage = layout.textContentManager as? NSTextContentStorage
    else { return }
    #if !canImport(UIKit)
      // A preview timing or shown belongs to the document being replaced, and its
      // range means nothing in the new one.
      hover.send(.reset)
    #endif
    // What section tracking last reported, for a place whose anchor the new
    // build does not have: its section's heading is the old behavior, and still
    // far better than the top of the document. Only a restyle has one: the first
    // install of a document leaves the choice between a deep link and the saved
    // reading position to `DocumentView`, and a coordinator never outlives its
    // document, so it has no place to carry either.
    let fallback = self.built == nil ? nil : lastReportedAnchor
    self.built = built
    // The column `layOut` sized the container to, which is the column the
    // storage is laid out at. Nil if no layout has run yet; the first one sets it.
    tracker.installed(atColumn: laidOutColumn)
    lastReportedAnchor = nil
    sectionIndex = built.anchors.sections
    deriveAccessibilityItems()
    // Through `install`, never by assigning `storage.attributedString`, which
    // discards the text storage that selection and link clicks go through while
    // rendering perfectly. `NSTextContentStorage.install(_:)` has the story, and
    // `StorageInstallTests` pins it.
    storage.install(built.text)
    beginLayout()
    if laidOutColumn != nil { restorePlace(fallback: fallback) }
  }

  /// Puts the place back at the top of the viewport and resumes tracking from
  /// there. Tracking does not run until after the scroll: the restore is what
  /// puts the place on screen, so what it scrolls past is not the reader's.
  private func restorePlace(fallback: String? = nil) {
    guard let textView, let built else { return }
    switch tracker.place {
    case .top:
      textView.syncLayout()
      textView.scroll(toY: 0)
      reportVisibleAnchor()
      tracker.restored(top: textView.viewportTop)
    case .line(let place):
      if let offset = place.documentOffset(in: built.anchors, length: built.text.length) {
        scroll(toOffset: offset)
        tracker.restored(top: textView.viewportTop)
        return
      }
      fallthrough
    case nil:
      // Nothing to hold on to, so tracking starts from wherever this lands.
      tracker.restored(top: nil)
      if let offset = fallback.flatMap(built.anchors.offset(of:)) {
        scroll(toOffset: offset)
      } else {
        reportVisibleAnchor()
      }
    }
  }

  /// Lays out the first slice now and the rest between frames.
  ///
  /// The first slice is far more than a viewport, so the document is complete
  /// where it can be seen before it is drawn; everything below it lands in
  /// `layoutSlice`-sized pieces, each about 8 ms, with a turn of the run loop
  /// between them. The interface stays live throughout — the alternative, one
  /// pass over the document range, is half a second of frozen window on the
  /// largest RFCs.
  ///
  /// Until the last slice lands the document end is unknown, which is exactly the
  /// state `scrollContainerTopTo` already treats as "do not clamp".
  private func beginLayout() {
    layoutTask?.cancel()
    laidOutEnd = nil
    laidOutThrough = 0
    ensureLayout(through: Self.layoutSlice)
    layoutTask = Task(name: "Lay out document") { [weak self] in
      while let self, self.laidOutEnd == nil {
        // A sleep rather than `Task.yield()`: yielding hands the main actor
        // its next queued job, which is this loop again, and the run loop
        // never gets between two slices. A timer does.
        try? await Task.sleep(for: .milliseconds(1))
        guard !Task.isCancelled else { return }
        let before = self.laidOutThrough
        self.ensureLayout(through: before + Self.layoutSlice)
        // A slice that laid nothing out means there is nothing left to lay
        // out — an empty document, or a text view that has gone away. Either
        // way the end stays unknown, which is the safe state, and looping on
        // it would spin.
        guard self.laidOutThrough > before else { return }
      }
    }
  }

  /// Lays out from the start of the document through `offset`, and records the
  /// document's end once the last character is in.
  ///
  /// Always from the start: TextKit keeps what it has already laid out, so this is
  /// the cheap incremental call it looks like, and asking for a range that begins
  /// mid-document would leave everything before it un-laid-out and every y after
  /// it wrong.
  private func ensureLayout(through offset: Int) {
    guard let layout = textView?.textLayoutManager, let built else { return }
    let end = min(offset, built.text.length)
    guard end > laidOutThrough, let range = layout.textRange(for: NSRange(location: 0, length: end))
    else { return }
    layout.ensureLayout(for: range)
    laidOutThrough = end
    guard end == built.text.length else { return }
    // Exact, because the whole document is now laid out. The usual caveat about
    // this value — that it keeps moving as the viewport does, which is why the
    // reader lays all of it out — applies to viewport layout, not here.
    laidOutEnd = layout.usageBoundsForTextContainer.maxY
  }

  // MARK: - Geometry

  /// Centers the column and hangs the header in the top inset.
  ///
  /// This runs on every update pass — and an update pass happens on every section
  /// crossing, because `visibleAnchor` is `@State` — so nothing is written unless
  /// the gutter, the column or the header's height moved. A relayout costs more
  /// still, and only the column can force one: under the recommended measure, a
  /// window wider than it moves the gutters, not the text. Full width has no such
  /// slack — every change of width is a change of column, and re-wraps.
  ///
  /// `measure` is the live preference, which runs ahead of the storage for as long
  /// as a flip takes to rebuild, exactly as the width does during a resize: the
  /// text re-wraps at the new column at once and the rebuild re-measures artwork
  /// and tables for it when it lands.
  func layOut(width: CGFloat, measure: MeasurePreference) {
    guard let textView, width > 0 else { return }
    let gutter = ReaderLayout.gutter(forWidth: width, measure: measure)
    let column = ReaderLayout.column(forWidth: width, measure: measure)
    // Measured every pass, deliberately: the height depends on the width, on the
    // content size category, and on metadata that can arrive after the first
    // layout, and a cache keyed on any one of those goes stale as a header
    // overlapping the first paragraph. Only the writes below are conditional.
    let offered = CGFloat.greatestFiniteMagnitude
    let measured =
      headerHost?.sizeThatFits(in: CGSize(width: column, height: offered)).height ?? 0
    let headerHeight = ReaderLayout.headerHeight(measured: measured, offered: offered)
    guard column != laidOutColumn || gutter != laidOutGutter || headerHeight != laidOutHeaderHeight
    else { return }
    let columnChanged = column != laidOutColumn
    laidOutColumn = column
    laidOutGutter = gutter
    laidOutHeaderHeight = headerHeight

    #if canImport(UIKit)
      textView.textContainerInset = UIEdgeInsets(
        top: headerHeight, left: gutter, bottom: ReaderLayout.margin, right: gutter)
    #else
      // AppKit's inset is symmetric, so the header's height is echoed as padding
      // under the last line. NSTextView has no asymmetric equivalent.
      textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
      textView.textContainerInset = NSSize(width: gutter, height: headerHeight)
    #endif
    headerHost?.view.frame = CGRect(x: gutter, y: 0, width: column, height: headerHeight)

    // The container is the column, set here and nowhere else. Tracking the text
    // view's width instead re-wrapped the storage on *every* resize: the frame
    // and the inset cannot change in one step, so the container passed through a
    // width that was neither the old column nor the new one, and TextKit threw
    // away the whole document's layout for it — measured on RFC 9000, a resize
    // that only moved the gutters left the reader 39,000 characters further on,
    // with no rebuild coming to put it back.
    //
    // Usually no relayout here: `DocumentView` derives the column from the same
    // width and rebuilds, which lands in `install()`. Until it does, the laid-out
    // end belongs to the previous column, and an unknown end is the safe state
    // (`scrollContainerTopTo` then does not clamp); nothing is laid out at the new
    // column yet either, so a jump in the meantime lays out from the start again
    // rather than trusting frames that are gone.
    //
    // The exception is a storage that was laid out at this very column — one
    // installed before the first layout, or a column that came back inside the
    // rebuild's debounce. Its layout was thrown away all the same, so it is laid
    // out again now and the place restored, rather than left on estimates until
    // a rebuild that changes nothing. That a storage installed before the first
    // layout belongs to this column rests on this view and `DocumentView`
    // deriving the column from the same width and the same measure preference:
    // `DocumentView` is the one reader of `readerMeasure`, and hands it down here.
    if columnChanged {
      #if canImport(UIKit)
        textView.textContainer.size = CGSize(width: column, height: .greatestFiniteMagnitude)
      #else
        textView.textContainer?.size = NSSize(width: column, height: .greatestFiniteMagnitude)
      #endif
      if tracker.columnChanged(to: column) {
        beginLayout()
        restorePlace()
      } else {
        layoutTask?.cancel()
        laidOutEnd = nil
        laidOutThrough = 0
      }
    }
  }

  // MARK: - Scrolling

  /// Puts the anchor's fragment at the top of the viewport.
  ///
  /// A jump can arrive — as a deep link, or as the reading position restored on
  /// the way in — before the slices have reached the section it names, and a
  /// fragment that has not been laid out has no frame to scroll to. So the jump
  /// pays for its own target: everything above it is laid out first, which is what
  /// makes its y the real one.
  func scroll(to anchor: String, animated: Bool) {
    // Deferred: this runs inside SwiftUI's update, where mutating state is illegal.
    defer { Task { self.onScrollHandled() } }
    guard let offset = built?.anchors.offset(of: anchor) else { return }
    // Set here as well as by tracking, which does not run while a resize waits
    // for its rebuild: a jump in that window is where the rebuild must land.
    tracker.jumped(to: ReadingPlace(anchor: anchor, offset: 0))
    scroll(toOffset: offset, animated: animated)
  }

  /// Puts the line holding `offset` at the top of the viewport; see
  /// `FragmentGeometry.scrollTarget(of:in:fragmentStart:)`.
  private func scroll(toOffset offset: Int, animated: Bool = false) {
    guard let textView, let layout = textView.textLayoutManager else { return }
    ensureLayout(through: offset + Self.layoutSlice)
    guard let location = layout.location(atOffset: offset),
      let fragment = layout.textLayoutFragment(for: location)
    else { return }
    let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
    let line = FragmentGeometry.scrollTarget(
      of: offset, in: fragment.textLineFragments, fragmentStart: fragmentStart)
    scrollContainerTopTo(fragment.layoutFragmentFrame.minY + line, animated: animated)
    reportVisibleAnchor()
  }

  /// Hit-tests the top of the visible rect. Deliberately not
  /// `textViewportLayoutController.viewportRange`: that range is larger than the
  /// visible rect, so its start names a section already scrolled past.
  func reportVisibleAnchor() {
    // Everything that reports where the viewport is comes through here — scrolls,
    // jumps, restored places — which is every time the title's position can move.
    updateToolbarTitle()
    guard let textView,
      let built,
      let layout = textView.textLayoutManager
    else { return }
    let top = max(0, textView.viewportTop)
    guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
    let offset = layout.offset(of: fragment.rangeInElement.location)
    let line = FragmentGeometry.topLine(
      atViewportTop: top,
      fragmentTop: fragment.layoutFragmentFrame.minY,
      in: fragment.textLineFragments,
      fragmentStart: offset,
      fragmentEnd: layout.offset(of: fragment.rangeInElement.endLocation)
    )
    tracker.report(
      viewportTop: textView.viewportTop, line: line, in: built.anchors, length: built.text.length)
    // The abstract is the first prose in the storage and sits ahead of section
    // one, so while it is on screen the reader is, as far as every consumer of
    // this is concerned, in section one — which is what the old view reported too.
    guard let anchor = sectionIndex.anchor(at: offset) ?? sectionIndex.entries.first?.anchor,
      anchor != lastReportedAnchor
    else { return }
    lastReportedAnchor = anchor
    lastVisibleAnchor?.anchor = anchor
    // Deferred for the same reason as `onScrollHandled`: installing a document
    // reports from inside SwiftUI's update, where mutating state is illegal.
    Task { self.onVisibleAnchorChange(anchor) }
  }

  /// macOS only: iOS has no toolbar title for this to drive, so it neither
  /// measures nor reports there.
  func updateToolbarTitle() {
    #if !canImport(UIKit)
      guard let textView, let header = headerHost?.view, let bottom = heading?.bottom else {
        return
      }
      let edge = textView.unobscuredTop
      let state = ToolbarTitleState(
        reveal: ToolbarTitleReveal.progress(
          headingBottom: header.frame.minY + bottom,
          visibleTop: edge,
          distance: Self.headingLineHeight
        ),
        runningHeading: runningHeading(
          atEdge: edge - textView.containerTop, in: textView.textLayoutManager)
      )
      // Steady for almost all of a document; only a change is news.
      guard state != lastToolbarTitle else { return }
      lastToolbarTitle = state
      onToolbarTitle(state)
    #endif
  }

  #if !canImport(UIKit)
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
  #endif

  #if !canImport(UIKit)
    /// The height of one line of the header's heading, which is set in the large
    /// title style (`DocumentHeaderView`): the distance the reveal runs over. Once,
    /// not per scroll tick — macOS text styles do not change size at run time.
    private static let headingLineHeight: CGFloat = {
      let font = NSFont.preferredFont(forTextStyle: .largeTitle)
      return ceil(font.ascender - font.descender + font.leading)
    }()
  #endif

  /// Clamped against the laid-out document end rather than the text view's own
  /// published height, and **not clamped at all** if that end is unknown: an
  /// overshoot self-corrects on the next scroll, whereas clamping to the top
  /// silently rewrites the reading position.
  private func scrollContainerTopTo(_ containerY: CGFloat, animated: Bool) {
    guard let textView else { return }
    textView.syncLayout()
    let top = textView.containerTop
    var target = max(0, containerY + top)
    if let end = laidOutEnd {
      let content = top + end + textView.containerBottom
      target = min(target, max(0, content - textView.viewportHeight))
    }
    textView.scroll(toY: target, animated: animated)
  }

  // MARK: - References

  /// The cross reference at this absolute character offset, and its whole
  /// extent. Shared by the iOS long-press lookup and the macOS hover hit test
  /// below; the lookup itself is `NSAttributedString.reference(at:)`.
  private func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.reference(at: offset)
  }

  /// The card for a reference, on either platform, or nil when it would say no
  /// more than the reference already does. Another document has its title and
  /// abstract; a place in this one has only its section's heading; a bibliography
  /// entry that names no RFC has its title, authors and where it was published
  /// (#198); and a figure or a table has none of those.
  private func preview(for reference: CrossReference) -> ReferencePreview? {
    guard let library else { return nil }
    switch reference.target {
    case .document:
      return ReferencePreview(reference: reference, library: library)
    case .anchor(let anchor):
      if let heading = built?.anchors.heading(of: anchor) {
        return ReferencePreview(reference: reference, library: library, heading: heading)
      }
      return bibliography.entry(anchor: anchor).map {
        ReferencePreview(reference: reference, library: library, entry: $0)
      }
    }
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator: UITextViewDelegate {
    func textView(
      _ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction
    ) -> UIAction? {
      guard case .link(let url) = textItem.content else { return defaultAction }
      // A tap carries no modifiers. Opening a reference elsewhere is the long-press
      // menu's job on this platform, not a chord's.
      return onLink(url, .here) ? nil : defaultAction
    }

    /// The long-press preview. `defaultMenu` (copy, etc.) still shows; only a run
    /// carrying `.rfcReference` gets the extra preview card above it.
    func textView(
      _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
      guard let box = reference(at: textItem), let preview = preview(for: box.reference) else {
        return .init(menu: defaultMenu)
      }
      let host = UIHostingController(rootView: preview)
      // Sized here, the way the header host is in `layOut`: the preview is shown
      // at its view's own size, and a hosting controller's view is not sized to
      // its content until something lays it out.
      host.view.frame.size = host.sizeThatFits(
        in: CGSize(width: ReferencePreview.width, height: CGFloat.greatestFiniteMagnitude))
      // Opaque, as a context-menu preview's view is expected to be: the card has no
      // background of its own, because on macOS the popover supplies one.
      host.view.backgroundColor = .systemBackground
      referencePreviewHost = host
      return UITextItem.MenuConfiguration(preview: .view(host.view), menu: defaultMenu)
    }

    private func reference(at textItem: UITextItem) -> ReferenceBox? {
      // `UITextItem.range` is a plain `NSRange` — already the absolute character
      // offset `reference(at:)` wants, no `NSTextLocation` translation needed.
      reference(at: textItem.range.location)?.box
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      reportVisibleAnchor()
    }
  }
#else
  extension RFCTextViewCoordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      // A force click is a click too, so its mouse-up may arrive here and follow
      // the link from under the card it just opened: `ReferenceHover` swallows it
      // once. No event number is compared: `eventNumber` raises on anything but a
      // mouse event, and a force click's own events are not all mouse events.
      let box = textView.textLayoutManager?.attributedText?.reference(at: charIndex)?.box
      let effects = hover.send(.clickedLink(reference: box, pointer: NSEvent.mouseLocation))
      guard !effects.contains(.swallowClick) else { return true }
      guard let url = Self.url(fromLink: link) else { return false }
      // Read here rather than passed down from the view: by the time SwiftUI's
      // `openURL` sees the link, the click that carried the modifiers is gone.
      return onLink(url, .current)
    }

    /// A context menu ends a dwell in progress, which would otherwise open a card
    /// under the menu or the moment it closes.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int)
      -> NSMenu?
    {
      hover.send(.contextMenu)
      return menu
    }

    /// AppKit has no scroll delegate; the clip view's bounds moving is the signal.
    /// Registered with the selector-based API so it unregisters with the coordinator.
    /// Scrolling also cancels any hover in progress — the popover is anchored to a
    /// character rect that scrolling has just moved out from under it — and then
    /// hit-tests again where the pointer is, because the text moved and the pointer
    /// may not have. Every further scroll restarts that dwell, so a reference
    /// scrolled under a resting pointer previews once scrolling stops. The hit test
    /// waits for the dwell to end rather than running on every tick: a fling posts
    /// a notification per frame, and only where the text comes to rest matters.
    /// A scroll caused by following a link does neither; see
    /// `ReferenceHover.linkClickPointer`.
    @objc
    func viewportDidScroll(_ notification: Notification) {
      reportVisibleAnchor()
      hover.send(.scrolled)
    }

    /// The next click is a click of its own, not the tail of a force click, and it
    /// ends any dwell. In a link preview's reader it commits the preview.
    func mouseDownInText() -> Bool {
      let withControl = NSEvent.modifierFlags.contains(.control)
      guard hover.send(.mouseDown(withControl: withControl)).contains(.commitPreview),
        let commitsOnClick
      else { return false }
      commitsOnClick()
      return true
    }

    // MARK: - Hover preview

    /// Hands the controller the text view and what only the document knows: where a
    /// reference is, what its card says, and what rests under the pointer.
    private func setUpHover() {
      guard let textView else { return }
      hover.attach(to: textView)
      hover.target = { [weak self] point in self?.reference(atWindowPoint: point) }
      hover.restingTarget = { [weak self] in self?.referenceUnderRestingPointer() }
      hover.card = { [weak self] target in
        guard let self, let preview = self.preview(for: target.box.reference),
          let rect = self.referenceRect(for: target.range)
        else { return nil }
        return ReferenceHoverController.Popover(
          content: NSHostingController(rootView: preview), anchor: rect)
      }
      hover.documentPreview = { [weak self] target in self?.documentPreview(for: target) }
    }

    /// Called from `dismantleNSView`.
    func tearDownHoverTracking() {
      hover.tearDown()
    }

    private func referenceUnderRestingPointer() -> HoverTarget? {
      guard NSApp.isActive, NSEvent.pressedMouseButtons == 0, let textView,
        let window = textView.window
      else { return nil }
      let point = window.mouseLocationOutsideOfEventStream
      guard textView.visibleRect.contains(textView.convert(point, from: nil)) else { return nil }
      return reference(atWindowPoint: point)
    }

    /// Force click on a reference: Safari's link preview, for documents (#29) — the
    /// document it names, readable and scrollable, at the place it names. A
    /// bibliography entry that names no RFC has no document of ours to show, and
    /// gets its card instead. Anywhere else, and on a reference with neither, it
    /// returns false and `ReaderTextView` hands the event on to AppKit's Look Up.
    /// So does Look Up from the keyboard, which means the selection, not whatever
    /// the pointer happens to rest on — and a key event has no location to test.
    /// So does an event from any other window, such as a menu's: its location is
    /// in that window's coordinates, not the text view's.
    func quickLookReference(with event: NSEvent) -> Bool {
      guard commitsOnClick == nil, event.type != .keyDown,
        let textView, event.window === textView.window,
        let target = reference(atWindowPoint: event.locationInWindow),
        let documentID,
        let url = link(at: target.range.location),
        let resolved = LinkPreview.resolve(url, from: documentID, in: library?.index)
      else { return false }
      switch resolved {
      case .card:
        guard preview(for: target.box.reference) != nil else { return false }
        hover.send(.forceClickCard(target))
      case .document:
        guard library != nil, referenceRect(for: target.range) != nil else { return false }
        hover.send(.forceClickDocument(target))
      }
      return true
    }

    /// The link a click on the reference under `event` follows, and the character
    /// it is on, or nil when the mouse-down is on no reference. `ReaderTextView`
    /// tracks a click on a reference itself, to see its force click (#29). Not in a
    /// link preview's reader, whose clicks commit the preview.
    func referenceLink(under event: NSEvent) -> (link: Any, characterIndex: Int)? {
      guard commitsOnClick == nil, let textView, event.window === textView.window,
        let target = reference(atWindowPoint: event.locationInWindow),
        let url = link(at: target.range.location)
      else { return nil }
      return (url, target.range.location)
    }

    /// The link a reference's runs carry.
    private func link(at offset: Int) -> URL? {
      let value = textView?.textLayoutManager?.attributedText?.attribute(
        .link, at: offset, effectiveRange: nil)
      return value.flatMap(Self.url(fromLink:))
    }

    /// A link attribute's value as a URL: AppKit may hand it over as its string.
    private static func url(fromLink link: Any) -> URL? {
      link as? URL ?? (link as? String).flatMap(URL.init(string:))
    }

    /// The preview is a reader of its own — its own text view and storage, built by
    /// `DocumentTextBuilder` — in a popover beside the reference. A click in it does
    /// what a click on the reference would have, with the modifiers held for it,
    /// and closes it. Nil for a reference that names no document of ours.
    private func documentPreview(for target: HoverTarget) -> ReferenceHoverController.Popover? {
      guard let documentID, let library, let url = link(at: target.range.location),
        case .document(let id, let place)? = LinkPreview.resolve(
          url, from: documentID, in: library.index),
        let rect = referenceRect(for: target.range)
      else { return nil }
      let preview = DocumentPreview(library: library, id: id, place: place) { [weak self] in
        guard let self else { return }
        let sameDocument = id == self.documentID
        // The popover fades out as the reader moves, not before it: waiting for the
        // fade to finish left the reader standing still behind it. And a click, as
        // far as the reader is concerned: the scroll it causes must not preview
        // whatever lands under the pointer, which is now over the reader.
        self.hover.send(.previewCommitted(pointer: NSEvent.mouseLocation))
        if sameDocument {
          // The reader's own jump is animated already.
          _ = self.onLink(url, .current)
        } else {
          // Another document replaces this one; `ReaderHost` cross-fades the two.
          withAnimation(Self.documentCrossFade) { _ = self.onLink(url, .current) }
        }
      }
      // The preview's reader asks the environment for the library, and a hosting
      // controller is outside every environment chain.
      let host = NSHostingController(rootView: preview.environment(library))
      return ReferenceHoverController.Popover(
        content: host, size: DocumentPreview.size, anchor: rect)
    }

    /// The reference under a point in window coordinates. `textContainerOrigin` is
    /// the inset: the view is flipped, so subtracting it is all it takes to reach
    /// container space.
    private func reference(atWindowPoint point: NSPoint) -> HoverTarget? {
      guard let textView else { return nil }
      let viewPoint = textView.convert(point, from: nil)
      return reference(
        at: CGPoint(
          x: viewPoint.x - textView.textContainerOrigin.x,
          y: viewPoint.y - textView.textContainerOrigin.y)
      ).map { HoverTarget(box: $0.box, range: $0.range) }
    }

    /// Hit-tests a point in text-container coordinates down to a character offset,
    /// fragment → line → glyph. `NSTextView`'s older `characterIndex(for:)` goes
    /// through the TextKit 1 compatibility shim and is unreliable on a view built
    /// `usingTextLayoutManager: true`; this walks the same TextKit 2 object graph
    /// `RFCTextLayoutFragment` draws against, in reverse.
    private func reference(at containerPoint: CGPoint) -> (box: ReferenceBox, range: NSRange)? {
      guard let layout = textView?.textLayoutManager,
        let fragment = layout.textLayoutFragment(for: containerPoint)
      else { return nil }
      let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
      guard fragmentStart >= 0 else { return nil }
      let pointInFragment = CGPoint(
        x: containerPoint.x - fragment.layoutFragmentFrame.minX,
        y: containerPoint.y - fragment.layoutFragmentFrame.minY
      )
      guard
        let offset = FragmentGeometry.characterOffset(
          in: fragment.textLineFragments,
          fragmentStart: fragmentStart,
          at: pointInFragment
        )
      else { return nil }
      return reference(at: offset)
    }

    /// The rect of a reference's run, in text-container coordinates — the
    /// popover's anchor. `enumerateTextSegments` folds a run that wraps across
    /// lines into the right set of rects on its own, the same as it does for
    /// selection rendering.
    private func referenceRect(for range: NSRange) -> CGRect? {
      guard let layout = textView?.textLayoutManager,
        let textRange = layout.textRange(for: range)
      else { return nil }
      var union: CGRect?
      layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
        union = union.map { $0.union(frame) } ?? frame
        return true
      }
      return union
    }
  }

#endif

extension RFCTextViewCoordinator: nonisolated NSTextLayoutManagerDelegate {
  // TextKit 2's background-layout design permits this delegate to be called off
  // the main thread; `nonisolated` keeps the conformance honest about that rather
  // than binding it to the main actor, which approachable concurrency would infer
  // for a main-actor type. The body only reads its parameters and
  // allocates, so it needs no isolation.
  nonisolated func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    RFCTextLayoutFragment.make(for: textElement)
  }
}
