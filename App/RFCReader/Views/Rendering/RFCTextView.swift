import RFCKit
import RFCReaderKit
import SwiftUI

/// The reader body: one text view over one text storage.
///
/// `header` is hosted in the text view's top content inset rather than placed in the
/// storage, because it carries buttons — the status banner's links to newer RFCs —
/// and nobody selects through it. Everything below it is text.
///
/// The `GeometryReader` is the width channel: it is what makes a window resize reach
/// the representable at all, and the column is centered from it.
struct RFCTextView: View {
  // The coordinator builds the hover/long-press preview's hosting controller
  // itself, which sits outside SwiftUI's environment chain — so it needs the
  // library handed to it explicitly, the same way it is here.
  @Environment(LibraryModel.self) private var library
  /// Everything else, gathered once here; see `ReaderInputs` for each.
  let inputs: ReaderInputs

  init(
    built: BuiltDocument,
    bibliography: [ReferenceGroup],
    measure: MeasurePreference,
    documentID: DocumentID,
    commitsOnClick: (() -> Void)? = nil,
    lastVisibleAnchor: VisibleAnchorBox,
    scrollTarget: ReaderScrollTarget?,
    onScrollHandled: @escaping () -> Void,
    onVisibleAnchorChange: @escaping (String) -> Void,
    onLink: @escaping (URL, LinkActivation) -> Bool,
    onToolbarTitle: @escaping (ToolbarTitleState) -> Void,
    onSelectionChange: @escaping (Bool) -> Void = { _ in },
    hidesChrome: Bool = false,
    onChromeHidden: @escaping (Bool) -> Void = { _ in },
    heading: HeadingBox,
    headerIdentity: DocumentHeaderView.Identity,
    @ViewBuilder header: () -> some View
  ) {
    inputs = ReaderInputs(
      built: built,
      bibliography: bibliography,
      measure: measure,
      documentID: documentID,
      commitsOnClick: commitsOnClick,
      lastVisibleAnchor: lastVisibleAnchor,
      scrollTarget: scrollTarget,
      onScrollHandled: onScrollHandled,
      onVisibleAnchorChange: onVisibleAnchorChange,
      onLink: onLink,
      onToolbarTitle: onToolbarTitle,
      onSelectionChange: onSelectionChange,
      hidesChrome: hidesChrome,
      onChromeHidden: onChromeHidden,
      heading: heading,
      header: AnyView(header()),
      headerIdentity: headerIdentity
    )
  }

  var body: some View {
    GeometryReader { geometry in
      Representable(inputs: inputs, library: library, width: geometry.size.width)
    }
  }
}

/// Where the reader is asked to scroll, and whether it should get there smoothly.
///
/// Smoothly only within a document already on screen — a link, a contents row, Back
/// within it — where the motion says which way the jump went. Arriving at a
/// document, or at a restored reading position, is not a movement the reader made.
struct ReaderScrollTarget: Equatable {
  let anchor: String
  let animated: Bool
}

/// Everything the reader is given, and the one place it is handed to the shared
/// coordinator. `RFCTextView` holds one of these rather than a copy of each field,
/// and the two representables pass it on, so an input is declared here and named
/// again only in `RFCTextView.init`'s labels. The library is not in it: it is the
/// environment's, which `RFCTextView` reads, and passed beside it.
struct ReaderInputs {
  let built: BuiltDocument
  /// The document's bibliographies, which the body leaves out: what a citation
  /// of an entry previews (#198).
  let bibliography: [ReferenceGroup]
  /// The same preference `DocumentView` derives the build's column from, so the
  /// inset settles on the column the next build measures against.
  let measure: MeasurePreference
  /// The document on screen, which a force click on an anchor previews (#29).
  let documentID: DocumentID
  /// Set only for the reader inside a link preview (#29): a click anywhere in it
  /// commits the preview rather than selecting, and it previews nothing itself.
  let commitsOnClick: (() -> Void)?
  /// Written synchronously as tracking computes; see `VisibleAnchorBox`.
  let lastVisibleAnchor: VisibleAnchorBox
  let scrollTarget: ReaderScrollTarget?
  let onScrollHandled: () -> Void
  let onVisibleAnchorChange: (String) -> Void
  let onLink: (URL, LinkActivation) -> Bool
  let onToolbarTitle: (ToolbarTitleState) -> Void
  /// Whether the reader has a selection, which grays out Edit ▸ Copy as Quote without
  /// one, as Copy is (#186). Reported on macOS only; see
  /// `RFCTextViewCoordinator.reportSelection()`.
  let onSelectionChange: (Bool) -> Void
  /// Whether reading on may hide the bars, and what to tell when it does or they
  /// come back; iOS only, see `ReaderChrome`.
  let hidesChrome: Bool
  let onChromeHidden: (Bool) -> Void
  /// Written by the header as it lays out; see `HeadingBox`.
  let heading: HeadingBox
  /// Erased on the way in rather than carried as a generic parameter: the only
  /// thing done with it is to hand it to a hosting controller, which is not
  /// generic either.
  let header: AnyView
  /// What the header displays, so the coordinator can tell a genuine change from
  /// the freshly erased `AnyView` it gets handed on every update pass.
  let headerIdentity: DocumentHeaderView.Identity

  /// Called on every SwiftUI update pass, so it does the cheap assignments first
  /// and only installs when the document itself changed.
  func apply(to coordinator: RFCTextViewCoordinator, library: LibraryModel, width: CGFloat) {
    coordinator.onScrollHandled = onScrollHandled
    coordinator.onVisibleAnchorChange = onVisibleAnchorChange
    coordinator.onLink = onLink
    coordinator.bibliography = bibliography
    coordinator.documentID = documentID
    coordinator.commitsOnClick = commitsOnClick
    coordinator.onToolbarTitle = onToolbarTitle
    coordinator.onSelectionChange = onSelectionChange
    #if canImport(UIKit)
      coordinator.onChromeHidden = onChromeHidden
      coordinator.setChromeEnabled(hidesChrome)
    #endif
    if coordinator.heading !== heading {
      coordinator.heading = heading
      heading.didChange = { [weak coordinator] in coordinator?.updateToolbarTitle() }
    }
    coordinator.library = library
    // Only when it actually changed: the hosting controller is outside SwiftUI's
    // diffing, so assigning `rootView` re-renders the whole header subtree, and
    // this runs on every update pass — including one per section crossing while
    // scrolling.
    if coordinator.headerIdentity != headerIdentity {
      coordinator.headerIdentity = headerIdentity
      coordinator.headerHost?.rootView = header
    }
    coordinator.layOut(width: width, measure: measure)
    if coordinator.built?.text !== built.text {
      coordinator.install(built)
    }
    if let scrollTarget {
      coordinator.scroll(to: scrollTarget.anchor, animated: scrollTarget.animated)
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
    let library: LibraryModel
    let width: CGFloat

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeUIView(context: Context) -> UITextView {
      let textView = ReaderTextView(usingTextLayoutManager: true)
      textView.isEditable = false
      textView.isSelectable = true
      // Off, because UIKit's text drag cannot carry a chip: it collects the chip's
      // link and its leading glyph's attachment as two overlapping ranges and
      // deletes both from its copy of the dragged text, which raises when the chip
      // ends the range. A long press on a chip lifts exactly that range (#431).
      textView.textDragInteraction?.isEnabled = false
      textView.backgroundColor = .clear
      textView.alwaysBounceVertical = true
      // `.never`: the insets for the bars the reader runs under are set by hand, in
      // `ReaderTextView.safeAreaInsetsDidChange`, which keeps the place when they
      // change; automatic adjustment would not.
      textView.contentInsetAdjustmentBehavior = .never
      textView.textContainer.lineFragmentPadding = 0
      // The coordinator sizes the container to the column; see `layOut(width:measure:)`.
      textView.textContainer.widthTracksTextView = false
      // Find-in-document, which is half of why the reader is a text view at all.
      textView.isFindInteractionEnabled = true
      textView.textLayoutManager?.delegate = context.coordinator
      textView.delegate = context.coordinator
      textView.quoteSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.quote(of: range)
      }

      let host = UIHostingController(rootView: inputs.header)
      host.view.backgroundColor = .clear
      // No safe area: the reader runs under the top bar, and the header scrolled
      // under it would otherwise be padded down by the overlap, and measured with
      // that padding by `layOut(width:measure:)`, which makes it the top inset.
      host.safeAreaRegions = []
      textView.addSubview(host.view)

      // Shows and hides the bars; see `RFCTextViewCoordinator.tappedText(_:)`.
      let tap = UITapGestureRecognizer(
        target: context.coordinator, action: #selector(RFCTextViewCoordinator.tappedText(_:)))
      tap.delegate = context.coordinator
      textView.addGestureRecognizer(tap)
      context.coordinator.chromeTap = tap

      context.coordinator.textView = textView
      context.coordinator.headerHost = host
      context.coordinator.lastVisibleAnchor = inputs.lastVisibleAnchor
      return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
      inputs.apply(to: context.coordinator, library: library, width: width)
    }
  }
#else
  private struct Representable: NSViewRepresentable {
    let inputs: ReaderInputs
    let library: LibraryModel
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
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
      textView.textContainer?.lineFragmentPadding = 0
      // The coordinator sizes the container to the column; see `layOut(width:measure:)`.
      textView.textContainer?.widthTracksTextView = false
      // The find bar lives in the scroll view, so `usesFindBar` needs the text view
      // to already be inside one — see where the scroll view is assembled below.
      textView.isIncrementalSearchingEnabled = true
      textView.usesFindBar = true
      // Off: the implicit tooltip gave every reference its raw `rfc://` URL. The
      // builder gives an external link an explicit `.toolTip` of its own URL
      // instead, so only a reference goes without — it has its preview.
      textView.displaysLinkToolTips = false
      // The default underlines every link, as a rendering attribute nothing in the
      // storage can take back. Whether links are underlined is a setting, so the
      // builder underlines them itself when asked (`ReadingStyle.underlinesLinks`).
      textView.linkTextAttributes?[.underlineStyle] = nil
      textView.textLayoutManager?.delegate = context.coordinator
      textView.delegate = context.coordinator
      textView.quickLookReference = { [weak coordinator = context.coordinator] event in
        coordinator?.quickLookReference(with: event) ?? false
      }
      textView.referenceLink = { [weak coordinator = context.coordinator] event in
        coordinator?.referenceLink(under: event)
      }
      textView.quoteSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.quote(of: range)
      }
      textView.willTrackMouseDown = { [weak coordinator = context.coordinator] in
        coordinator?.mouseDownInText() ?? false
      }

      let host = NSHostingController(rootView: inputs.header)
      textView.addSubview(host.view)
      textView.header = host.view

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
      inputs.apply(to: context.coordinator, library: library, width: width)
    }

    /// The hover preview's timer is self-cleaning (its `[weak self]` capture on
    /// the coordinator means it cannot outlive this view), but a popover already
    /// on screen would not otherwise close when the view goes away, and the
    /// tracking area does not retain the coordinator it reports to.
    ///
    /// `releaseDocument()` is the one that matters most: without it, what AppKit
    /// keeps of the text view holds the whole document (#356).
    static func dismantleNSView(_ nsView: ReaderScrollView, coordinator: RFCTextViewCoordinator) {
      coordinator.tearDownHoverTracking()
      coordinator.releaseDocument()
    }
  }
#endif
