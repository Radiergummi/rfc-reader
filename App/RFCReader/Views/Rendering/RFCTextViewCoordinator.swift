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
    /// The text column. `ReadingStyle.measure` is what the builder measured artwork
    /// and tables against, so the container has to match it or the two disagree
    /// about what fits.
    static let measure = ReadingStyle().measure

    /// The smallest gutter beside the column, and the padding under the last line.
    static let margin: CGFloat = 24

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
    var onLink: (URL) -> Bool = { _ in false }

    /// The anchors tracking is allowed to report. The index covers *every* anchor —
    /// paragraphs, figures, tables, reference rows — because `scroll(to:)` has to
    /// reach all of them, but every consumer of `visibleAnchor` resolves it with
    /// `document.section(anchor:)`, so reporting a paragraph anchor would silently
    /// break all four. Sections only, therefore, and the index of them is derived.
    var trackedAnchors: Set<String> = [] {
        didSet {
            guard trackedAnchors != oldValue else { return }
            deriveTrackedIndex()
        }
    }

    /// Where section tracking last put the reader, written the moment it is computed.
    /// `visibleAnchor` in `DocumentView` is the observable copy and lags this by a
    /// main-actor hop, which `onDisappear` cannot afford to wait for.
    var lastVisibleAnchor: VisibleAnchorBox?

    private(set) var built: BuiltDocument?
    private var trackedIndex = AnchorIndex([])
    private var lastReportedAnchor: String?
    private var laidOutColumn: CGFloat?
    private var laidOutHeaderHeight: CGFloat?

    /// The bottom of the last laid-out fragment, in container coordinates. The text
    /// view's own `contentSize`/`frame` are republished by *its* layout pass, not by
    /// `ensureLayout`, so they can still read near zero in the same update that
    /// installed the document — and clamping a deep jump against that would land at
    /// the top and overwrite the reading position with section one.
    private var laidOutEnd: CGFloat?

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

    /// Swaps in a document and lays the whole of it out, synchronously.
    ///
    /// Viewport layout would be cheaper here and wrong afterwards:
    /// `usageBoundsForTextContainer` keeps moving as the viewport does, which the
    /// scroller shows as jitter, and estimated fragment heights run well above the
    /// laid-out ones, so an anchor's y is a guess. The document is immutable once
    /// built, so one pass buys a stable content size, an exact anchor → y mapping
    /// and correct hit-testing for the rest of its life.
    func install(_ built: BuiltDocument) {
        guard let textView,
              let layout = textView.textLayoutManager,
              let storage = layout.textContentManager as? NSTextContentStorage else { return }
        self.built = built
        lastReportedAnchor = nil
        deriveTrackedIndex()
        deriveAccessibilityItems()
        storage.performEditingTransaction {
            storage.attributedString = built.text
        }
        layOutEverything()
        reportVisibleAnchor()
    }

    private func deriveTrackedIndex() {
        trackedIndex = AnchorIndex(built?.anchors.entries.filter { trackedAnchors.contains($0.anchor) } ?? [])
    }

    private func layOutEverything() {
        laidOutEnd = nil
        guard let layout = textView?.textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
        var end: CGFloat?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            end = fragment.layoutFragmentFrame.maxY
            return false
        }
        laidOutEnd = end
    }

    // MARK: - Geometry

    /// Centres the column and hangs the header in the top inset.
    ///
    /// This runs on every update pass — and an update pass happens on every section
    /// crossing, because `visibleAnchor` is `@State` — so nothing is written unless
    /// the column or the header's height actually moved. A relayout costs more
    /// still, and only the column can force one: a window wider than the measure
    /// moves the gutters, not the text.
    func layOut(width: CGFloat) {
        guard let textView, width > 0 else { return }
        let gutter = max(Self.margin, (width - Self.measure) / 2)
        let column = width - gutter * 2
        let headerHeight = headerHost?.sizeThatFits(in: CGSize(width: column, height: .greatestFiniteMagnitude)).height ?? 0
        guard column != laidOutColumn || headerHeight != laidOutHeaderHeight else { return }
        let columnChanged = column != laidOutColumn
        laidOutColumn = column
        laidOutHeaderHeight = headerHeight

        #if canImport(UIKit)
        textView.textContainerInset = UIEdgeInsets(top: headerHeight, left: gutter, bottom: Self.margin, right: gutter)
        #else
        // AppKit's inset is symmetric, so the header's height is echoed as padding
        // under the last line. NSTextView has no asymmetric equivalent.
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.textContainerInset = NSSize(width: gutter, height: headerHeight)
        #endif
        headerHost?.view.frame = CGRect(x: gutter, y: 0, width: column, height: headerHeight)

        if columnChanged { layOutEverything() }
    }

    // MARK: - Scrolling

    /// Puts the anchor's fragment at the top of the viewport. The document is laid
    /// out already, so this is a lookup rather than a layout pass.
    func scroll(to anchor: String) {
        // Deferred: this runs inside SwiftUI's update, where mutating state is illegal.
        defer { Task { self.onScrollHandled() } }
        guard let textView,
              let built,
              let layout = textView.textLayoutManager,
              let offset = built.anchors.offset(of: anchor),
              let location = layout.location(layout.documentRange.location, offsetBy: offset),
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
              let layout = textView.textLayoutManager,
              let top = visibleContainerTop,
              let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: max(0, top))) else { return }
        let offset = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
        // The abstract is the first prose in the storage and sits ahead of section
        // one, so while it is on screen the reader is, as far as every consumer of
        // this is concerned, in section one — which is what the old view reported too.
        guard let anchor = trackedIndex.anchor(at: offset) ?? trackedIndex.entries.first?.anchor,
              anchor != lastReportedAnchor else { return }
        lastReportedAnchor = anchor
        lastVisibleAnchor?.anchor = anchor
        // Deferred for the same reason as `onScrollHandled`: installing a document
        // reports from inside SwiftUI's update, where mutating state is illegal.
        Task { self.onVisibleAnchorChange(anchor) }
    }

    /// The top of the viewport in text-container coordinates.
    private var visibleContainerTop: CGFloat? {
        guard let textView else { return nil }
        #if canImport(UIKit)
        return textView.contentOffset.y - textView.textContainerInset.top
        #else
        return textView.visibleRect.minY - textView.textContainerOrigin.y
        #endif
    }

    /// Clamped against the laid-out document end rather than the text view's own
    /// published height, and **not clamped at all** if that end is unknown: an
    /// overshoot self-corrects on the next scroll, whereas clamping to the top
    /// silently rewrites the reading position.
    private func scrollContainerTopTo(_ containerY: CGFloat) {
        guard let textView else { return }
        // The view's own geometry has to be current before an offset is set against
        // it, or the platform clamps the jump to a content size it has not published
        // yet. The text is laid out already, so this only syncs frames.
        #if canImport(UIKit)
        textView.layoutIfNeeded()
        #else
        textView.enclosingScrollView?.layoutSubtreeIfNeeded()
        #endif
        #if canImport(UIKit)
        let inset = textView.textContainerInset
        let top = inset.top
        let content = laidOutEnd.map { top + $0 + inset.bottom }
        let viewport = textView.bounds.height
        #else
        guard let scroll = textView.enclosingScrollView else { return }
        let top = textView.textContainerOrigin.y
        let content = laidOutEnd.map { top + $0 + textView.textContainerInset.height }
        let viewport = scroll.contentView.bounds.height
        #endif
        var target = max(0, containerY + top)
        if let content {
            target = min(target, max(0, content - viewport))
        }
        #if canImport(UIKit)
        textView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        #else
        scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        scroll.reflectScrolledClipView(scroll.contentView)
        #endif
    }

    // MARK: - Links

    func handle(_ url: URL) -> Bool {
        onLink(url)
    }

    // MARK: - References

    /// The cross reference tagged on the run at this absolute character offset,
    /// and the full extent of its run. Shared by the iOS long-press lookup and the
    /// macOS hover hit test below.
    private func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
        guard let layout = textView?.textLayoutManager,
              let storage = layout.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString,
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
        return handle(url) ? nil : defaultAction
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
        return handle(url)
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
        let fragmentStart = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
        guard fragmentStart >= 0 else { return nil }
        let pointInFragment = CGPoint(
            x: containerPoint.x - fragment.layoutFragmentFrame.minX,
            y: containerPoint.y - fragment.layoutFragmentFrame.minY
        )
        for line in fragment.textLineFragments
        where line.typographicBounds.minY <= pointInFragment.y && pointInFragment.y < line.typographicBounds.maxY {
            let pointInLine = CGPoint(x: pointInFragment.x - line.typographicBounds.minX, y: pointInFragment.y - line.typographicBounds.minY)
            let offset = fragmentStart + line.characterRange.location + line.characterIndex(for: pointInLine)
            return reference(at: offset)
        }
        return nil
    }

    /// The rect of a reference's run, in text-container coordinates — the
    /// popover's anchor. `enumerateTextSegments` folds a run that wraps across
    /// lines into the right set of rects on its own, the same as it does for
    /// selection rendering.
    private func referenceRect(for range: NSRange) -> CGRect? {
        guard let layout = textView?.textLayoutManager,
              let start = layout.location(layout.documentRange.location, offsetBy: range.location),
              let end = layout.location(layout.documentRange.location, offsetBy: NSMaxRange(range)),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
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
