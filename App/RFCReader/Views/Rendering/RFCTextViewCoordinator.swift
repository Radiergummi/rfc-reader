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
        setUpHoverTracking()
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
  /// hosting controller — a card's or a document's — must outlive the
  /// `UITargetedPreview` that wraps its view.
  var referencePreviewHost: PlatformHostingController<AnyView>?

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
  var commitsOnClick: (() -> Void)?
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
  /// laid out. Cancelled by the next `install` — and by a change of column, which
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
    /// `.inVisibleRect` keeps this correct across resizes and scrolling without an
    /// `updateTrackingAreas` override; see `setUpHoverTracking`.
    private var trackingArea: NSTrackingArea?
    /// Fires the hover preview after a 0.5 s dwell. Captures `self` weakly, so a
    /// coordinator that goes away before it fires neither leaks nor crashes.
    private var dwellTimer: Timer?
    /// The reference the pointer is currently over, timing or already previewed.
    /// The box, compared by identity: there is one per reference, so two adjacent
    /// references to the same target are still two hovers.
    private var hoveredBox: ReferenceBox?
    private var popover: NSPopover?
    /// The popover up is a document preview (#29), which the pointer is meant to
    /// travel into — unlike a card, which leaving the reference closes.
    private var isShowingDocumentPreview = false
    /// The reference a force click just previewed, whose own mouse-up must not
    /// follow it: see `clickedOnLink`. The next mouse-down starts a click of its
    /// own, and forgets it.
    private var forceClickedBox: ReferenceBox?
    /// Where the pointer was, in screen coordinates, when it followed a link. Until
    /// it moves from there, a scroll does not look for a reference under it: the
    /// jump the click caused is not the reader resting on whatever it landed on.
    private var linkClickPointer: NSPoint?
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
      cancelHover()
    #endif
    // What section tracking last reported, for a place whose anchor the new
    // build does not have: its section's heading is the old behaviour, and still
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

  /// Centres the column and hangs the header in the top inset.
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
        subtitle: subtitle(atEdge: edge - textView.containerTop, in: textView.textLayoutManager)
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
    private func subtitle(atEdge edge: CGFloat, in layout: NSTextLayoutManager?)
      -> ToolbarSubtitle.State
    {
      // Above the container is the header, which belongs to no section.
      guard edge >= 0, let layout,
        let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: edge))
      else { return .steady(nil) }
      let frame = fragment.layoutFragmentFrame
      return ToolbarSubtitle.state(
        in: sectionIndex,
        topFragmentStart: layout.offset(of: fragment.rangeInElement.location),
        crossing: ToolbarSubtitle.crossing(
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

  /// The link a reference's runs carry. Read from the storage rather than from
  /// what the platform says was pressed: a chip's leading glyph is an attachment,
  /// which UIKit reports as one, not as the link it is part of.
  private func link(at offset: Int) -> URL? {
    let value = textView?.textLayoutManager?.attributedText?.attribute(
      .link, at: offset, effectiveRange: nil)
    return value.flatMap(Self.url(fromLink:))
  }

  /// A link attribute's value as a URL: AppKit may hand it over as its string.
  private static func url(fromLink link: Any) -> URL? {
    link as? URL ?? (link as? String).flatMap(URL.init(string:))
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
      // A link the reader does not own, a web page, is UIKit's to open. Read from
      // the storage, as the preview's is: a press on a chip's leading glyph is an
      // attachment item, whose own default action follows nothing.
      guard let url = link(at: textItem.range.location), let documentID,
        LinkDestination.resolve(url, from: documentID, activation: .here) != .unhandled
      else { return defaultAction }
      // An action, not the link followed here and nil returned: UIKit asks for the
      // primary action as a long press begins too, so following it here navigated
      // before the preview could open (#29). Performed, it is the tap — on the
      // link, or on the long press's preview, which is the preview's commit. A tap
      // carries no modifiers. Opening a reference elsewhere is the long-press
      // menu's job on this platform, not a chord's.
      return UIAction(title: defaultAction.title, image: defaultAction.image) { [weak self] _ in
        _ = self?.onLink(url, .here)
      }
    }

    /// The long-press preview: Safari's link preview, for documents (#29). A
    /// reference to an RFC, or to a place in this one, previews that document at
    /// that place; a bibliography entry that names no RFC gets its card. The
    /// `defaultMenu` (Open, Copy, etc.) still shows beside it, and a tap on the
    /// preview performs the item's primary action, which follows the reference.
    func textView(
      _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
      // `UITextItem.range` is a plain `NSRange` — already the absolute character
      // offset `reference(at:)` wants, no `NSTextLocation` translation needed.
      guard let library, let documentID,
        let (box, range) = reference(at: textItem.range.location),
        let url = link(at: range.location),
        let target = LinkPreview.resolve(url, from: documentID, in: library.index)
      else { return .init(menu: defaultMenu) }
      let host: UIHostingController<AnyView>
      switch target {
      case .card:
        guard let preview = preview(for: box.reference) else { return .init(menu: defaultMenu) }
        host = UIHostingController(rootView: AnyView(preview))
        // Sized here, the way the header host is in `layOut`: the preview is shown
        // at its view's own size, and a hosting controller's view is not sized to
        // its content until something lays it out.
        host.view.frame.size = host.sizeThatFits(
          in: CGSize(width: ReferencePreview.width, height: CGFloat.greatestFiniteMagnitude))
      case .document(let id, let place):
        // Measured against the window, not the text view: the preview is shown
        // over the whole window, whatever the reader's own width.
        guard let window = textView.window else { return .init(menu: defaultMenu) }
        let size = LinkPreview.documentSize(fitting: window.bounds.size)
        // The commit is the tap, performed as the primary action; nothing in a
        // context menu's preview is clicked.
        let preview = DocumentPreview(library: library, id: id, place: place, size: size) {}
        // The preview's reader asks the environment for the library, and a hosting
        // controller is outside every environment chain.
        host = UIHostingController(rootView: AnyView(preview.environment(library)))
        host.view.frame.size = size
      }
      // Opaque, as a context-menu preview's view is expected to be: neither preview
      // has a background of its own, because on macOS the popover supplies one.
      host.view.backgroundColor = .systemBackground
      referencePreviewHost = host
      // UIKit makes the preview view the view of a controller of its own, which
      // raises for a view that is already a controller's: the host's is. So the
      // host's view goes inside a plain one, the way the header host's goes inside
      // the text view.
      let container = UIView(frame: host.view.frame)
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(host.view)
      let menu = referenceMenu(
        defaultMenu,
        sharing: LinkCopy.forLink(
          url, from: documentID, in: library.index, bibliography: bibliography),
        from: textView, at: range)
      return UITextItem.MenuConfiguration(preview: .view(container), menu: menu)
    }

    /// A document preview holds a whole second build, so it goes with its menu
    /// rather than waiting for the next long press to replace it.
    func textView(
      _ textView: UITextView, textItemMenuWillEndFor textItem: UITextItem,
      animator: any UIContextMenuInteractionAnimating
    ) {
      // Only the host this menu showed: a long press begun while the last menu was
      // still fading out has installed its own by the time this completion runs.
      let shown = referencePreviewHost
      animator.addCompletion { [weak self] in
        guard let self, self.referencePreviewHost === shown else { return }
        self.referencePreviewHost = nil
      }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      reportVisibleAnchor()
    }
  }
#else
  extension RFCTextViewCoordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      // A force click is a click too, so its mouse-up may arrive here and follow
      // the link from under the card it just opened. Swallowed once, when it is
      // the reference the force click previewed; the mouse-down of any later click
      // has already forgotten that. No event number is compared: `eventNumber`
      // raises on anything but a mouse event, and a force click's own events are
      // not all mouse events.
      if let forceClickedBox,
        textView.textLayoutManager?.attributedText?.reference(at: charIndex)?.box
          === forceClickedBox
      {
        self.forceClickedBox = nil
        return true
      }
      // Following a reference is what the preview was for; one still timing would
      // otherwise open over the document the click is leaving.
      cancelHover()
      linkClickPointer = NSEvent.mouseLocation
      guard let url = Self.url(fromLink: link) else { return false }
      // Read here rather than passed down from the view: by the time SwiftUI's
      // `openURL` sees the link, the click that carried the modifiers is gone.
      return onLink(url, .current)
    }

    /// A menu's tracking loop holds the run loop outside `.default` mode, so a dwell
    /// timer left running would fire the moment the menu closes.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int)
      -> NSMenu?
    {
      cancelHover()
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
    /// A scroll caused by following a link does neither; see `linkClickPointer`.
    @objc
    func viewportDidScroll(_ notification: Notification) {
      reportVisibleAnchor()
      cancelHover()
      guard linkClickPointer == nil else { return }
      dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.previewUnderRestingPointer() }
      }
    }

    private func previewUnderRestingPointer() {
      guard commitsOnClick == nil, NSApp.isActive, NSEvent.pressedMouseButtons == 0, let textView,
        let window = textView.window
      else { return }
      let point = window.mouseLocationOutsideOfEventStream
      guard textView.visibleRect.contains(textView.convert(point, from: nil)),
        let (box, range) = reference(atWindowPoint: point)
      else { return }
      hoveredBox = box
      showPopover(for: box, range: range)
    }

    /// The next click is a click of its own, not the tail of a force click, and it
    /// ends any dwell: the timer runs in `.default` mode, so a click or a drag's
    /// tracking loop only delays it until the button is up again, and a drag that
    /// began on a reference would otherwise open its card wherever the drag ended.
    func mouseDownInText() -> Bool {
      cancelHover()
      // A control-click is the context menu, in a preview as anywhere else.
      guard let commitsOnClick, !NSEvent.modifierFlags.contains(.control) else { return false }
      commitsOnClick()
      return true
    }

    // MARK: - Hover preview

    /// Added once, the moment `textView` is set. `.inVisibleRect` recomputes the
    /// tracking rect from the view's own visible rect on every resize and scroll,
    /// so there is no `updateTrackingAreas` override to keep in sync by hand.
    /// `.mouseEnteredAndExited` is what lets `mouseExited` end a hover when the
    /// pointer leaves the view entirely, rather than only on the next in-view move.
    /// `.activeInActiveApp` rather than `.activeInKeyWindow`: the popover's window can
    /// become key, and then the moves and the exit that close it would stop arriving.
    private func setUpHoverTracking() {
      guard let textView, trackingArea == nil else { return }
      let area = NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
      textView.addTrackingArea(area)
      trackingArea = area
    }

    /// A tracking area does not retain its owner, so it must not outlive this
    /// coordinator on a view that might. Called from `dismantleNSView`.
    func tearDownHoverTracking() {
      cancelHover()
      if let trackingArea { textView?.removeTrackingArea(trackingArea) }
      trackingArea = nil
    }

    /// Named explicitly, and so is `mouseExited` below: a tracking area sends its
    /// owner `mouseMoved:`, but the selector Swift derives for `mouseMoved(with:)`
    /// on a class that is not an `NSResponder` is `mouseMovedWith:`. AppKit checks
    /// before sending and skips an owner that does not respond, so with the derived
    /// name the tracking area was installed and no hover ever reached this.
    @objc(mouseMoved:)
    private func mouseMoved(with event: NSEvent) {
      // Compared, not just cleared: a move event is not proof the pointer moved.
      if let linkClickPointer {
        guard NSEvent.mouseLocation != linkClickPointer else { return }
        self.linkClickPointer = nil
      }
      hover(atWindowPoint: event.locationInWindow)
    }

    private func hover(atWindowPoint point: NSPoint) {
      // A preview previews nothing itself: a card over a card over the reader. And
      // a document preview is to be read and scrolled, so the pointer leaving the
      // reference on its way there must not close it, as it does a card.
      guard commitsOnClick == nil, !isShowingDocumentPreview else { return }
      guard let (box, range) = reference(atWindowPoint: point) else {
        cancelHover()
        return
      }
      guard box !== hoveredBox else { return }
      cancelHover()
      hoveredBox = box
      dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
        // A button still held is a click or a drag in progress, not a dwell. One
        // in the text view has already cancelled this in `mouseDownInText`.
        Task { @MainActor in
          guard NSEvent.pressedMouseButtons == 0 else { return }
          self?.showPopover(for: box, range: range)
        }
      }
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
        let (box, range) = reference(atWindowPoint: event.locationInWindow),
        let documentID,
        let url = link(at: range.location),
        let target = LinkPreview.resolve(url, from: documentID, in: library?.index)
      else { return false }
      switch target {
      case .card:
        guard preview(for: box.reference) != nil else { return false }
        // Already showing from a hover: the force click adds nothing.
        if hoveredBox === box, popover?.isShown == true {
          forceClickedBox = box
          return true
        }
        cancelHover()
        hoveredBox = box
        forceClickedBox = box
        showPopover(for: box, range: range)
      case .document(let id, let place):
        // Already open from this force click: the stage-2 pressure step and a
        // `quickLook(with:)` can both arrive for one force click.
        if forceClickedBox === box, isShowingDocumentPreview { return true }
        // Over a hover card too: this is the bigger answer to the same question.
        guard let library, let rect = referenceRect(for: range) else { return false }
        cancelHover()
        hoveredBox = box
        forceClickedBox = box
        showDocumentPreview(of: id, at: place, following: url, at: rect, library: library)
      }
      return true
    }

    /// The link a click on the reference under `event` follows, and the character
    /// it is on, or nil when the mouse-down is on no reference. `ReaderTextView`
    /// tracks a click on a reference itself, to see its force click (#29). Not in a
    /// link preview's reader, whose clicks commit the preview.
    func referenceLink(under event: NSEvent) -> (link: Any, characterIndex: Int)? {
      guard commitsOnClick == nil, let textView, event.window === textView.window,
        let (_, range) = reference(atWindowPoint: event.locationInWindow),
        let url = link(at: range.location)
      else { return nil }
      return (url, range.location)
    }

    /// The preview is a reader of its own — its own text view and storage, built by
    /// `DocumentTextBuilder` — in a popover beside the reference. A click in it does
    /// what a click on the reference would have, with the modifiers held for it,
    /// and closes it.
    private func showDocumentPreview(
      of id: DocumentID, at place: String?, following url: URL, at rect: CGRect,
      library: LibraryModel
    ) {
      let preview = DocumentPreview(library: library, id: id, place: place) { [weak self] in
        guard let self else { return }
        let sameDocument = id == self.documentID
        // The popover fades out as the reader moves, not before it: waiting for the
        // fade to finish left the reader standing still behind it.
        self.cancelHover()
        // A click, as far as the reader is concerned: the scroll it causes must not
        // preview whatever lands under the pointer, which is now over the reader.
        self.linkClickPointer = NSEvent.mouseLocation
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
      present(host, size: preview.size, at: rect)
      isShowingDocumentPreview = true
    }

    /// Shared by the card and the document preview, so the two popovers are
    /// anchored and dismissed the same way.
    private func present(_ controller: NSViewController, size: CGSize?, at rect: CGRect) {
      guard let textView else { return }
      let shown = NSPopover()
      shown.behavior = .transient
      shown.delegate = self
      shown.contentViewController = controller
      if let size { shown.contentSize = size }
      let anchor = rect.offsetBy(
        dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
      shown.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
      popover = shown
    }

    /// The reference under a point in window coordinates. `textContainerOrigin` is
    /// the inset: the view is flipped, so subtracting it is all it takes to reach
    /// container space.
    private func reference(atWindowPoint point: NSPoint) -> (box: ReferenceBox, range: NSRange)? {
      guard let textView else { return nil }
      let viewPoint = textView.convert(point, from: nil)
      return reference(
        at: CGPoint(
          x: viewPoint.x - textView.textContainerOrigin.x,
          y: viewPoint.y - textView.textContainerOrigin.y))
    }

    /// Not while a document preview is up: the pointer leaves the text view on its
    /// way into the popover, which is where it is meant to go.
    @objc(mouseExited:)
    private func mouseExited(with event: NSEvent) {
      guard !isShowingDocumentPreview else { return }
      cancelHover()
    }

    /// Cancels the dwell timer and closes the popover, if either is active, and
    /// forgets a force click's pending mouse-up. The timer's own `[weak self]`
    /// capture means a coordinator that is simply deallocated needs no help from
    /// here, but a popover left open after the view goes away would not close itself.
    func cancelHover() {
      dwellTimer?.invalidate()
      dwellTimer = nil
      hoveredBox = nil
      forceClickedBox = nil
      isShowingDocumentPreview = false
      if popover?.isShown == true { popover?.performClose(nil) }
      popover = nil
    }

    /// Checks `hoveredBox` again before showing: a move that changed or
    /// cleared the hover already invalidated this timer, but the guard costs
    /// nothing and keeps this function correct even if that ever stops being true.
    private func showPopover(for box: ReferenceBox, range: NSRange) {
      guard hoveredBox === box, let preview = preview(for: box.reference),
        let rect = referenceRect(for: range)
      else { return }
      present(NSHostingController(rootView: preview), size: nil, at: rect)
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

  extension RFCTextViewCoordinator: NSPopoverDelegate {
    /// A transient popover also closes on its own — Esc, a click elsewhere, the app
    /// going to the background — and then the hover it belonged to is over too, or
    /// the same reference could not preview again until the pointer left it. Only
    /// for the popover still current: one `cancelHover` closed has been replaced or
    /// dropped already, and its close may land after the next hover began.
    func popoverDidClose(_ notification: Notification) {
      guard let closed = notification.object as? NSPopover, closed === popover else { return }
      popover = nil
      hoveredBox = nil
      forceClickedBox = nil
      isShowingDocumentPreview = false
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
    RFCTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
  }
}
