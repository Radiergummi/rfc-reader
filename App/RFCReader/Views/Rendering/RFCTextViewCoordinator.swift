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
    /// outlives no part of this.
    weak var textView: PlatformTextView?

    /// Retained deliberately: `UIHostingController().view` does not keep its
    /// controller alive, and a released controller takes trait propagation — and so
    /// Dynamic Type — with it.
    var headerHost: PlatformHostingController<AnyView>?

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

    private(set) var built: BuiltDocument?
    private var trackedIndex = AnchorIndex([])
    private var lastReportedAnchor: String?
    private var laidOutColumn: CGFloat?

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
        guard let layout = textView?.textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
    }

    // MARK: - Geometry

    /// Centres the column, hangs the header in the top inset, and re-lays out only
    /// when the column itself changed: a window wider than the measure moves the
    /// gutters, not the text.
    func layOut(width: CGFloat) {
        guard let textView, width > 0 else { return }
        let gutter = max(Self.margin, (width - Self.measure) / 2)
        let column = width - gutter * 2
        let headerHeight = headerHost?.sizeThatFits(in: CGSize(width: column, height: .greatestFiniteMagnitude)).height ?? 0

        #if canImport(UIKit)
        textView.textContainerInset = UIEdgeInsets(top: headerHeight, left: gutter, bottom: Self.margin, right: gutter)
        #else
        // AppKit's inset is symmetric, so the header's height is echoed as padding
        // under the last line. NSTextView has no asymmetric equivalent.
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.textContainerInset = NSSize(width: gutter, height: headerHeight)
        #endif
        headerHost?.view.frame = CGRect(x: gutter, y: 0, width: column, height: headerHeight)

        guard laidOutColumn != column else { return }
        laidOutColumn = column
        layOutEverything()
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

    private func scrollContainerTopTo(_ containerY: CGFloat) {
        guard let textView else { return }
        #if canImport(UIKit)
        let target = containerY + textView.textContainerInset.top
        let limit = max(0, textView.contentSize.height - textView.bounds.height)
        textView.setContentOffset(CGPoint(x: 0, y: min(max(0, target), limit)), animated: false)
        #else
        guard let scroll = textView.enclosingScrollView else { return }
        let target = containerY + textView.textContainerOrigin.y
        let limit = max(0, textView.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, target), limit)))
        scroll.reflectScrolledClipView(scroll.contentView)
        #endif
    }

    // MARK: - Links

    func handle(_ url: URL) -> Bool {
        onLink(url)
    }
}

#if canImport(UIKit)
extension RFCTextViewCoordinator: UITextViewDelegate {
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return handle(url) ? nil : defaultAction
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
    @objc
    func viewportDidScroll(_ notification: Notification) {
        reportVisibleAnchor()
    }
}
#endif

extension RFCTextViewCoordinator: NSTextLayoutManagerDelegate {
    // Filled in by Task 10; until then the default fragment is what we want.
}
