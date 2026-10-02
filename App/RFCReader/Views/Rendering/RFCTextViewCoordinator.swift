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
/// navigating away would persist the section before last. `ReadingPositionKeeper`
/// reads this instead: it is written the moment the anchor is computed.
final class VisibleAnchorBox {
  var anchor: String?
  /// The reader's line, as a place that survives a rebuild: what the reading
  /// position saves (#322). Nil at the top of the document.
  var place: ReadingPlace?
  /// Whether the top of the viewport is ahead of section one, which `anchor`
  /// reports as section one.
  var isAheadOfSections = false
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
      engine.textView = textView
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
  /// hosting controller — a card's or a document's — must outlive the
  /// `UITargetedPreview` that wraps its view.
  var referencePreviewHost: PlatformHostingController<AnyView>?

  /// What every hosting controller the coordinator builds is given — the header's,
  /// and a reference preview's on both platforms — since each sits outside SwiftUI's
  /// environment chain; see `ReaderEnvironment`.
  var environment: ReaderEnvironment?

  var onVisibleAnchorChange: (String) -> Void = { _ in }
  var onScrollHandled: () -> Void = {}
  var onLink: (URL, LinkActivation) -> Bool = { _, _ in false }
  /// See `RFCTextView.bibliography`.
  var bibliography: [ReferenceGroup] = []
  /// The document on screen; see `RFCTextView.documentID`.
  var documentID: DocumentID?
  /// The quote Copy as Quote puts on the pasteboard for `range` of the reader's text,
  /// or nil when nothing is selected (#186); see `QuoteCitation`.
  func quote(of range: NSRange) -> QuoteCitation.Quote? {
    guard let documentID, let built else { return nil }
    return QuoteCitation.quote(of: range, in: built, document: documentID)
  }
  /// See `RFCTextView.onSelectionChange`.
  var onSelectionChange: (Bool) -> Void = { _ in }
  /// See `RFCTextView.onChoosePresentation`.
  var onChoosePresentation: ((PresentationKey, PresentationChoices.Presentation) -> Void)?
  /// What `onSelectionChange` was last told, so a selection dragged across the text
  /// reports once rather than on every character.
  private var reportedSelection: Bool?

  /// Tells the view whether anything is selected: whenever the selection changes, and
  /// after an install, which may clear it without saying so. Deferred for the reason
  /// `onVisibleAnchorChange` is: installing reports from inside SwiftUI's update.
  /// macOS only, where Edit ▸ Copy as Quote observes it; on iOS the item is in the
  /// selection's own edit menu (#186).
  func reportSelection() {
    #if !canImport(UIKit)
      guard let textView else { return }
      let hasSelection = textView.selectedRange().length > 0
      guard hasSelection != reportedSelection else { return }
      reportedSelection = hasSelection
      Task { self.onSelectionChange(hasSelection) }
    #endif
  }
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
  ///
  /// With the coordinator, which owns what it reports until it withdraws it through
  /// `onToolbarTitleReleased` in `releaseDocument()` (#281): the reader is made per
  /// document, and the last one's teardown can come after the next one's report.
  var onToolbarTitle: (ToolbarTitleState, _ reader: AnyObject) -> Void = { _, _ in }
  var onToolbarTitleReleased: (_ reader: AnyObject) -> Void = { _ in }
  var heading: HeadingBox?
  var lastToolbarTitle: ToolbarTitleState?

  #if canImport(UIKit)
    /// Whether the bars are out of the way on iPhone; see `ReaderChrome`. Driven by
    /// the text view's scrolls and taps, and reported through `onChromeHidden`.
    var chrome = ReaderChrome()
    /// Told when `chrome` hides or shows the bars. Deferred, as
    /// `onVisibleAnchorChange` is: a jump reports from inside SwiftUI's update.
    var onChromeHidden: (Bool) -> Void = { _ in }
    private var reportedChromeHidden = false
    /// The tap that shows and hides the bars, told apart from the text view's own
    /// recognizers in the gesture delegate.
    weak var chromeTap: UITapGestureRecognizer?
    /// Whether the text had a selection when the tap began, or was still moving
    /// after a flick: that tap clears the selection or stops the scroll, and is not
    /// one for the bars.
    private var tapIsNotForTheBars = false
    /// Where that tap touched, in the text view's content. Taken when it begins,
    /// because the tap is recognized only after a double tap has failed, and by
    /// then a link it followed may have scrolled the text away from under it.
    private var chromeTapPoint = CGPoint.zero
    /// The finger's drag on the text, from the moment it begins until the scroll
    /// it started stops: a pan moves the bars, a drag of the scroll indicator does
    /// not (`ReaderChrome.Drag`).
    private var drag: ReaderChrome.Drag?
  #endif

  /// Where section tracking last put the reader, written the moment it is computed.
  /// `visibleAnchor` in `DocumentView` is the observable copy and lags this by a
  /// main-actor hop, which `onDisappear` cannot afford to wait for.
  var lastVisibleAnchor: VisibleAnchorBox?

  var built: BuiltDocument?
  /// The anchors tracking may report. The full index covers *every* anchor —
  /// paragraphs, figures, tables, reference rows — because `scroll(to:)` has to
  /// reach all of them, but every consumer of the reader's visible anchor resolves
  /// it with `RFCDocument.section(anchor:)`, so reporting a paragraph anchor would
  /// silently break all of them. The builder marks which entries are sections; this
  /// is just that subset.
  var sectionIndex = AnchorIndex([])
  var lastReportedAnchor: String?
  /// The reader's geometry under viewport layout; see `ReaderLayoutEngine`.
  let engine = ReaderLayoutEngine()
  var laidOutColumn: CGFloat?
  /// Tracked separately from the column, because above the breakpoint the two move
  /// independently: the column pins at the ideal measure and the gutter takes the
  /// whole resize. The inset is the gutter, so the gutter is what invalidates it.
  var laidOutGutter: CGFloat?
  var laidOutHeaderHeight: CGFloat?

  /// The header as hosted: given `environment`, and on iOS with a tap on its blank
  /// space for the bars.
  func hostedHeader(_ header: AnyView, in environment: ReaderEnvironment) -> AnyView {
    #if canImport(UIKit)
      AnyView(
        header
          .contentShape(.rect)
          .onTapGesture { [weak self] in self?.tappedHeader() }
          .readerEnvironment(environment))
    #else
      AnyView(header.readerEnvironment(environment))
    #endif
  }

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

  /// Hit-tests a point in text-container coordinates down to a character offset,
  /// fragment → line → glyph, or nil beside the text. `NSTextView`'s older
  /// `characterIndex(for:)` goes through the TextKit 1 compatibility shim and is
  /// unreliable on a view built `usingTextLayoutManager: true`, and `UITextView`'s
  /// `closestPosition(to:)` snaps a point beside the text onto the nearest
  /// character; this walks the same TextKit 2 object graph `RFCTextLayoutFragment`
  /// draws against, in reverse.
  func characterOffset(atContainerPoint containerPoint: CGPoint) -> Int? {
    guard let layout = textView?.textLayoutManager,
      let fragment = layout.textLayoutFragment(for: containerPoint)
    else { return nil }
    let fragmentStart = layout.offset(of: fragment.rangeInElement.location)
    guard fragmentStart >= 0 else { return nil }
    let pointInFragment = CGPoint(
      x: containerPoint.x - fragment.layoutFragmentFrame.minX,
      y: containerPoint.y - fragment.layoutFragmentFrame.minY
    )
    return FragmentGeometry.characterOffset(
      in: fragment.textLineFragments,
      fragmentStart: fragmentStart,
      at: pointInFragment
    )
  }

  // MARK: - References

  /// The cross reference at this absolute character offset, and its whole
  /// extent. Shared by the iOS long-press lookup and the macOS hover hit test
  /// below; the lookup itself is `NSAttributedString.reference(at:)`.
  func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.reference(at: offset)
  }

  /// The link a reference's runs carry. Read from the storage rather than from
  /// what the platform says was pressed: a chip's leading glyph is an attachment,
  /// which UIKit reports as one, not as the link it is part of.
  func link(at offset: Int) -> URL? {
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
  func preview(for reference: CrossReference) -> ReferencePreview? {
    guard let library = environment?.library else { return nil }
    switch reference.target {
    case .document:
      return ReferencePreview(
        reference: reference, library: library, kind: bibliography.kind(of: reference.target))
    // A section of an entry outside the series previews the entry (#473).
    case .anchor(let anchor), .entrySection(let anchor, _, _, _):
      if let heading = built?.anchors.heading(of: anchor) {
        return ReferencePreview(reference: reference, library: library, heading: heading)
      }
      return bibliography.entry(anchor: anchor).map {
        ReferencePreview(
          reference: reference, library: library, entry: $0,
          kind: bibliography.kind(of: reference.target))
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
      // A figure is an item for its long press alone: a tap on it is a tap on text,
      // which `chromeTap` takes for the bars. Not nil: for an item with no primary
      // action UIKit opens the menu on a tap, and that took the tap from the bars.
      if case .tag = textItem.content { return UIAction { _ in } }
      let offset = textItem.range.location
      // A backlink chip goes nowhere: it lists what refers to its section.
      if backlinkChip(at: offset) != nil {
        return UIAction(title: defaultAction.title, image: defaultAction.image) { [weak self] _ in
          self?.showBacklinks(at: offset)
        }
      }
      guard let url = link(at: offset), let documentID,
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
      if case .tag = textItem.content { return figureMenu(for: textItem, in: textView) }
      // A backlink chip's link is ours alone, and nothing in the default menu —
      // Copy Link, Share — means anything for it.
      if backlinkChip(at: textItem.range.location) != nil { return nil }
      // `UITextItem.range` is a plain `NSRange` — already the absolute character
      // offset `reference(at:)` wants, no `NSTextLocation` translation needed.
      guard let environment, let documentID,
        let (box, range) = reference(at: textItem.range.location),
        let url = link(at: range.location),
        let target = LinkPreview.resolve(
          box.reference, linkedTo: url, from: documentID, in: environment.library.index)
      else { return .init(menu: defaultMenu) }
      let host: UIHostingController<AnyView>
      switch target {
      case .card:
        guard let preview = preview(for: box.reference) else { return .init(menu: defaultMenu) }
        host = UIHostingController(rootView: AnyView(preview.readerEnvironment(environment)))
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
        let preview = DocumentPreview(
          library: environment.library, id: id, place: place, size: size
        ) {}
        host = UIHostingController(rootView: AnyView(preview.readerEnvironment(environment)))
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
          url, from: documentID, in: environment.library.index, bibliography: bibliography),
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
      followChrome(scrollView)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      drag = ReaderChrome.Drag(
        offset: scrollView.contentOffset.y,
        finger: scrollView.panGestureRecognizer.translation(in: scrollView).y)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if decelerate {
        drag?.lifted()
      } else {
        drag = nil
      }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      drag = nil
    }
  }

  // MARK: - The bars on iPhone

  extension RFCTextViewCoordinator: UIGestureRecognizerDelegate {
    /// Whether the bars may go at all; see `ReaderChrome.isEnabled`.
    func setChromeEnabled(_ enabled: Bool) {
      guard chrome.isEnabled != enabled else { return }
      chrome.isEnabled = enabled
      reportChrome()
    }

    private func followChrome(_ scrollView: UIScrollView) {
      let offset = scrollView.contentOffset.y
      let finger = scrollView.panGestureRecognizer.translation(in: scrollView).y
      // Not `isDragging`, which can stay set while a flick decelerates: the finger
      // is off the glass then, and the flick's drag is still the one scrolling.
      let touching = scrollView.isTracking
      drag = .following(drag, offset: offset, finger: finger, touching: touching)
      let insets = scrollView.adjustedContentInset
      chrome.scrolled(
        ReaderChrome.Scroll(
          offset: offset, topInset: insets.top, bottomInset: insets.bottom,
          contentHeight: scrollView.contentSize.height,
          viewportHeight: scrollView.bounds.height,
          isUserDriven: drag?.isUserDriven(
            touching: touching, decelerating: scrollView.isDecelerating,
            engineMoving: engine.keeper.isEngineMoving) ?? false,
          isFlinging: scrollView.isDecelerating && !scrollView.isTracking))
      reportChrome()
    }

    func reportChrome() {
      let hidden = chrome.isHidden
      guard hidden != reportedChromeHidden else { return }
      reportedChromeHidden = hidden
      // Now, not with the report: the safe area follows the bars, which follow the
      // report, and the top inset must already know to hold.
      (textView as? ReaderTextView)?.barsHidden = hidden
      Task { self.onChromeHidden(hidden) }
    }

    /// A tap on the text brings the bars back, or puts them away. Not a tap on a
    /// link or a chip, which follows it; not one on the header, which takes its own
    /// (`tappedHeader()`); and not one that clears a selection or stops a flick.
    @objc func tappedText(_ tap: UITapGestureRecognizer) {
      guard tap.state == .ended, !tapIsNotForTheBars, let textView else { return }
      let point = chromeTapPoint
      if headerHost?.view.frame.contains(point) == true { return }
      let inset = textView.textContainerInset
      let containerPoint = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
      if let offset = characterOffset(atContainerPoint: containerPoint), link(at: offset) != nil {
        return
      }
      chrome.tapped()
      reportChrome()
    }

    /// A tap on the header's blank space, as a tap on the text is. Told by a tap
    /// gesture on the header's root (`hostedHeader(_:in:)`), which the header's author
    /// chips and banner links take precedence over, being SwiftUI gestures below
    /// it: a tap on one of them does only what it does.
    func tappedHeader() {
      guard !tapIsNotForTheBars else { return }
      chrome.tapped()
      reportChrome()
    }

    /// Beside the text view's own recognizers, so a tap on a link still follows it
    /// and a long press still previews it.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // The delegate of `chromeTap` alone, so always that one.
      true
    }

    /// After a double tap has failed: the first tap of one that selects a word is
    /// not a tap for the bars.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      guard gestureRecognizer === chromeTap,
        let tap = otherGestureRecognizer as? UITapGestureRecognizer
      else { return false }
      return tap.numberOfTapsRequired > 1
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
    ) -> Bool {
      if gestureRecognizer === chromeTap, let textView {
        tapIsNotForTheBars = textView.selectedRange.length > 0 || textView.isDecelerating
        chromeTapPoint = touch.location(in: textView)
      }
      return true
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
      // A backlink chip goes nowhere: it lists what refers to its section.
      if backlinkChip(at: charIndex) != nil {
        showBacklinks(at: charIndex)
        return true
      }
      guard let url = Self.url(fromLink: link) else { return false }
      // Read here rather than passed down from the view: by the time SwiftUI's
      // `openURL` sees the link, the click that carried the modifiers is gone.
      return onLink(url, .current)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      reportSelection()
    }

    /// A context menu ends a dwell in progress, which would otherwise open a card
    /// under the menu or the moment it closes.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int)
      -> NSMenu?
    {
      hover.send(.contextMenu)
      // A backlink chip's link is ours alone, and Copy Link would copy a URL
      // nothing else can open; the rest of the menu stays.
      if backlinkChip(at: charIndex) != nil { return BacklinkMenu.withoutCopyLink(menu) }
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

    /// Detaches the text view from its text container, so what AppKit keeps of the
    /// view after it is gone no longer holds the document (#356). Called from
    /// `dismantleNSView`.
    ///
    /// A TextKit 2 text view's private subviews outlive it on macOS 27: the content
    /// view that draws the text, and the viewport element view of every fragment on
    /// screen. Measured with `heap` after ten opens: one text view, but eleven content
    /// views, layout managers and storages, and 27,803 layout fragments, 35 MB a
    /// document, never freed, and every build from the eighth open on 5 to 10 times
    /// slower. A plain `NSTextView` in a small program leaks the same way, so it is
    /// AppKit's, not this reader's: the subviews stay registered with the notification
    /// center, by blocks that capture them.
    ///
    /// The subviews cannot be released from here, but what they reach can. Without
    /// its container the content view no longer reaches the layout manager, which
    /// takes the storage, the fragments and every attribute they drew with. Measured
    /// in the same program: storages and content views all freed, and a dozen
    /// fragments left per view, the ones on screen when it went. Emptying the storage
    /// instead left the layout manager and storage behind.
    ///
    /// Detached through the container, the way AppKit documents it: `NSTextView`'s own
    /// `textContainer` setter is not to be called directly, and measured in the same
    /// program both free the same. The scroll observer goes too, so a viewport left
    /// without a layout manager reports nothing to the window's toolbar title, which
    /// the next reader already owns. And what it said of the title goes with it: its
    /// header is gone, and only the next reader, or a mode without one, says more.
    func releaseDocument() {
      engine.stop()
      NotificationCenter.default.removeObserver(
        self, name: NSView.boundsDidChangeNotification, object: nil)
      textView?.textContainer?.textView = nil
      onToolbarTitleReleased(self)
      // The window's models, which nothing that outlives the window should hold.
      environment = nil
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
