import RFCKit
import RFCReaderKit
import SwiftUI
import Synchronization

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
final class RFCTextViewCoordinator: NSObject {
  /// The text view this coordinator drives. Weak: SwiftUI owns both, and the view
  /// outlives no part of this. AppKit's hover preview needs a tracking area the
  /// moment the view exists, hence the `didSet`; UIKit needs no such setup.
  weak var textView: PlatformTextView? {
    didSet {
      engine.textView = textView
      engine.didLayOut = { [weak self] in self?.layOutNoteMarkers() }
      #if canImport(UIKit)
        // The reader's link color, which `makeUIView` sets in place of the system
        // tint (#317).
        let attributes = LinkAttributes(
          attributes: textView?.linkTextAttributes ?? [:], caption: [:])
      #else
        setUpHover()
        // A backlink caption opens a list beside it, as a control does, under the
        // ordinary pointer rather than a link's pointing hand. Made here, on the
        // main thread, where AppKit makes cursors.
        let attributes = LinkAttributes(
          attributes: textView?.linkTextAttributes ?? [:], caption: [.cursor: NSCursor.arrow])
      #endif
      linkAttributes.withLock { $0 = attributes }
      #if !canImport(UIKit)
        systemSelection = textView?.selectedTextAttributes ?? [:]
      #endif
      setUpAccessibilityRotors()
    }
  }

  #if !canImport(UIKit)
    /// The text view's own selection attributes, which a page theme's selection
    /// color replaces the background of, and the automatic palette restores.
    private var systemSelection: [NSAttributedString.Key: Any] = [:]
  #endif

  /// The text view's own link attributes, taken when it is handed over, after it is
  /// configured. A layout manager whose delegate answers for a link's rendering
  /// stops reading them and starts from TextKit's (link-colored and underlined), so
  /// the delegate starts from these instead (#584). Behind a lock because TextKit
  /// may ask off the main thread.
  nonisolated let linkAttributes = Mutex(LinkAttributes(attributes: [:], caption: [:]))

  /// The hung heading number under the pointer (#433), which the link's rendering
  /// lights up. Behind a lock for the reason `linkAttributes` is.
  nonisolated let hoveredSectionNumber = Mutex<NSRange?>(nil)

  /// The colors this reader draws its page, links and decoration in: the page theme
  /// for the appearance it is drawn in (#703, #704). A box the fragments keep, so
  /// that `apply(_:in:outlinesEveryChip:)` recolors what is already laid out
  /// rather than laying it out again.
  nonisolated let paletteBox = ReaderPaletteBox()

  /// Draws the page, the text and the decoration in the theme `settings` choose for
  /// `appearance` from now on, and redraws what is on screen if it changed. Never a
  /// layout: a palette is the draw-time half of the settings, and costs neither a
  /// rebuild nor the reader's place. So is Increase Contrast, which outlines every
  /// chip (#457).
  func apply(
    _ settings: ReaderSettings, in appearance: PaletteAppearance, outlinesEveryChip: Bool
  ) {
    // Before the redraw, which resolves the text's colors to the themes chosen.
    ReaderPalette.choose(light: settings.lightPalette, dark: settings.darkPalette)
    let palette = settings.palette(for: appearance)
    guard paletteBox.replace(with: palette, outlinesEveryChip: outlinesEveryChip), let textView
    else { return }
    // The laid-out fragments are rendered again, which reads the box, and their
    // text resolves its colors again, to the theme chosen
    // (`ReaderPalette.themedText`).
    engine.redraw()
    drawPage(palette, in: textView)
    if let header, let environment {
      headerHost?.rootView = hostedHeader(header, in: environment)
    }
  }

  /// The page behind the text, and on macOS the selection, in `palette`'s colors:
  /// none and the system's under the automatic palette, as the reader always had.
  private func drawPage(_ palette: ReaderPalette, in textView: PlatformTextView) {
    #if canImport(UIKit)
      textView.backgroundColor = palette.pageBackground ?? .clear
    #else
      // The scroll view rather than the text view, which is only as tall as the
      // text and stops short of a short document's end.
      if let scroll = textView.enclosingScrollView {
        scroll.backgroundColor = palette.pageBackground ?? .clear
        scroll.drawsBackground = palette.pageBackground != nil
      }
      var selection = systemSelection
      if let highlight = palette.selection { selection[.backgroundColor] = highlight }
      textView.selectedTextAttributes = selection
    #endif
  }

  /// A text view's link attributes, the same for a link on a card (#694), and what
  /// a backlink caption is drawn with on top of them, handed across threads.
  /// `@unchecked Sendable` because the dictionaries are made once and never written
  /// to, and their values, colors and cursors, are only read to draw.
  nonisolated struct LinkAttributes: @unchecked Sendable {
    let attributes: [NSAttributedString.Key: Any]
    let card: [NSAttributedString.Key: Any]
    let caption: [NSAttributedString.Key: Any]

    init(attributes: [NSAttributedString.Key: Any], caption: [NSAttributedString.Key: Any]) {
      self.attributes = attributes
      self.card = LinkRendering.cardAttributes(attributes)
      self.caption = caption
    }
  }

  /// Retained deliberately: `UIHostingController().view` does not keep its
  /// controller alive, and a released controller takes trait propagation — and so
  /// Dynamic Type — with it.
  var headerHost: PlatformHostingController<AnyView>? {
    didSet { engine.header = headerHost?.view }
  }

  /// What the hosted header currently displays; see `ReaderInputs.apply`.
  var headerIdentity: DocumentHeaderView.Identity?
  /// The header last handed over, hosted again when the palette changes.
  var header: AnyView?

  /// Retained for the same reason as `headerHost`: the iOS long-press preview's
  /// hosting controller — a card's or a document's — must outlive the
  /// `UITargetedPreview` that wraps its view.
  var referencePreviewHost: PlatformHostingController<AnyView>?

  /// What every hosting controller the coordinator builds is given — the header's,
  /// and a reference preview's on both platforms — since each sits outside SwiftUI's
  /// environment chain; see `ReaderEnvironment`.
  var environment: ReaderEnvironment?

  var onLink: (URL, LinkActivation) -> Bool = { _, _ in false }
  /// See `RFCTextView.bibliography`.
  var bibliography: [ReferenceGroup] = []
  /// The document on screen; see `RFCTextView.document`.
  var document: ReadableDocument?
  /// The RFC on screen: what a copied link names and a reference's preview is
  /// resolved from. Nil for a draft (#728), whose quotes and previews are an RFC's
  /// only.
  var documentID: DocumentID? { document?.rfc }
  /// What a copy cites; see `ReaderInputs.citing`.
  var citing: DocumentID?
  /// The quote Copy as Quote puts on the pasteboard for `range` of the reader's text,
  /// or nil when nothing is selected (#186); see `QuoteCitation`. Cited as Settings
  /// say (#712).
  func quote(of range: NSRange) -> QuoteCitation.Quote? {
    guard let citing, let built else { return nil }
    return QuoteCitation.quote(
      of: range, in: built, document: citing, cited: environment?.library.citedDocument(citing),
      settings: ReaderSettings(defaults: .standard))
  }

  /// Copy Citation's citation of the section `range` starts in, in the style Settings
  /// chose (#712), or nil where the index has no entry to cite from.
  func citation(of range: NSRange) -> String? {
    guard let citing, let built, let cited = environment?.library.citedDocument(citing) else {
      return nil
    }
    let settings = ReaderSettings(defaults: .standard)
    return DocumentActions.citation(
      cited, section: QuoteCitation.section(of: range, in: built), style: settings.citationStyle,
      site: settings.linkSite)
  }

  /// The URL a copy links `link` to on `site` (#778, #712): one anyone can open, or
  /// nil where the reader has none to hand out.
  func publicURL(for link: URL, site: LinkSite) -> URL? {
    guard let documentID else { return nil }
    return LinkCopy.publicURL(
      for: link, from: documentID, in: environment?.library.index, bibliography: bibliography,
      site: site)
  }
  /// See `RFCTextView.onChoosePresentation`.
  var onChoosePresentation: ((PresentationKey, PresentationChoices.Presentation) -> Void)?
  /// Tells the controller whether anything is selected: whenever the selection
  /// changes, and after an install, which may clear it without saying so. macOS only,
  /// where Edit ▸ Copy as Quote observes it; on iOS the item is in the selection's own
  /// edit menu (#186).
  func reportSelection() {
    #if !canImport(UIKit)
      guard let textView else { return }
      controller?.reportSelection(textView.selectedRange().length > 0)
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
  /// What the toolbar's title was last told; see `updateToolbarTitle()`.
  var lastToolbarTitle: ToolbarTitleState?
  /// See `ReaderInputs.isShown`.
  var isShown = true

  #if canImport(UIKit)
    /// The bars on iPhone, which reading on puts away; see `ReaderBars`.
    let bars = ReaderBars()
  #endif

  /// What the reader reports to, and is asked through: the view's.
  var controller: ReaderController?
  /// The reading this reader scrolls together with another one in, side by side
  /// (#187); see `RFCTextViewCoordinator+Coupling`.
  var coupling: ScrollCoupling?
  /// Set while this reader follows the other one; its scroll reports wait for
  /// `follow(_:)` to report the place it was put at.
  var isFollowing = false

  var built: BuiltDocument? {
    didSet {
      hasCopyButtons =
        built.map { !$0.text.copyButtons(in: NSRange(location: 0, length: $0.text.length)).isEmpty }
        ?? false
    }
  }
  /// Whether the document shows a copy button anywhere (macOS), so that a document
  /// without one never looks for them in its viewport (#724).
  private(set) var hasCopyButtons = false
  /// The anchors tracking may report. The full index covers *every* anchor —
  /// paragraphs, figures, tables, reference rows — because `scroll(to:)` has to
  /// reach all of them, but every consumer of the reader's visible anchor resolves
  /// it with `RFCDocument.section(anchor:)`, so reporting a paragraph anchor would
  /// silently break all of them. The builder marks which entries are sections; this
  /// is just that subset.
  var sectionIndex = AnchorIndex([])
  /// The reader's geometry under viewport layout; see `ReaderLayoutEngine`.
  let engine = ReaderLayoutEngine()
  /// Skips the paragraphs the reading mode folds; the content storage's delegate.
  let foldingDelegate = FoldingDelegate()
  /// The reading mode and expanded sections last applied (#698).
  var folding = Folding()
  /// What folding needs of the installed build: the build's own (#723).
  var foldingIndex: FoldingIndex? { built?.foldingIndex }
  /// What VoiceOver says after each disclosed heading, for the folding and index it
  /// was worked out for: asked on every line VoiceOver reads (`spokenStates()`).
  var spokenStatesKept: KeptSpokenStates?

  struct KeptSpokenStates {
    let folding: Folding
    /// The build's text, held and compared by reference: a new build can be
    /// allocated where a freed one was, and an identifier would take it for that one.
    let text: NSAttributedString
    let said: [Int: String]
  }
  /// A folding this coordinator changed itself and asked the scene for, which the
  /// scene has not caught up with yet; see `FoldingEcho`.
  var foldingEcho = FoldingEcho()
  /// The document's requirements, which Implementer bands (#700).
  var requirements: [Requirement] = []
  /// Where the requirements are in the installed build: found in Implementer only,
  /// once per build and requirements.
  var requirementBands: RequirementBands?
  /// Finding the bands, off the main actor.
  var bandsTask: Task<Void, Never>?
  /// The document's highlights (#522), which this text view draws where the
  /// installed build places them.
  var highlights: [AnnotationSnapshot.HighlightEntry] = []
  /// Where they are in the installed build.
  var highlightPlacement = HighlightPlacement.none
  /// The document's notes (#523), and where the installed build places them.
  var notes: [AnnotationSnapshot.NoteEntry] = []
  var notePlacement = NotePlacement.none
  /// The gutter markers standing now, and their views, one each.
  var noteMarkers: [FragmentGeometry.NoteMarker] = []
  #if canImport(UIKit)
    var noteMarkerViews: [UIView] = []
    /// The note editor's sheet, while it is up.
    var noteEditorHost: UIViewController?
  #else
    var noteMarkerViews: [NSView] = []
    /// The note editor's popover, while it is open.
    var notePopover: NSPopover?
  #endif
  /// Placing them, off the main actor.
  var highlightsTask: Task<Void, Never>?
  /// The reader's keys (#711), holding the first key of a vim pair.
  var keys = ReaderKeys()
  /// The link the keyboard's focus is on (#711), which Return follows; nil for none.
  /// The ring's own, so the two cannot disagree.
  var focusedLink: NSRange? { foldingDelegate.focusedLink }
  #if !canImport(UIKit)
    /// A click in a highlight, waiting out the double-click interval before its
    /// popover opens, so it never opens on the way to a double-click.
    var highlightClick: Task<Void, Never>?
    /// The popover of the highlight last clicked, while it is open.
    var highlightPopover: NSPopover?
  #endif
  var laidOutColumn: CGFloat?
  /// Tracked separately from the column, because above the breakpoint the two move
  /// independently: the column pins at the ideal measure and the gutter takes the
  /// whole resize. The inset is the gutter, so the gutter is what invalidates it.
  var laidOutGutter: CGFloat?
  var laidOutHeaderHeight: CGFloat?
  var laidOutHang: CGFloat?
  /// How far the container reaches into the leading gutter for the hang
  /// (`ReaderLayout.containerReach`), which moves the column when it changes.
  var laidOutReach: CGFloat?

  /// The header as hosted: given `environment`, in the page theme's text and link
  /// colors (#704), and on iOS with a tap on its blank space for the bars.
  func hostedHeader(_ header: AnyView, in environment: ReaderEnvironment) -> AnyView {
    let themed = AnyView(header.readerPalette(paletteBox.palette))
    #if canImport(UIKit)
      return AnyView(
        themed
          .contentShape(.rect)
          .onTapGesture { [weak self] in self?.bars.tappedHeader() }
          .readerEnvironment(environment))
    #else
      return AnyView(themed.readerEnvironment(environment))
    #endif
  }

  // MARK: - Accessibility

  /// The headings, links and diagrams rotors search — cached by
  /// `deriveAccessibilityItems()` in `RFCTextViewCoordinator+Accessibility.swift`.
  var accessibilityHeadings: [AccessibilityRotorItem] = []
  var accessibilityLinks: [AccessibilityRotorItem] = []
  var accessibilityDiagrams: [AccessibilityRotorItem] = []
  /// The Highlights rotor's stops (#522), from the placement drawn.
  var accessibilityHighlights: [AccessibilityRotorItem] = []

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
    guard let lines = FragmentLines(fragment, in: layout) else { return nil }
    let pointInFragment = CGPoint(
      x: containerPoint.x - fragment.layoutFragmentFrame.minX,
      y: containerPoint.y - fragment.layoutFragmentFrame.minY
    )
    return FragmentGeometry.characterOffset(in: lines, at: pointInFragment)
  }

  /// Where the paragraph laid out at the height of `containerPoint` starts: what a
  /// click or tap in the gutter beside a disclosure toggles. By its layout fragment,
  /// not a character, since an aside's caption is set in from the column's edge the
  /// gutter point is on (#700).
  func paragraphStart(atContainerPoint containerPoint: CGPoint) -> Int? {
    guard let layout = textView?.textLayoutManager,
      let fragment = layout.textLayoutFragment(for: containerPoint)
    else { return nil }
    let start = layout.offset(of: fragment.rangeInElement.location)
    return start >= 0 ? start : nil
  }

  // MARK: - References

  /// The cross reference at this absolute character offset, and its whole
  /// extent. Shared by the iOS long-press lookup and the macOS hover hit test
  /// below; the lookup itself is `NSAttributedString.reference(at:)`.
  func reference(at offset: Int) -> (box: ReferenceBox, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.reference(at: offset)
  }

  // MARK: - Glosses (#396)

  /// The gloss at this absolute character offset, and its whole extent: what its
  /// card is anchored to, on hover and force click on macOS and long press on iOS.
  func gloss(at offset: Int) -> (box: GlossBox, range: NSRange)? {
    textView?.textLayoutManager?.attributedText?.gloss(at: offset)
  }

  /// Go to Definition or Go to Expansion for `gloss`, from its menu: the anchor of
  /// the definition, or of the section that expands the abbreviation, followed here,
  /// as a link to it would be, so Back returns. Nil for a definition with no anchor,
  /// which has nowhere to go.
  func followGloss(of gloss: Gloss) -> (() -> Void)? {
    guard let anchor = gloss.anchor,
      let url = ReaderLinkScheme.url(anchor, scheme: ReaderLinkScheme.anchorScheme)
    else { return nil }
    return { [weak self] in _ = self?.onLink(url, .here) }
  }

  /// The link a reference's runs carry. Read from the storage rather than from
  /// what the platform says was pressed: a chip's leading glyph is an attachment,
  /// which UIKit reports as one, not as the link it is part of. Nil past the end,
  /// where a right-click below the last line puts the menu's index.
  func link(at offset: Int) -> URL? {
    guard let text = textView?.textLayoutManager?.attributedText,
      offset >= 0, offset < text.length
    else { return nil }
    return text.attribute(.link, at: offset, effectiveRange: nil).flatMap(
      ReaderLinkScheme.url(fromLink:))
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
      if let definition = built?.grammar.definition(of: anchor) {
        return ReferencePreview(reference: reference, library: library, definition: definition)
      }
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
      // which `ReaderBars` takes for the bars. Not nil: for an item with no primary
      // action UIKit opens the menu on a tap, and that took the tap from the bars.
      if case .tag = textItem.content { return UIAction { _ in } }
      let offset = textItem.range.location
      // A backlink caption goes nowhere: it lists what refers to its section.
      if backlinkCaption(at: offset) != nil {
        return UIAction(title: defaultAction.title, image: defaultAction.image) { [weak self] _ in
          self?.showBacklinks(at: offset)
        }
      }
      // Nor does an errata chip: it lists its section's errata (#387).
      if errataChip(at: offset) != nil {
        return UIAction(title: defaultAction.title, image: defaultAction.image) { [weak self] _ in
          self?.showErrata(at: offset)
        }
      }
      guard let url = link(at: offset), let document,
        LinkDestination.resolve(url, from: document, activation: .here) != .unhandled
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
    /// reader's own menu shows beside it (`referenceMenu`), and a tap on the
    /// preview performs the item's primary action, which follows the reference.
    func textView(
      _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
      if case .tag = textItem.content {
        return glossMenu(for: textItem, in: textView) ?? figureMenu(for: textItem, in: textView)
      }
      // A backlink caption's link is ours alone, and so is an errata chip's: nothing
      // in the default menu — Copy Link, Share — means anything for it.
      if listsRatherThanGoes(at: textItem.range.location) { return nil }
      // A heading's hung number (#433) links to its own heading, which there is no
      // point previewing: only the menu, its Copy and Share handing out the RFC
      // Editor's URL for the section.
      if let number = textView.textLayoutManager?.attributedText?.sectionNumber(
        at: textItem.range.location),
        let url = ReaderLinkScheme.url(number.anchor, scheme: ReaderLinkScheme.anchorScheme)
      {
        guard
          let menu = referenceMenu(
            defaultMenu, for: url, opens: false, from: textView, at: number.range)
        else { return nil }
        return .init(menu: menu)
      }
      // `UITextItem.range` is a plain `NSRange` — already the absolute character
      // offset `reference(at:)` wants, no `NSTextLocation` translation needed.
      let reference = reference(at: textItem.range.location)
      let range = reference?.range ?? textItem.range
      guard let url = link(at: range.location) else { return .init(menu: defaultMenu) }
      // Whatever the preview comes to, the menu is the reader's own: UIKit's would
      // hand out the `rfc://` URL (#763).
      let menu = referenceMenu(defaultMenu, for: url, from: textView, at: range)
      guard let environment, let documentID, let box = reference?.box,
        let target = LinkPreview.resolve(
          box.reference, linkedTo: url, from: documentID, in: environment.library.index)
      else { return menu.map { .init(menu: $0) } }
      let host: UIHostingController<AnyView>
      switch target {
      case .card:
        guard let preview = preview(for: box.reference) else { return menu.map { .init(menu: $0) } }
        host = UIHostingController(rootView: AnyView(preview.readerEnvironment(environment)))
        // Sized here, the way the header host is in `layOut`: the preview is shown
        // at its view's own size, and a hosting controller's view is not sized to
        // its content until something lays it out.
        host.view.frame.size = host.sizeThatFits(
          in: CGSize(width: ReferencePreview.width, height: CGFloat.greatestFiniteMagnitude))
      case .document(let id, let place):
        // Measured against the window, not the text view: the preview is shown
        // over the whole window, whatever the reader's own width.
        guard let window = textView.window else { return menu.map { .init(menu: $0) } }
        let size = LinkPreview.documentSize(fitting: window.bounds.size)
        // The commit is the tap, performed as the primary action; nothing in a
        // context menu's preview is clicked.
        let preview = DocumentPreview(
          library: environment.library, id: id, place: place, size: size
        ) {}
        host = UIHostingController(rootView: AnyView(preview.readerEnvironment(environment)))
        host.view.frame.size = size
      }
      let container = previewView(hosting: host)
      return UITextItem.MenuConfiguration(
        preview: .view(container), menu: menu ?? UIMenu(children: []))
    }

    /// `host`'s view as a long-press preview: a reference's card or document, or a
    /// gloss's card (#396). Opaque, as a context-menu preview's view is expected to
    /// be: none has a background of its own, because on macOS the popover supplies
    /// one. Held until the menu ends (`textItemMenuWillEndFor`).
    func previewView(hosting host: UIHostingController<AnyView>) -> UIView {
      host.view.backgroundColor = .systemBackground
      referencePreviewHost = host
      // UIKit makes the preview view the view of a controller of its own, which
      // raises for a view that is already a controller's: the host's is. So the
      // host's view goes inside a plain one, the way the header host's goes inside
      // the text view.
      let container = UIView(frame: host.view.frame)
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(host.view)
      return container
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
      if !isFollowing { reportVisibleAnchor() }
      bars.scrolled(scrollView, engineMoving: engine.keeper.isEngineMoving)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      takeLead()
      bars.willBeginDragging(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      bars.didEndDragging(willDecelerate: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      bars.didEndDecelerating()
    }
  }

  // MARK: - The bars on iPhone

  extension RFCTextViewCoordinator {
    /// A tap on the text, which brings the bars back or puts them away, unless it is
    /// for something else; see `ReaderChrome.action(for:discloses:isLink:toggles:)`.
    @objc func tappedText(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let textView else { return }
      let point = bars.tapPoint
      let inset = textView.textContainerInset
      let containerPoint = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
      let discloses = folding.mode.discloses
      let tap = ReaderChrome.Tap(
        clearsSelectionOrStopsFling: bars.tapClearsSelectionOrStopsFling,
        isOnHeader: headerHost?.view.frame.contains(point) == true,
        besideDisclosure: discloses
          ? FragmentGeometry.disclosureHit(atContainerPoint: containerPoint)
            .flatMap(paragraphStart(atContainerPoint:))
          : nil,
        character: characterOffset(atContainerPoint: containerPoint))
      let action = ReaderChrome.action(
        for: tap, discloses: discloses,
        isLink: { link(at: $0) != nil },
        toggles: { offset in
          foldingIndex.map { folding.toggling(heading: offset, in: $0) != nil } ?? false
        },
        isHighlighted: { highlightPlacement.marks.highlight(at: $0) != nil })
      switch action {
      case .nothing:
        break
      case .toggleSection(let offset):
        _ = toggleSection(atHeading: offset)
      case .showHighlight(character: let offset):
        showHighlightPopover(at: offset)
      case .toggleBars:
        bars.tapped()
      }
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
      // A backlink caption goes nowhere: it lists what refers to its section.
      if backlinkCaption(at: charIndex) != nil {
        showBacklinks(at: charIndex)
        return true
      }
      // Nor does an errata chip: it lists its section's errata (#387).
      if errataChip(at: charIndex) != nil {
        showErrata(at: charIndex)
        return true
      }
      guard let url = ReaderLinkScheme.url(fromLink: link) else { return false }
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
      return linkMenu(menu, at: charIndex)
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
      if !isFollowing { reportVisibleAnchor() }
      hover.send(.scrolled)
      // A lit number has moved out from under the pointer, and its help tag with it;
      // the next move lights whatever is there now (#433).
      hoverSectionNumber(under: nil)
    }

    /// The next click is a click of its own, not the tail of a force click, and it
    /// ends any dwell. In a link preview's reader it commits the preview.
    func mouseDownInText() -> Bool {
      takeLead()
      // A second click is a double-click's, not the highlight's.
      highlightClick?.cancel()
      highlightClick = nil
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
      controller?.releaseTitle(from: self)
      couple(to: nil, installed: false)
      // The window's models, which nothing that outlives the window should hold.
      environment = nil
      header = nil
    }
  }

#endif

extension RFCTextViewCoordinator: nonisolated NSTextLayoutManagerDelegate {
  // TextKit 2's background-layout design permits this delegate to be called off
  // the main thread; `nonisolated` keeps the conformance honest about that rather
  // than binding it to the main actor, which approachable concurrency would infer
  // for a main-actor type. The bodies read their parameters, the storage as the
  // fragments do while they lay out, and a locked copy of the text view's link
  // attributes, so they need no isolation.
  nonisolated func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    RFCTextLayoutFragment.make(for: textElement, palette: paletteBox)
  }

  /// Every link as the text view draws it, over the storage's color, but a
  /// heading's backlink caption, which keeps the caption's (#584), and a link on a
  /// card, which takes the card's link color (#694). Not `renderingAttributes`,
  /// which are TextKit's and not the text view's.
  nonisolated func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    renderingAttributesForLink link: Any,
    at location: any NSTextLocation,
    defaultAttributes renderingAttributes: [NSAttributedString.Key: Any]
  ) -> [NSAttributedString.Key: Any]? {
    let textView = linkAttributes.withLock { $0 }
    let onCard = textLayoutManager.drawsCard(at: location)
    return LinkRendering.attributes(
      for: link,
      defaults: onCard ? textView.card : textView.attributes,
      caption: textView.caption,
      sectionNumber: textLayoutManager.sectionNumberState(
        at: location, hovered: hoveredSectionNumber.withLock { $0 }),
      palette: paletteBox.palette, onCard: onCard)
  }
}
