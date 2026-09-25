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
@MainActor
final class VisibleAnchorBox {
    var anchor: String?
}

/// Everything the two representables share. Both platforms drive the same anchor
/// jumping, viewport tracking and link handling; only the scroll plumbing differs,
/// and that difference lives here rather than in the representables so the pair
/// stays reviewable side by side.
@MainActor
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
    /// same line back at the top of the new storage.
    private var place: ReadingPlace?
    /// The text container's width when the current storage was last a faithful map
    /// of the screen. A resize re-wraps the old storage at the new width long before
    /// the rebuild lands, so the same scroll offset shows other text — and tracking
    /// that would record a place the reader never was. See `reportVisibleAnchor`.
    private var trackedWidth: CGFloat?
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
    private var hoveredReference: CrossReference?
    private var popover: NSPopover?
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
              let storage = layout.textContentManager as? NSTextContentStorage else { return }
        // Only a restyle has a place to carry: the first install of a document leaves
        // the choice between a deep link and the saved reading position to
        // `DocumentView`, and a coordinator never outlives its document.
        let carried = self.built == nil ? nil : place
        // What section tracking last reported, for a place whose anchor the new
        // build does not have: its section's heading is the old behaviour, and still
        // far better than the top of the document.
        let fallback = self.built == nil ? nil : lastReportedAnchor
        self.built = built
        lastReportedAnchor = nil
        sectionIndex = built.anchors.sections
        deriveAccessibilityItems()
        // Written through the backing `NSTextStorage`, never by assigning
        // `storage.attributedString`.
        //
        // That assignment *discards* the `NSTextStorage` — measured: non-nil before,
        // nil immediately after, and `textView.textStorage` nil with it. TextKit 2
        // lays out and draws from `attributedString` alone, so the document still
        // renders perfectly and the damage is invisible: what breaks is everything
        // AppKit still routes through the text storage. Dragging computed a correct
        // selection and then discarded it at mouse-up, and `clickedOnLink` never
        // fired, so the reader could be read but not selected, copied, or clicked.
        storage.performEditingTransaction {
            storage.textStorage?.setAttributedString(built.text)
        }
        beginLayout()
        // The column `layOut` sized the container to, which is the column this
        // document was built at. Nil if no layout has run yet; the first one sets it.
        trackedWidth = laidOutColumn
        if let offset = carried?.documentOffset(in: built.anchors, length: built.text.length)
            ?? fallback.flatMap(built.anchors.offset(of:)) {
            scroll(toOffset: offset)
        } else {
            reportVisibleAnchor()
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
        layoutTask = Task { [weak self] in
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
        guard end > laidOutThrough, let range = layout.textRange(for: NSRange(location: 0, length: end)) else { return }
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
    /// still, and only the column can force one: a window wider than the measure
    /// moves the gutters, not the text.
    func layOut(width: CGFloat) {
        guard let textView, width > 0 else { return }
        let gutter = ReaderLayout.gutter(forWidth: width)
        let column = ReaderLayout.column(forWidth: width)
        // Measured every pass, deliberately: the height depends on the width, on the
        // content size category, and on metadata that can arrive after the first
        // layout, and a cache keyed on any one of those goes stale as a header
        // overlapping the first paragraph. Only the writes below are conditional.
        let headerHeight = headerHost?.sizeThatFits(in: CGSize(width: column, height: .greatestFiniteMagnitude)).height ?? 0
        guard column != laidOutColumn || gutter != laidOutGutter || headerHeight != laidOutHeaderHeight else { return }
        let columnChanged = column != laidOutColumn
        let firstColumn = laidOutColumn == nil
        laidOutColumn = column
        laidOutGutter = gutter
        laidOutHeaderHeight = headerHeight

        #if canImport(UIKit)
        textView.textContainerInset = UIEdgeInsets(top: headerHeight, left: gutter, bottom: ReaderLayout.margin, right: gutter)
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
        // No relayout here: `DocumentView` derives the column from the same width and
        // rebuilds, which lands in `install()` — the one place the document is laid
        // out. Until it does, the laid-out end belongs to the previous column, and an
        // unknown end is the safe state (`scrollContainerTopTo` then does not clamp);
        // nothing is laid out at the new column yet either, so a jump in the meantime
        // lays out from the start again rather than trusting frames that are gone.
        if columnChanged {
            #if canImport(UIKit)
            textView.textContainer.size = CGSize(width: column, height: .greatestFiniteMagnitude)
            #else
            textView.textContainer?.size = NSSize(width: column, height: .greatestFiniteMagnitude)
            #endif
            layoutTask?.cancel()
            laidOutEnd = nil
            laidOutThrough = 0
            // A document installed before the first layout was built at the column
            // this view derives from the same width, so it is this column.
            if firstColumn, built != nil { trackedWidth = column }
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
    func scroll(to anchor: String) {
        // Deferred: this runs inside SwiftUI's update, where mutating state is illegal.
        defer { Task { self.onScrollHandled() } }
        guard let offset = built?.anchors.offset(of: anchor) else { return }
        // Set here as well as by tracking, which does not run while a resize waits
        // for its rebuild: a jump in that window is where the rebuild must land.
        place = ReadingPlace(anchor: anchor, offset: 0)
        scroll(toOffset: offset)
    }

    /// Puts the line holding `offset` at the top of the viewport — or, for the first
    /// line, the whole fragment, spacing above it included, which is where an anchor
    /// has always landed. A place carried across a rebuild can be any line.
    private func scroll(toOffset offset: Int) {
        guard let textView, let layout = textView.textLayoutManager else { return }
        ensureLayout(through: offset + Self.layoutSlice)
        guard let location = layout.location(atOffset: offset),
              let fragment = layout.textLayoutFragment(for: location) else { return }
        let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
        let line = offset == fragmentStart ? 0 : FragmentGeometry.lineTop(of: offset, in: fragment.textLineFragments, fragmentStart: fragmentStart) ?? 0
        scrollContainerTopTo(fragment.layoutFragmentFrame.minY + line)
        reportVisibleAnchor()
    }

    /// Hit-tests the top of the visible rect. Deliberately not
    /// `textViewportLayoutController.viewportRange`: that range is larger than the
    /// visible rect, so its start names a section already scrolled past.
    func reportVisibleAnchor() {
        guard let textView,
              let built,
              let layout = textView.textLayoutManager else { return }
        // Nothing is tracked while the storage is wrapped at a width it was not
        // installed at. Between a change of column and the rebuild it triggers, the
        // old text re-wraps under an unmoved scroll offset and TextKit lays out the
        // viewport afresh from estimates: measured on RFC 9000, the top of the
        // viewport then showed text 45,000 characters from the reader's line. That
        // was recorded as the reader's place, and the rebuild duly restored it (#30).
        guard textView.textContainerWidth == trackedWidth else { return }
        let top = max(0, textView.viewportTop)
        guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
        let offset = layout.offset(of: fragment.rangeInElement.location)
        // A point of slack, so a line put exactly at the top by `scroll(toOffset:)`
        // is read back as that line and not the one above it.
        let fragmentRange = NSRange(location: offset, length: layout.offset(of: fragment.rangeInElement.endLocation) - offset)
        let line = FragmentGeometry.lineRange(at: top - fragment.layoutFragmentFrame.minY + 1, in: fragment.textLineFragments, fragment: fragmentRange)
        place = ReadingPlace.tracking(place, topLine: line, in: built.anchors, length: built.text.length)
        // The abstract is the first prose in the storage and sits ahead of section
        // one, so while it is on screen the reader is, as far as every consumer of
        // this is concerned, in section one — which is what the old view reported too.
        guard let anchor = sectionIndex.anchor(at: offset) ?? sectionIndex.entries.first?.anchor,
              anchor != lastReportedAnchor else { return }
        lastReportedAnchor = anchor
        lastVisibleAnchor?.anchor = anchor
        // Deferred for the same reason as `onScrollHandled`: installing a document
        // reports from inside SwiftUI's update, where mutating state is illegal.
        Task { self.onVisibleAnchorChange(anchor) }
    }

    /// Clamped against the laid-out document end rather than the text view's own
    /// published height, and **not clamped at all** if that end is unknown: an
    /// overshoot self-corrects on the next scroll, whereas clamping to the top
    /// silently rewrites the reading position.
    private func scrollContainerTopTo(_ containerY: CGFloat) {
        guard let textView else { return }
        textView.syncLayout()
        let top = textView.containerTop
        var target = max(0, containerY + top)
        if let end = laidOutEnd {
            let content = top + end + textView.containerBottom
            target = min(target, max(0, content - textView.viewportHeight))
        }
        textView.scroll(toY: target)
    }

    // MARK: - References

    /// The cross reference tagged on the run at this absolute character offset,
    /// and the full extent of its run. Shared by the iOS long-press lookup and the
    /// macOS hover hit test below.
    private func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
        guard let text = textView?.textLayoutManager?.attributedText,
              offset >= 0, offset < text.length else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard let box = text.attribute(.rfcReference, at: offset, effectiveRange: &range) as? ReferenceBox else { return nil }
        return (box, range)
    }
}

#if canImport(UIKit)
extension RFCTextViewCoordinator: UITextViewDelegate {
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        // A tap carries no modifiers. Opening a reference elsewhere is the long-press
        // menu's job on this platform, not a chord's.
        return onLink(url, .here) ? nil : defaultAction
    }

    /// The long-press preview. `defaultMenu` (copy, etc.) still shows; only a run
    /// carrying `.rfcReference` gets the extra preview card above it.
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard let box = reference(at: textItem), let library else { return .init(menu: defaultMenu) }
        let host = UIHostingController(rootView: ReferencePreview(reference: box.reference, library: library))
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
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        // Read here rather than passed down from the view: by the time SwiftUI's
        // `openURL` sees the link, the click that carried the modifiers is gone.
        return onLink(url, .current)
    }

    /// AppKit has no scroll delegate; the clip view's bounds moving is the signal.
    /// Registered with the selector-based API so it unregisters with the coordinator.
    /// Scrolling also cancels any hover in progress — the popover is anchored to a
    /// character rect that scrolling has just moved out from under it.
    @objc
    func viewportDidScroll(_ notification: Notification) {
        reportVisibleAnchor()
        cancelHover()
    }

    // MARK: - Hover preview

    /// Added once, the moment `textView` is set. `.inVisibleRect` recomputes the
    /// tracking rect from the view's own visible rect on every resize and scroll,
    /// so there is no `updateTrackingAreas` override to keep in sync by hand.
    /// `.mouseEnteredAndExited` is what lets `mouseExited` end a hover when the
    /// pointer leaves the view entirely, rather than only on the next in-view move.
    private func setUpHoverTracking() {
        guard let textView, trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        textView.addTrackingArea(area)
        trackingArea = area
    }

    @objc
    private func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        let viewPoint = textView.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: viewPoint.x - textView.textContainerOrigin.x, y: viewPoint.y - textView.textContainerOrigin.y)
        guard let (box, range) = reference(at: point) else {
            cancelHover()
            return
        }
        guard box.reference != hoveredReference else { return }
        cancelHover()
        hoveredReference = box.reference
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showPopover(for: box, range: range) }
        }
    }

    @objc
    private func mouseExited(with event: NSEvent) {
        cancelHover()
    }

    /// Cancels the dwell timer and closes the popover, if either is active. Called
    /// on every move to a different reference or to no reference, on scroll
    /// (`viewportDidScroll`), and when the view is dismantled
    /// (`Representable.dismantleNSView`) — the timer's own `[weak self]` capture
    /// means a coordinator that is simply deallocated needs no help from here, but
    /// a popover left open after the view goes away would not close itself.
    func cancelHover() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        hoveredReference = nil
        if popover?.isShown == true { popover?.performClose(nil) }
        popover = nil
    }

    /// Checks `hoveredReference` again before showing: a move that changed or
    /// cleared the hover already invalidated this timer, but the guard costs
    /// nothing and keeps this function correct even if that ever stops being true.
    private func showPopover(for box: ReferenceBox, range: NSRange) {
        guard let textView, let library, hoveredReference == box.reference,
              let rect = referenceRect(for: range) else { return }
        let host = NSHostingController(rootView: ReferencePreview(reference: box.reference, library: library))
        let shown = NSPopover()
        shown.behavior = .transient
        shown.contentViewController = host
        let anchor = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        shown.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        popover = shown
    }

    /// Hit-tests a point in text-container coordinates down to a character offset,
    /// fragment → line → glyph. `NSTextView`'s older `characterIndex(for:)` goes
    /// through the TextKit 1 compatibility shim and is unreliable on a view built
    /// `usingTextLayoutManager: true`; this walks the same TextKit 2 object graph
    /// `RFCTextLayoutFragment` draws against, in reverse.
    private func reference(at containerPoint: CGPoint) -> (box: ReferenceBox, range: NSRange)? {
        guard let layout = textView?.textLayoutManager,
              let fragment = layout.textLayoutFragment(for: containerPoint) else { return nil }
        let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
        guard fragmentStart >= 0 else { return nil }
        let pointInFragment = CGPoint(
            x: containerPoint.x - fragment.layoutFragmentFrame.minX,
            y: containerPoint.y - fragment.layoutFragmentFrame.minY
        )
        guard let offset = FragmentGeometry.characterOffset(
            in: fragment.textLineFragments,
            fragmentStart: fragmentStart,
            at: pointInFragment
        ) else { return nil }
        return reference(at: offset)
    }

    /// The rect of a reference's run, in text-container coordinates — the
    /// popover's anchor. `enumerateTextSegments` folds a run that wraps across
    /// lines into the right set of rects on its own, the same as it does for
    /// selection rendering.
    private func referenceRect(for range: NSRange) -> CGRect? {
        guard let layout = textView?.textLayoutManager,
              let textRange = layout.textRange(for: range) else { return nil }
        var union: CGRect?
        layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        return union
    }
}
#endif

extension RFCTextViewCoordinator: NSTextLayoutManagerDelegate {
    // TextKit 2's background-layout design permits this delegate to be called off
    // the main thread; `nonisolated` keeps the conformance honest about that rather
    // than binding it to the main actor. The body only reads its parameters and
    // allocates, so it needs no isolation.
    nonisolated func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        RFCTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
