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
  // The header's hosting controller and the previews' are outside SwiftUI's
  // environment chain, so what they read is gathered here, where it is in reach,
  // and handed to the coordinator that makes them as a `ReaderEnvironment`.
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(ReaderState.self) private var reader
  @Environment(\.colorSchemeContrast) private var contrast
  /// Which page theme is drawn: the light one or the dark one (#704).
  @Environment(\.colorScheme) private var colorScheme
  /// For the palette, the draw-time half of the settings, which reaches the text
  /// view on every update and only redraws.
  @ReaderSettingsValue private var settings
  /// Everything else, gathered once here; see `ReaderInputs` for each.
  let inputs: ReaderInputs

  init(
    built: BuiltDocument,
    bibliography: [ReferenceGroup],
    measure: MeasurePreference,
    document: ReadableDocument,
    citing: DocumentID? = nil,
    commitsOnClick: (() -> Void)? = nil,
    controller: ReaderController,
    onLink: @escaping (URL, LinkActivation) -> Bool,
    onChoosePresentation: ((PresentationKey, PresentationChoices.Presentation) -> Void)? = nil,
    hidesChrome: Bool = false,
    folding: Folding? = nil,
    isShown: Bool = true,
    coupling: ScrollCoupling? = nil,
    requirements: [Requirement]? = nil,
    headerIdentity: DocumentHeaderView.Identity,
    @ViewBuilder header: () -> some View
  ) {
    inputs = ReaderInputs(
      built: built,
      folding: folding,
      coupling: coupling,
      requirements: requirements,
      bibliography: bibliography,
      measure: measure,
      document: document,
      citing: citing ?? document.rfc,
      commitsOnClick: commitsOnClick,
      controller: controller,
      onLink: onLink,
      onChoosePresentation: onChoosePresentation,
      hidesChrome: hidesChrome,
      isShown: isShown,
      header: AnyView(header()),
      headerIdentity: headerIdentity
    )
  }

  var body: some View {
    GeometryReader { geometry in
      Representable(
        inputs: inputs,
        environment: ReaderEnvironment(
          library: library, navigation: navigation, reader: reader),
        // Increase Contrast outlines every chip (#457): a redraw, never a rebuild.
        settings: settings,
        appearance: PaletteAppearance(colorScheme),
        outlinesEveryChip: contrast == .increased,
        // Read here, where it is observed: a highlight made or changed draws again.
        // An RFC's only: a draft has none (#728).
        highlights: inputs.document.rfc.map(library.annotations.highlights(of:)) ?? [],
        width: geometry.size.width)
    }
  }
}

/// Everything the reader is given, and the one place it is handed to the shared
/// coordinator. `RFCTextView` holds one of these rather than a copy of each field,
/// and the two representables pass it on, so an input is declared here and named
/// again only in `RFCTextView.init`'s labels. The `ReaderEnvironment` is not in it:
/// it is the environment's, which `RFCTextView` reads, and passed beside it.
struct ReaderInputs {
  let built: BuiltDocument
  /// The reading mode and the sections it has expanded (#698); nil to keep what the
  /// text view has, as a reader fading out does while the scene has moved on.
  let folding: Folding?
  /// The side-by-side reading this reader scrolls together in (#187), nil when it
  /// is read alone.
  let coupling: ScrollCoupling?
  /// The document's requirements, which Implementer bands (#700); nil to keep what
  /// the text view has, as `folding` is.
  let requirements: [Requirement]?
  /// The document's bibliographies, which the body leaves out: what a citation
  /// of an entry previews (#198).
  let bibliography: [ReferenceGroup]
  /// The same preference `DocumentView` derives the build's column from, so the
  /// inset settles on the column the next build measures against.
  let measure: MeasurePreference
  /// The document on screen, which a force click on an anchor previews (#29): an
  /// RFC, or a draft's revision (#728).
  let document: ReadableDocument
  /// What a copy of it cites (#712): the document the tab opened, a series as itself
  /// rather than the RFC shown for it (#656). Nil for a draft (#728).
  let citing: DocumentID?
  /// Set only for the reader inside a link preview (#29): a click anywhere in it
  /// commits the preview rather than selecting, and it previews nothing itself.
  let commitsOnClick: (() -> Void)?
  /// What the reader reports to, and is asked through; see `ReaderController`.
  let controller: ReaderController
  let onLink: (URL, LinkActivation) -> Bool
  /// Shows a rendered verbatim block as its text, or back, from its menu. Nil where
  /// the reader cannot, as in a force-click preview: no block offers to switch.
  let onChoosePresentation: ((PresentationKey, PresentationChoices.Presentation) -> Void)?
  /// Whether reading on may hide the bars; iOS only, see `ReaderBars`.
  let hidesChrome: Bool
  /// Whether the window's reader state is this reader's. False for a reader on iOS
  /// that the stack keeps below its top (#263): what it reported was replaced by
  /// the readers pushed over it, so it reports again when this comes back.
  let isShown: Bool
  /// Erased on the way in rather than carried as a generic parameter: the only
  /// thing done with it is to hand it to a hosting controller, which is not
  /// generic either.
  let header: AnyView
  /// What the header displays, so the coordinator can tell a genuine change from
  /// the freshly erased `AnyView` it gets handed on every update pass.
  let headerIdentity: DocumentHeaderView.Identity

  /// Called on every SwiftUI update pass, so it does the cheap assignments first
  /// and only installs when the document itself changed.
  func apply(
    to coordinator: RFCTextViewCoordinator, environment: ReaderEnvironment, width: CGFloat
  ) {
    coordinator.drive(controller)
    coordinator.onLink = onLink
    coordinator.bibliography = bibliography
    coordinator.document = document
    coordinator.citing = citing
    coordinator.commitsOnClick = commitsOnClick
    coordinator.onChoosePresentation = onChoosePresentation
    #if canImport(UIKit)
      coordinator.bars.setEnabled(hidesChrome)
    #endif
    coordinator.environment = environment
    coordinator.header = header
    // Only when it actually changed: the hosting controller is outside SwiftUI's
    // diffing, so assigning `rootView` re-renders the whole header subtree, and
    // this runs on every update pass — including one per section crossing while
    // scrolling.
    if coordinator.headerIdentity != headerIdentity {
      coordinator.headerIdentity = headerIdentity
      coordinator.headerHost?.rootView = coordinator.hostedHeader(header, in: environment)
    }
    coordinator.layOut(width: width, measure: measure, hang: built.sectionNumberHang)
    if let requirements { coordinator.setRequirements(requirements) }
    let installs = coordinator.built?.text !== built.text
    if installs {
      coordinator.install(built, folding: folding ?? coordinator.folding)
    } else if let folding {
      coordinator.apply(folding)
    }
    coordinator.couple(to: coupling, installed: installs)
    // A scroll asked for before there was a build to carry it out on; one asked for
    // since went to the build at once (`ReaderController.scroll(to:offset:)`).
    if let target = controller.takePendingTarget() {
      coordinator.scroll(to: target.anchor, offset: target.offset)
    }
    if isShown, !coordinator.isShown { coordinator.reportAgain() }
    coordinator.isShown = isShown
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
    /// Told of a scroll the reader makes with a wheel, a trackpad or the scroller,
    /// before it moves anything: in a side-by-side reading, that side leads (#187).
    var willScroll: () -> Void = {}

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      // A drag of the scroller reaches neither `scrollWheel(with:)` nor the text
      // view, but starts a live scroll. Observed rather than taken from a scroller
      // subclass, which AppKit would show as a legacy, always-visible scroller.
      NotificationCenter.default.addObserver(
        self, selector: #selector(liveScrollWillStart),
        name: NSScrollView.willStartLiveScrollNotification, object: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not used: the reader's scroll view is made in code")
    }

    /// The override of `scrollWheel(with:)` only says who leads before handing the
    /// event on, so it keeps AppKit's responsive scrolling, which an override of it
    /// otherwise turns off.
    override static var isCompatibleWithResponsiveScrolling: Bool { true }

    override var safeAreaInsets: NSEdgeInsets {
      var insets = super.safeAreaInsets
      insets.right = 0
      return insets
    }

    override func scrollWheel(with event: NSEvent) {
      willScroll()
      super.scrollWheel(with: event)
    }

    @objc private func liveScrollWillStart() {
      willScroll()
    }
  }
#endif

#if canImport(UIKit)
  private struct Representable: UIViewRepresentable {
    let inputs: ReaderInputs
    let environment: ReaderEnvironment
    /// The page themes chosen, and which of them is drawn (#704).
    let settings: ReaderSettings
    let appearance: PaletteAppearance
    /// Increase Contrast, which outlines every chip (#457).
    let outlinesEveryChip: Bool
    /// The document's highlights (#522).
    let highlights: [AnnotationSnapshot.HighlightEntry]
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
      // The system tint is 3.52:1 on a white page; the reader's link color clears
      // the minimum contrast in both appearances, on the page and on a chip (#317).
      textView.linkTextAttributes = [.foregroundColor: RFCColors.readerLink]
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
      (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate =
        context.coordinator.foldingDelegate
      textView.delegate = context.coordinator
      textView.quoteSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.quote(of: range)
      }
      textView.isTranslation = { [weak coordinator = context.coordinator] in
        coordinator?.built?.isTranslation == true
      }
      textView.citeSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.citation(of: range)
      }
      textView.publicURL = { [weak coordinator = context.coordinator] link, site in
        coordinator?.publicURL(for: link, site: site)
      }
      textView.sectionNumberHang = { [weak coordinator = context.coordinator] in
        coordinator?.built?.sectionNumberHang ?? 0
      }
      textView.disclosureAction = { [weak coordinator = context.coordinator] in
        coordinator?.disclosureAction()
      }
      textView.revealRange = { [weak coordinator = context.coordinator] range in
        guard let coordinator else { return false }
        // Found or sent to its end, this side leads a side-by-side reading (#187).
        coordinator.takeLead()
        // A find hit in folded text, or ⌘↓ to its end, opens its section first (#698).
        _ = coordinator.show(range.location)
        let revealed = coordinator.engine.reveal(range)
        if revealed { coordinator.reportVisibleAnchor() }
        return revealed
      }
      textView.willHandleKey = { [weak coordinator = context.coordinator] in
        coordinator?.takeLead()
      }
      // After a jump TextKit estimates the rest of the document again, and the scroll
      // view moves its offset to keep what it shows: the title read then is read from
      // fragments that are only put where they are by the next viewport layout, which
      // no scroll follows. Only a change is reported, so a layout costs a lookup.
      textView.didLayOut = { [weak coordinator = context.coordinator] in
        coordinator?.updateToolbarTitle()
      }

      let host = UIHostingController(
        rootView: context.coordinator.hostedHeader(inputs.header, in: environment))
      host.view.backgroundColor = .clear
      // No safe area: the reader runs under the top bar, and the header scrolled
      // under it would otherwise be padded down by the overlap, and measured with
      // that padding by `layOut(width:measure:)`, which makes it the top inset.
      host.safeAreaRegions = []
      textView.addSubview(host.view)

      // Shows and hides the bars; see `RFCTextViewCoordinator.tappedText(_:)`.
      context.coordinator.bars.attach(
        to: textView, target: context.coordinator,
        action: #selector(RFCTextViewCoordinator.tappedText(_:)))
      context.coordinator.bars.report = { [weak coordinator = context.coordinator] hidden in
        coordinator?.controller?.reportBars(hidden: hidden)
      }

      context.coordinator.textView = textView
      context.coordinator.headerHost = host
      context.coordinator.drive(inputs.controller)
      return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
      inputs.apply(to: context.coordinator, environment: environment, width: width)
      context.coordinator.apply(
        settings, in: appearance, outlinesEveryChip: outlinesEveryChip)
      context.coordinator.setHighlights(highlights)
      // Not a preview's, nor a reader the stack keeps below its top (#263): Find is
      // the reader on screen's.
      let findReader = inputs.isShown && inputs.commitsOnClick == nil ? environment.reader : nil
      (textView as? ReaderTextView)?.findReader = findReader
    }

    /// Brings the bars back if this reader had put them away: the next one, after a
    /// load or a failure, starts with them showing and would not report otherwise.
    static func dismantleUIView(_ textView: UITextView, coordinator: RFCTextViewCoordinator) {
      // The background layout ends with the view, as `releaseDocument()` ends it on
      // the Mac.
      coordinator.engine.stop()
      coordinator.releaseController()
      coordinator.bars.setEnabled(false)
      coordinator.couple(to: nil, installed: false)
      // What it said of the title goes with it, as on the Mac (`releaseDocument()`):
      // a reader made afresh, on the way back from the original text, has not
      // reported yet.
      coordinator.controller?.releaseTitle(from: coordinator)
    }
  }
#else
  private struct Representable: NSViewRepresentable {
    let inputs: ReaderInputs
    let environment: ReaderEnvironment
    /// The page themes chosen, and which of them is drawn (#704).
    let settings: ReaderSettings
    let appearance: PaletteAppearance
    /// Increase Contrast, which outlines every chip (#457).
    let outlinesEveryChip: Bool
    /// The document's highlights (#522).
    let highlights: [AnnotationSnapshot.HighlightEntry]
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
      (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate =
        context.coordinator.foldingDelegate
      textView.delegate = context.coordinator
      textView.quickLookReference = { [weak coordinator = context.coordinator] event in
        coordinator?.quickLookReference(with: event) ?? false
      }
      textView.referenceLink = { [weak coordinator = context.coordinator] event in
        coordinator?.referenceLink(under: event)
      }
      textView.copySectionLink = { [weak coordinator = context.coordinator] event in
        coordinator?.copySectionLink(under: event) ?? false
      }
      textView.hoverSectionNumber = { [weak coordinator = context.coordinator] event in
        coordinator?.hoverSectionNumber(under: event)
      }
      textView.copyCode = { [weak coordinator = context.coordinator] event in
        coordinator?.copyCode(under: event) ?? false
      }
      textView.isOnGloss = { [weak coordinator = context.coordinator] event in
        coordinator?.isOnGloss(event) ?? false
      }
      textView.followGloss = { [weak coordinator = context.coordinator] event in
        coordinator?.followGloss(under: event)
      }
      textView.toggleSection = { [weak coordinator = context.coordinator] event in
        coordinator?.toggleSection(under: event) ?? false
      }
      textView.arrowCursorRects = { [weak coordinator = context.coordinator] in
        guard let coordinator else { return [] }
        return coordinator.disclosureCursorRects() + coordinator.copyButtonCursorRects()
      }
      textView.quoteSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.quote(of: range)
      }
      textView.isTranslation = { [weak coordinator = context.coordinator] in
        coordinator?.built?.isTranslation == true
      }
      textView.citeSelection = { [weak coordinator = context.coordinator] range in
        coordinator?.citation(of: range)
      }
      textView.publicURL = { [weak coordinator = context.coordinator] link, site in
        coordinator?.publicURL(for: link, site: site)
      }
      textView.sectionNumberHang = { [weak coordinator = context.coordinator] in
        coordinator?.built?.sectionNumberHang ?? 0
      }
      textView.disclosureAction = { [weak coordinator = context.coordinator] in
        coordinator?.disclosureAction()
      }
      textView.choosePresentation = { [weak coordinator = context.coordinator] in
        coordinator?.onChoosePresentation
      }
      textView.spokenStates = { [weak coordinator = context.coordinator] in
        coordinator?.spokenStates() ?? [:]
      }
      textView.revealRange = { [weak coordinator = context.coordinator] range in
        guard let coordinator else { return false }
        // Found or sent to its end, this side leads a side-by-side reading (#187).
        coordinator.takeLead()
        // A find hit in folded text, or ⌘↓ to its end, opens its section first (#698).
        _ = coordinator.show(range.location)
        let revealed = coordinator.engine.reveal(range)
        if revealed { coordinator.reportVisibleAnchor() }
        return revealed
      }
      textView.willHandleKey = { [weak coordinator = context.coordinator] in
        coordinator?.takeLead()
      }
      textView.keepingPlace = { [weak coordinator = context.coordinator] scroll in
        guard let coordinator else { return scroll() }
        coordinator.engine.keepPlace(through: scroll)
      }
      textView.willTrackMouseDown = { [weak coordinator = context.coordinator] in
        coordinator?.mouseDownInText() ?? false
      }
      textView.highlight = { [weak coordinator = context.coordinator] range, color in
        coordinator?.highlight(range, color: color)
      }
      textView.highlightColors = { [weak coordinator = context.coordinator] in
        coordinator?.highlightColors ?? HighlightColor.allCases
      }
      textView.clickedText = { [weak coordinator = context.coordinator] event in
        coordinator?.clickedText(event)
      }

      let host = NSHostingController(
        rootView: context.coordinator.hostedHeader(inputs.header, in: environment))
      textView.addSubview(host.view)
      textView.header = host.view

      let scroll = ReaderScrollView()
      scroll.documentView = textView
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      scroll.willScroll = { [weak coordinator = context.coordinator] in
        coordinator?.takeLead()
      }

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
      context.coordinator.drive(inputs.controller)
      return scroll
    }

    func updateNSView(_ scroll: ReaderScrollView, context: Context) {
      inputs.apply(to: context.coordinator, environment: environment, width: width)
      context.coordinator.apply(
        settings, in: appearance, outlinesEveryChip: outlinesEveryChip)
      context.coordinator.setHighlights(highlights)
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
      coordinator.releaseController()
    }
  }
#endif
