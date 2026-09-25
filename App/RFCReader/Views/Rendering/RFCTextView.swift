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
struct RFCTextView: View {
    // The coordinator builds the hover/long-press preview's hosting controller
    // itself, which sits outside SwiftUI's environment chain — so it needs the
    // library handed to it explicitly, the same way it is here.
    @Environment(LibraryModel.self) private var library
    let built: BuiltDocument
    /// Written synchronously as tracking computes; see `VisibleAnchorBox`.
    let lastVisibleAnchor: VisibleAnchorBox
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL, LinkActivation) -> Bool
    /// Erased on the way in rather than carried as a generic parameter: the only
    /// thing done with it is to hand it to a hosting controller, which is not
    /// generic either.
    let header: AnyView
    /// What the header displays, so the coordinator can tell a genuine change from
    /// the freshly erased `AnyView` it gets handed on every update pass.
    let headerIdentity: DocumentHeaderView.Identity

    init(
        built: BuiltDocument,
        lastVisibleAnchor: VisibleAnchorBox,
        scrollTarget: String?,
        onScrollHandled: @escaping () -> Void,
        onVisibleAnchorChange: @escaping (String) -> Void,
        onLink: @escaping (URL, LinkActivation) -> Bool,
        headerIdentity: DocumentHeaderView.Identity,
        @ViewBuilder header: () -> some View
    ) {
        self.built = built
        self.lastVisibleAnchor = lastVisibleAnchor
        self.scrollTarget = scrollTarget
        self.onScrollHandled = onScrollHandled
        self.onVisibleAnchorChange = onVisibleAnchorChange
        self.onLink = onLink
        self.headerIdentity = headerIdentity
        self.header = AnyView(header())
    }

    var body: some View {
        GeometryReader { geometry in
            Representable(
                inputs: ReaderInputs(
                    built: built,
                    lastVisibleAnchor: lastVisibleAnchor,
                    scrollTarget: scrollTarget,
                    onScrollHandled: onScrollHandled,
                    onVisibleAnchorChange: onVisibleAnchorChange,
                    onLink: onLink,
                    library: library,
                    header: header,
                    headerIdentity: headerIdentity
                ),
                width: geometry.size.width
            )
        }
    }
}

/// Everything the two representables hand their shared coordinator, and the one
/// place that handing-over is written. Declared outside the `#if` so a new callback
/// is added once instead of in both platform structs and both update bodies.
struct ReaderInputs {
    let built: BuiltDocument
    let lastVisibleAnchor: VisibleAnchorBox
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL, LinkActivation) -> Bool
    let library: LibraryModel
    let header: AnyView
    let headerIdentity: DocumentHeaderView.Identity

    /// Called on every SwiftUI update pass, so it does the cheap assignments first
    /// and only installs when the document itself changed.
    @MainActor
    func apply(to coordinator: RFCTextViewCoordinator, width: CGFloat) {
        coordinator.onScrollHandled = onScrollHandled
        coordinator.onVisibleAnchorChange = onVisibleAnchorChange
        coordinator.onLink = onLink
        coordinator.library = library
        // Only when it actually changed: the hosting controller is outside SwiftUI's
        // diffing, so assigning `rootView` re-renders the whole header subtree, and
        // this runs on every update pass — including one per section crossing while
        // scrolling.
        if coordinator.headerIdentity != headerIdentity {
            coordinator.headerIdentity = headerIdentity
            coordinator.headerHost?.rootView = header
        }
        coordinator.layOut(width: width)
        if coordinator.built?.text !== built.text {
            coordinator.install(built)
        }
        if let scrollTarget {
            coordinator.scroll(to: scrollTarget)
        }
    }
}

#if !canImport(UIKit)
/// The reader's scroll view, which does not give up width to the contents panel.
///
/// The reader's pane runs underneath the panel, so AppKit reports the panel's width
/// as a right safe-area inset — and a scroll view turns its safe area into content
/// insets, which the text view tracks. Measured: the scroll view and its clip view
/// stayed 1019 pt wide while the text view inside went to 699 and its column to 392,
/// so the text re-wrapped although nothing above it had changed. Refusing the inset
/// here is the level that works: it was tried on the hosted root, on this
/// representable and on the hosting controller, and none of those reach the clip
/// view. Only the trailing edge is refused, because zeroing the insets outright puts
/// the first lines of the document behind the toolbar.
final class ReaderScrollView: NSScrollView {
    override var safeAreaInsets: NSEdgeInsets {
        var insets = super.safeAreaInsets
        insets.right = 0
        return insets
    }
}
#endif

#if canImport(UIKit)
private struct Representable: UIViewRepresentable {
    let inputs: ReaderInputs
    let width: CGFloat

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = ReaderTextView(usingTextLayoutManager: true)
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
        // Find-in-document, which is half of why the reader is a text view at all.
        textView.isFindInteractionEnabled = true
        textView.textLayoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator

        let host = UIHostingController(rootView: inputs.header)
        host.view.backgroundColor = .clear
        textView.addSubview(host.view)

        context.coordinator.textView = textView
        context.coordinator.headerHost = host
        context.coordinator.lastVisibleAnchor = inputs.lastVisibleAnchor
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        inputs.apply(to: context.coordinator, width: width)
    }
}
#else
private struct Representable: NSViewRepresentable {
    let inputs: ReaderInputs
    let width: CGFloat

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeNSView(context: Context) -> ReaderScrollView {
        let textView = ReaderTextView(usingTextLayoutManager: true)
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
        // The find bar lives in the scroll view, so `usesFindBar` needs the text view
        // to already be inside one — see where the scroll view is assembled below.
        textView.isIncrementalSearchingEnabled = true
        textView.usesFindBar = true
        // On by default: every `.link` run gets an implicit tooltip of its URL, and
        // hovering a reference showed the raw `rfc://8174`. The hover popover is what
        // a reference shows; nothing in the reader surfaces the app's own scheme.
        textView.displaysLinkToolTips = false
        textView.textLayoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator

        let host = NSHostingController(rootView: inputs.header)
        textView.addSubview(host.view)

        let scroll = ReaderScrollView()
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
        context.coordinator.lastVisibleAnchor = inputs.lastVisibleAnchor
        return scroll
    }

    func updateNSView(_ scroll: ReaderScrollView, context: Context) {
        inputs.apply(to: context.coordinator, width: width)
    }

    /// The hover preview's timer is self-cleaning (its `[weak self]` capture on
    /// the coordinator means it cannot outlive this view), but a popover already
    /// on screen would not otherwise close when the view goes away.
    static func dismantleNSView(_ nsView: ReaderScrollView, coordinator: RFCTextViewCoordinator) {
        coordinator.cancelHover()
    }
}
#endif
