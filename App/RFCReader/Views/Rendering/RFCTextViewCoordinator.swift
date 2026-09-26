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
    /// The reference a force click just previewed, whose own mouse-up must not
    /// follow it: see `clickedOnLink`. The next mouse-down starts a click of its
    /// own, and forgets it.
    private var forceClickedBox: ReferenceBox?
    /// Where the pointer was, in screen coordinates, when it followed a link. Until
    /// it moves from there, a scroll does not look for a reference under it: the
    /// jump the click caused is not the reader resting on whatever it landed on.
    private var linkClickPointer: NSPoint?
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
        #if !canImport(UIKit)
        // A preview timing or shown belongs to the document being replaced, and its
        // range means nothing in the new one.
        cancelHover()
        #endif
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
        reportVisibleAnchor()
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

        // No relayout here: `DocumentView` derives the column from the same width and
        // rebuilds, which lands in `install()` — the one place the document is laid
        // out. Until it does, the laid-out end belongs to the previous column, and an
        // unknown end is the safe state (`scrollContainerTopTo` then does not clamp).
        if columnChanged {
            layoutTask?.cancel()
            laidOutEnd = nil
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
        guard let textView,
              let built,
              let layout = textView.textLayoutManager,
              let offset = built.anchors.offset(of: anchor) else { return }
        ensureLayout(through: offset + Self.layoutSlice)
        guard let location = layout.location(atOffset: offset),
              let fragment = layout.textLayoutFragment(for: location) else { return }
        scrollContainerTopTo(fragment.layoutFragmentFrame.minY)
        reportVisibleAnchor()
    }

    /// Hit-tests the top of the visible rect. Deliberately not
    /// `textViewportLayoutController.viewportRange`: that range is larger than the
    /// visible rect, so its start names a section already scrolled past.
    func reportVisibleAnchor() {
        guard let textView,
              built != nil,
              let layout = textView.textLayoutManager else { return }
        let top = max(0, textView.viewportTop)
        guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
        let offset = layout.offset(of: fragment.rangeInElement.location)
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

    /// The cross reference at this absolute character offset, and its whole
    /// extent. Shared by the iOS long-press lookup and the macOS hover hit test
    /// below; the lookup itself is `NSAttributedString.reference(at:)`.
    private func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
        textView?.textLayoutManager?.attributedText?.reference(at: offset)
    }

    /// The card for a reference, on either platform, or nil when it would say no
    /// more than the reference already does. Another document has its title and
    /// abstract; a place in this one has only its section's heading, and a figure
    /// or a table has not even that.
    private func preview(for reference: CrossReference) -> ReferencePreview? {
        guard let library else { return nil }
        switch reference.target {
        case .document:
            return ReferencePreview(reference: reference, library: library)
        case .anchor(let anchor):
            return built?.anchors.heading(of: anchor).map { ReferencePreview(reference: reference, library: library, heading: $0) }
        }
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
        guard let box = reference(at: textItem), let preview = preview(for: box.reference) else { return .init(menu: defaultMenu) }
        let host = UIHostingController(rootView: preview)
        // Sized here, the way the header host is in `layOut`: the preview is shown
        // at its view's own size, and a hosting controller's view is not sized to
        // its content until something lays it out.
        host.view.frame.size = host.sizeThatFits(in: CGSize(width: ReferencePreview.width, height: CGFloat.greatestFiniteMagnitude))
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
        // the link from under the card it just opened. Swallowed once, when it is
        // the reference the force click previewed; the mouse-down of any later click
        // has already forgotten that. No event number is compared: `eventNumber`
        // raises on anything but a mouse event, and a force click's own events are
        // not all mouse events.
        if let forceClickedBox,
           textView.textLayoutManager?.attributedText?.reference(at: charIndex)?.box === forceClickedBox {
            self.forceClickedBox = nil
            return true
        }
        // Following a reference is what the preview was for; one still timing would
        // otherwise open over the document the click is leaving.
        cancelHover()
        linkClickPointer = NSEvent.mouseLocation
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        // Read here rather than passed down from the view: by the time SwiftUI's
        // `openURL` sees the link, the click that carried the modifiers is gone.
        return onLink(url, .current)
    }

    /// A menu's tracking loop holds the run loop outside `.default` mode, so a dwell
    /// timer left running would fire the moment the menu closes.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
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
        guard NSApp.isActive, NSEvent.pressedMouseButtons == 0, let textView, let window = textView.window else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard textView.visibleRect.contains(textView.convert(point, from: nil)),
              let (box, range) = reference(atWindowPoint: point) else { return }
        hoveredBox = box
        showPopover(for: box, range: range)
    }

    /// The next click is a click of its own, not the tail of a force click, and it
    /// ends any dwell: the timer runs in `.default` mode, so a click or a drag's
    /// tracking loop only delays it until the button is up again, and a drag that
    /// began on a reference would otherwise open its card wherever the drag ended.
    func mouseDownInText() {
        cancelHover()
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

    /// Force click on a reference: the same card, without the dwell. Anywhere else,
    /// and on a reference that has no card, it returns false and `ReaderTextView`
    /// hands the event on to AppKit's Look Up.
    /// So does Look Up from the keyboard, which means the selection, not whatever
    /// the pointer happens to rest on — and a key event has no location to test.
    /// So does an event from any other window, such as a menu's: its location is
    /// in that window's coordinates, not the text view's.
    func quickLookReference(with event: NSEvent) -> Bool {
        guard event.type != .keyDown,
              let textView, event.window === textView.window,
              let (box, range) = reference(atWindowPoint: event.locationInWindow),
              preview(for: box.reference) != nil else { return false }
        if hoveredBox === box, popover?.isShown == true {
            forceClickedBox = box
            return true
        }
        cancelHover()
        hoveredBox = box
        forceClickedBox = box
        showPopover(for: box, range: range)
        return true
    }

    /// The reference under a point in window coordinates. `textContainerOrigin` is
    /// the inset: the view is flipped, so subtracting it is all it takes to reach
    /// container space.
    private func reference(atWindowPoint point: NSPoint) -> (box: ReferenceBox, range: NSRange)? {
        guard let textView else { return nil }
        let viewPoint = textView.convert(point, from: nil)
        return reference(at: CGPoint(x: viewPoint.x - textView.textContainerOrigin.x, y: viewPoint.y - textView.textContainerOrigin.y))
    }

    @objc(mouseExited:)
    private func mouseExited(with event: NSEvent) {
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
        if popover?.isShown == true { popover?.performClose(nil) }
        popover = nil
    }

    /// Checks `hoveredBox` again before showing: a move that changed or
    /// cleared the hover already invalidated this timer, but the guard costs
    /// nothing and keeps this function correct even if that ever stops being true.
    private func showPopover(for box: ReferenceBox, range: NSRange) {
        guard let textView, hoveredBox === box, let preview = preview(for: box.reference),
              let rect = referenceRect(for: range) else { return }
        let host = NSHostingController(rootView: preview)
        let shown = NSPopover()
        shown.behavior = .transient
        shown.delegate = self
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
