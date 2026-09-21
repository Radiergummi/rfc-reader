import RFCReaderKit
import SwiftUI

/// The reader body: one text view over one text storage.
///
/// `header` is hosted in the text view's top content inset rather than placed in the
/// storage, because it carries buttons — the status banner's links to newer RFCs —
/// and nobody selects through it. Everything below it is text.
///
/// The `GeometryReader` is the width channel: it is what makes a window resize reach
/// the representable at all, and the column is centred from it.
struct RFCTextView<Header: View>: View {
    // The coordinator builds the hover/long-press preview's hosting controller
    // itself, which sits outside SwiftUI's environment chain — so it needs the
    // library handed to it explicitly, the same way it is here.
    @Environment(LibraryModel.self) private var library
    let built: BuiltDocument
    /// The section anchors: the only anchors section tracking may report. See
    /// `RFCTextViewCoordinator.trackedAnchors`.
    let trackedAnchors: Set<String>
    /// Written synchronously as tracking computes; see `VisibleAnchorBox`.
    let lastVisibleAnchor: VisibleAnchorBox
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL) -> Bool
    /// The real text column, reported whenever the coordinator's `layOut(width:)`
    /// computes a new one — see Critical Finding 3. `DocumentView` rebuilds the
    /// document with a matching `ReadingStyle.measure` so artwork and tables scale
    /// against the column they actually render into, not a fixed 712 pt default.
    let onColumnChange: (CGFloat) -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        GeometryReader { geometry in
            Representable(
                built: built,
                trackedAnchors: trackedAnchors,
                lastVisibleAnchor: lastVisibleAnchor,
                width: geometry.size.width,
                scrollTarget: scrollTarget,
                onScrollHandled: onScrollHandled,
                onVisibleAnchorChange: onVisibleAnchorChange,
                onLink: onLink,
                onColumnChange: onColumnChange,
                library: library,
                header: AnyView(header())
            )
        }
    }
}

#if canImport(UIKit)
private struct Representable: UIViewRepresentable {
    let built: BuiltDocument
    let trackedAnchors: Set<String>
    let lastVisibleAnchor: VisibleAnchorBox
    let width: CGFloat
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL) -> Bool
    let onColumnChange: (CGFloat) -> Void
    let library: LibraryModel
    let header: AnyView

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        // `.never`: SwiftUI already places this inside the safe area, and anything
        // else moves `contentOffset`'s origin away from the top of the content,
        // which is what the anchor arithmetic is expressed in.
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textLayoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator

        let host = UIHostingController(rootView: header)
        host.view.backgroundColor = .clear
        textView.addSubview(host.view)

        context.coordinator.textView = textView
        context.coordinator.headerHost = host
        context.coordinator.lastVisibleAnchor = lastVisibleAnchor
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onScrollHandled = onScrollHandled
        coordinator.onVisibleAnchorChange = onVisibleAnchorChange
        coordinator.onLink = onLink
        coordinator.onColumnChange = onColumnChange
        coordinator.library = library
        coordinator.trackedAnchors = trackedAnchors
        coordinator.headerHost?.rootView = header
        coordinator.layOut(width: width)
        if coordinator.built?.text !== built.text {
            coordinator.install(built)
        }
        if let scrollTarget {
            coordinator.scroll(to: scrollTarget)
        }
    }
}
#else
private struct Representable: NSViewRepresentable {
    let built: BuiltDocument
    let trackedAnchors: Set<String>
    let lastVisibleAnchor: VisibleAnchorBox
    let width: CGFloat
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL) -> Bool
    let onColumnChange: (CGFloat) -> Void
    let library: LibraryModel
    let header: AnyView

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        // AppKit needs all five to let a hand-built text view grow downwards inside a
        // scroll view; UITextView is a scroll view already and arranges its own.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textLayoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator

        let host = NSHostingController(rootView: header)
        textView.addSubview(host.view)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // AppKit has no scroll delegate. The selector-based observer unregisters
        // itself with the coordinator, which the block-based one would not.
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(RFCTextViewCoordinator.viewportDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )

        context.coordinator.textView = textView
        context.coordinator.headerHost = host
        context.coordinator.lastVisibleAnchor = lastVisibleAnchor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onScrollHandled = onScrollHandled
        coordinator.onVisibleAnchorChange = onVisibleAnchorChange
        coordinator.onLink = onLink
        coordinator.onColumnChange = onColumnChange
        coordinator.library = library
        coordinator.trackedAnchors = trackedAnchors
        coordinator.headerHost?.rootView = header
        coordinator.layOut(width: width)
        if coordinator.built?.text !== built.text {
            coordinator.install(built)
        }
        if let scrollTarget {
            coordinator.scroll(to: scrollTarget)
        }
    }

    /// The hover preview's timer is self-cleaning (its `[weak self]` capture on
    /// the coordinator means it cannot outlive this view), but a popover already
    /// on screen would not otherwise close when the view goes away.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: RFCTextViewCoordinator) {
        coordinator.cancelHover()
    }
}
#endif
