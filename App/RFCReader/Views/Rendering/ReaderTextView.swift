import RFCKit
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
  import UniformTypeIdentifiers

  /// The reader's text view, which copies what it means rather than what it holds.
  ///
  /// See `SelectionText`: a chip's symbol lives in the storage as an
  /// object-replacement character and its brackets do not live there at all, so the
  /// characters under a selection are not the text that selection stands for.
  final class ReaderTextView: UITextView {
    /// Whether the bars are hidden, set by the coordinator the moment `ReaderChrome`
    /// decides so, before the safe area follows: the top inset holds at the bars'
    /// height meanwhile (`ReaderChrome.topInset`).
    var barsHidden = false

    /// The reader runs under both bars and the home indicator (`DocumentView` lets
    /// it into the vertical safe areas), so the bars are glass over the text rather
    /// than a solid strip above it. At the top the inset keeps the header clear of
    /// the top bar; at the bottom it is room to scroll the last line clear of the bar
    /// and the home indicator.
    ///
    /// By hand, because `contentInsetAdjustmentBehavior` is `.never`. The top inset
    /// moves `contentOffset`'s origin, so the scroll arithmetic asks for the
    /// viewport through `PlatformTextView+Scrolling`, which measures from the inset's
    /// edge, as the Mac does from the toolbar's. When the top inset changes — the
    /// first layout, a rotation, not the bars going, which it holds through — the
    /// offset moves with it, so the line at the top of the uncovered viewport stays
    /// there: a place restored before the inset arrived is not put under the bar.
    /// The bottom inset changing leaves the offset alone, so the bottom bar going
    /// moves nothing.
    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      let insets = safeAreaInsets
      let top = ReaderChrome.topInset(
        current: contentInset.top, safeArea: insets.top, barsHidden: barsHidden)
      if contentInset.top != top {
        let moved = top - contentInset.top
        contentInset.top = top
        verticalScrollIndicatorInsets.top = top
        contentOffset.y -= moved
      }
      if contentInset.bottom != insets.bottom {
        contentInset.bottom = insets.bottom
        verticalScrollIndicatorInsets.bottom = insets.bottom
      }
    }

    /// A find match or a VoiceOver rotor stop far from the viewport lands on an
    /// estimate under viewport layout; the engine puts it there exactly instead.
    var revealRange: ((NSRange) -> Bool)?

    override func scrollRangeToVisible(_ range: NSRange) {
      if revealRange?(range) == true { return }
      super.scrollRangeToVisible(range)
    }

    /// Told of a key pressed on a hardware keyboard, before it scrolls anything: in
    /// a side-by-side reading, that side leads (#187).
    var willHandleKey: () -> Void = {}

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      willHandleKey()
      super.pressesBegan(presses, with: event)
    }

    /// The quote for a range of the text, from the coordinator (#186).
    var quoteSelection: (NSRange) -> QuoteCitation.Quote? = { _ in nil }
    /// The URL a copy links a link of the text to (`LinkCopy.publicURL`), from the
    /// coordinator, which knows the document (#778).
    var publicURL: (URL) -> URL? = { _ in nil }

    /// Copy as Quote, offered in the edit menu beside Copy (`RFCTextViewCoordinator`).
    func copyAsQuote() {
      guard let quote = quoteSelection(selectedRange) else { return }
      Clipboard.write(.quote(quote), announcing: .quote)
    }

    /// The selection as the Mac copies it (#778): rich text and HTML as well as plain
    /// text, with a reference's link one that opens outside the reader.
    override func copy(_ sender: Any?) {
      guard let attributed = attributedText, let range = selectedTextRange, !range.isEmpty else {
        super.copy(sender)
        return
      }
      let selection = NSRange(
        location: offset(from: beginningOfDocument, to: range.start),
        length: offset(from: range.start, to: range.end)
      )
      guard selection.location != NSNotFound, NSMaxRange(selection) <= attributed.length else {
        super.copy(sender)
        return
      }
      Clipboard.write(
        .selection(attributed.attributedSubstring(from: selection), publicURL: publicURL))
    }
  }

#elseif canImport(AppKit)
  import AppKit

  /// The reader's text view, which copies what it means rather than what it holds.
  ///
  /// See `SelectionText`: a chip's symbol lives in the storage as an
  /// object-replacement character and its brackets do not live there at all, so the
  /// characters under a selection are not the text that selection stands for.
  final class ReaderTextView: NSTextView {
    /// Posted, with the view as the object, when a live resize of the view ends: the
    /// window's, or a drag of a split view's divider beside it, of which the window
    /// says nothing. The background layout waits for it (`ReaderLayoutEngine`).
    static let didEndLiveResizeNotification = Notification.Name("ReaderTextViewDidEndLiveResize")

    override func viewDidEndLiveResize() {
      super.viewDidEndLiveResize()
      NotificationCenter.default.post(name: Self.didEndLiveResizeNotification, object: self)
    }

    /// Force click on a reference previews it; answers whether it did. Set by the
    /// representable, and a closure rather than the coordinator so this view stays
    /// about text.
    var quickLookReference: (NSEvent) -> Bool = { _ in false }
    /// The link, and the character it is on, that a click at a mouse-down follows
    /// when the mouse-down is on a reference, or nil anywhere else.
    var referenceLink: (NSEvent) -> (link: Any, characterIndex: Int)? = { _ in nil }
    /// Copies a link to the heading whose hung number an Option-click is on (#433),
    /// answering whether there was one.
    var copySectionLink: (NSEvent) -> Bool = { _ in false }
    /// Told where the pointer is, or nil when it leaves, so a hung number under it
    /// can light up.
    var hoverSectionNumber: (NSEvent?) -> Void = { _ in }
    /// Copies a code block for a click on its copy button, answering whether there
    /// was one.
    var copyCode: (NSEvent) -> Bool = { _ in false }

    /// How far the text container reaches left into the gutter, for the headings'
    /// hung numbers (#433). AppKit's inset is symmetric, so the reach is taken off
    /// the container's origin instead.
    var leadingHang: CGFloat = 0 {
      didSet {
        if leadingHang != oldValue { invalidateTextContainerOrigin() }
      }
    }

    override var textContainerOrigin: NSPoint {
      let origin = super.textContainerOrigin
      return NSPoint(x: origin.x - leadingHang, y: origin.y)
    }
    /// Opens or closes the section of a heading clicked in the outline (#698);
    /// answers whether the click was on one.
    var toggleSection: (NSEvent) -> Bool = { _ in false }
    /// Where the pointer is the arrow over the text in view, in this view's
    /// coordinates (`resetCursorRects()`): where a click would toggle a heading's
    /// section in the outline, and a code block's copy button (#724).
    var arrowCursorRects: () -> [CGRect] = { [] }
    /// Told before a click is tracked, so a force click's pending mouse-up is not
    /// mistaken for part of the next click. Answers whether it took the click
    /// itself, as the reader inside a link preview does, to commit it.
    var willTrackMouseDown: () -> Bool = { false }

    /// A find match or a VoiceOver rotor stop far from the viewport lands on an
    /// estimate under viewport layout; the engine puts it there exactly instead.
    var revealRange: ((NSRange) -> Bool)?

    override func scrollRangeToVisible(_ range: NSRange) {
      if revealRange?(range) == true { return }
      super.scrollRangeToVisible(range)
    }

    /// Told of a key pressed in the text, before it scrolls anything: in a
    /// side-by-side reading, that side leads (#187).
    var willHandleKey: () -> Void = {}

    override func keyDown(with event: NSEvent) {
      willHandleKey()
      super.keyDown(with: event)
    }

    /// The quote for a range of the text, from the coordinator (#186).
    var quoteSelection: (NSRange) -> QuoteCitation.Quote? = { _ in nil }
    /// The URL a copy links a link of the text to (`LinkCopy.publicURL`), from the
    /// coordinator, which knows the document (#778).
    var publicURL: (URL) -> URL? = { _ in nil }
    /// What shows a rendered verbatim block as its text, or back, or nil where the
    /// reader cannot, as in a force-click preview.
    var choosePresentation: () -> ((PresentationKey, PresentationChoices.Presentation) -> Void)? = {
      nil
    }

    /// Edit ▸ Copy as Quote (⌥⇧⌘C), and the context menu's (#186).
    @objc func copyAsQuote(_ sender: Any?) {
      guard let quote = quoteSelection(selectedRange()) else { return }
      Clipboard.write(.quote(quote), announcing: .quote)
    }

    /// Look Up from the menu or the keyboard: a reference under the selection is
    /// still previewed rather than looked up. A force click never arrives here; see
    /// `trackReferenceClick(_:link:at:)`.
    override func quickLook(with event: NSEvent) {
      guard !quickLookReference(event) else { return }
      super.quickLook(with: event)
    }

    /// The hosted header in the top inset. Named rather than found among the
    /// subviews, because TextKit 2 keeps its own fragment views there.
    weak var header: NSView?

    /// The text view sets the I-beam over its whole bounds — over the header's
    /// author chips too, which are buttons, and its title, which cannot be selected,
    /// and under the overlay scroller, which lies over the text. Over either the
    /// pointer is the arrow. Both overrides are needed: a cursor update the hosting
    /// view does not handle arrives here through the responder chain, and every move
    /// resets it.
    /// The arrow beside a heading the outline discloses (#698) and over a code block's
    /// copy button (#724), in two halves that both have to hold, as a run of the app
    /// showed: a cursor rect, added after `super`'s as `NSTextView` adds a link's
    /// pointing hand over its I-beam, sets it on the way in; and `wantsArrow`, which
    /// answers for the same rects, keeps `mouseMoved` from putting the I-beam back on
    /// every move.
    override func resetCursorRects() {
      super.resetCursorRects()
      arrowRects = arrowCursorRects()
      for rect in arrowRects {
        addCursorRect(rect, cursor: .arrow)
      }
    }

    /// The arrow's rects as the cursor rects were last set, which every pointer move
    /// asks about: worked out once per reset, not per move.
    private var arrowRects: [CGRect] = []

    override func cursorUpdate(with event: NSEvent) {
      guard !wantsArrow(event) else {
        NSCursor.arrow.set()
        return
      }
      super.cursorUpdate(with: event)
    }

    override func mouseExited(with event: NSEvent) {
      hoverSectionNumber(nil)
      super.mouseExited(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
      hoverSectionNumber(event)
      guard !wantsArrow(event) else {
        NSCursor.arrow.set()
        return
      }
      super.mouseMoved(with: event)
    }

    private func wantsArrow(_ event: NSEvent) -> Bool {
      if let header, header.frame.contains(convert(event.locationInWindow, from: nil)) {
        return true
      }
      // Beside a heading the outline discloses, or over a copy button: the cursor rects
      // show the arrow on the way in, and every move reaches here, where `super` would
      // put the I-beam back.
      let point = convert(event.locationInWindow, from: nil)
      if arrowRects.contains(where: { $0.contains(point) }) { return true }
      guard let scrollView = enclosingScrollView, let scroller = scrollView.verticalScroller,
        !scroller.isHidden
      else { return false }
      return scroller.frame.contains(scrollView.convert(event.locationInWindow, from: nil))
    }

    /// Before `super`, which runs the whole click — `clickedOnLink` included — in its
    /// own tracking loop and does not return until the button is up. A click that
    /// starts on a reference is tracked here instead — a single click without
    /// Control: a control-click is the context menu and a double-click selects,
    /// both `NSTextView`'s as they were before.
    override func mouseDown(with event: NSEvent) {
      guard !willTrackMouseDown() else { return }
      // An Option-click on a hung heading number copies a link to the heading,
      // rather than following it (#433).
      if event.clickCount == 1,
        event.modifierFlags.intersection([.option, .control, .shift, .command]) == .option,
        copySectionLink(event)
      {
        return
      }
      // A copy button is a button: a click on it copies, and selects nothing.
      if event.clickCount == 1, !event.modifierFlags.contains(.control), copyCode(event) {
        return
      }
      if event.clickCount == 1, event.modifierFlags.isDisjoint(with: [.control, .shift, .command]),
        toggleSection(event)
      {
        return
      }
      guard event.clickCount == 1, !event.modifierFlags.contains(.control),
        let (link, index) = referenceLink(event)
      else {
        super.mouseDown(with: event)
        return
      }
      trackReferenceClick(event, link: link, at: index)
    }

    /// A click that starts on a reference, tracked here rather than by `NSTextView`,
    /// whose own tracking loop takes a force click's pressure events off the queue:
    /// logged on a Force Touch trackpad, stage 2 never reached `pressureChange(with:)`
    /// or `quickLook(with:)`, and a force click on a reference showed nothing (#29).
    /// Here the deep press previews the reference — or, when it has no preview, is
    /// Look Up's, as it is on any other word — and its mouse-up is swallowed; a
    /// plain release follows the link through `clicked(onLink:at:)`, as `NSTextView`
    /// would have; and a drag is handed back to `NSTextView` from the mouse-down, so
    /// a selection can still start on a reference.
    private func trackReferenceClick(_ down: NSEvent, link: Any, at index: Int) {
      guard let window else { return }
      // Decided once, at the first event of stage 2. Not on `stageTransition`, which
      // measures the way to the next stage rather than the step into this one: it
      // reads 0 on the first event of stage 2, logged on the trackpad.
      var forceClicked = false
      while let event = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged, .pressure]) {
        switch event.type {
        case .pressure:
          if !forceClicked, event.stage >= 2 {
            forceClicked = true
            if !quickLookReference(event) { super.quickLook(with: event) }
          }
        case .leftMouseDragged:
          let distance = hypot(
            event.locationInWindow.x - down.locationInWindow.x,
            event.locationInWindow.y - down.locationInWindow.y)
          if !forceClicked, distance > Self.dragThreshold {
            super.mouseDown(with: down)
            return
          }
        case .leftMouseUp:
          if !forceClicked { clicked(onLink: link, at: index) }
          return
        default:
          break
        }
      }
    }

    /// How far, in points, a press on a reference moves before it is a drag.
    private static let dragThreshold: CGFloat = 3

    /// Copy writes the selection as `PasteboardContent` has it, in one go, as iOS
    /// does (#778). A selection of several ranges stays AppKit's to join.
    override func copy(_ sender: Any?) {
      guard selectedRanges.count == 1, selectedRange().length > 0 else {
        super.copy(sender)
        return
      }
      Clipboard.write(.selection(selectedSubstring, publicURL: publicURL))
    }

    /// A drag and a service get the HTML a copy carries too.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
      let types = super.writablePasteboardTypes
      return types.contains(.html) ? types : types + [.html]
    }

    /// For a drag or a service, which AppKit writes a type at a time, asking for each
    /// by its legacy name (`SelectionText.flavor(of:)`); the reply is written under
    /// the name asked for. Each is `PasteboardContent`'s, as a copy's is. A selection
    /// of several ranges stays AppKit's to join, chip and all, but for its plain
    /// text, which is the one the chip's characters are wrong for.
    override func writeSelection(
      to pboard: NSPasteboard,
      type: NSPasteboard.PasteboardType
    ) -> Bool {
      guard let flavor = SelectionText.flavor(of: type) else {
        return super.writeSelection(to: pboard, type: type)
      }
      if flavor == .plain {
        // Every range, as AppKit joins them: a line apart.
        let text = attributedString()
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let plain = ranges.map { SelectionText.plainText(of: text.attributedSubstring(from: $0)) }
        return pboard.setString(plain.joined(separator: "\n"), forType: type)
      }
      guard selectedRanges.count == 1 else {
        return super.writeSelection(to: pboard, type: type)
      }
      let content = PasteboardContent.selection(selectedSubstring, publicURL: publicURL)
      switch content.value(for: flavor.type) {
      case .text(let text)?: return pboard.setString(text, forType: type)
      case .data(let data)?: return pboard.setData(data, forType: type)
      case nil: return false
      }
    }

    private var selectedSubstring: NSAttributedString {
      attributedString().attributedSubstring(from: selectedRange())
    }

    /// "Copy Figure" for the figure under the click, or else the one the selection
    /// holds (issue #15). First in the menu, because on a figure it is what the
    /// menu was opened for. Which figure and what it copies are `FigureCopy`'s.
    /// "Copy as Quote" right after Copy where there is a selection (#186).
    override func menu(for event: NSEvent) -> NSMenu? {
      let standard = super.menu(for: event)
      let text = attributedString()
      let clicked = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
      let clickedBox = FigureCopy.box(at: clicked, in: text)
      let box = clickedBox ?? FigureCopy.box(in: selectedRange(), of: text)
      let figure = box?.content
      let quotes = selectedRange().length > 0
      guard figure != nil || quotes else { return standard }
      // A copy, so the items are never left behind in a menu AppKit hands out again.
      let result = (standard?.copy() as? NSMenu) ?? NSMenu()
      if quotes {
        let quote = NSMenuItem(
          title: String(localized: "Copy as Quote"), action: #selector(copyAsQuote(_:)),
          keyEquivalent: "")
        quote.target = self
        let copyIndex = result.items.firstIndex { $0.action == #selector(NSText.copy(_:)) }
        result.insertItem(quote, at: copyIndex.map { $0 + 1 } ?? result.items.count)
      }
      if let box, figure != nil {
        let item = NSMenuItem(
          title: String(localized: "Copy Figure"), action: #selector(copyFigure(_:)),
          keyEquivalent: "")
        item.target = self
        let near = clickedBox != nil ? NSRange(location: clicked, length: 0) : selectedRange()
        item.representedObject = (box, near)
        if !result.items.isEmpty {
          result.insertItem(.separator(), at: 0)
        }
        result.insertItem(item, at: 0)
        if let shown = box.presentation, choosePresentation() != nil {
          let toggle = NSMenuItem(
            title: FigureMenu.title(offeredFrom: shown),
            action: #selector(choosePresentationItem(_:)), keyEquivalent: "")
          toggle.target = self
          toggle.representedObject = (box.presentationKey, FigureMenu.offered(from: shown))
          result.insertItem(toggle, at: 1)
        }
      }
      return result
    }

    @objc private func choosePresentationItem(_ sender: NSMenuItem) {
      guard
        let (key, presentation) = sender.representedObject
          as? (PresentationKey, PresentationChoices.Presentation)
      else { return }
      choosePresentation()?(key, presentation)
    }

    /// The figure's text, and its drawing where the reader draws it (#778).
    @objc private func copyFigure(_ sender: NSMenuItem) {
      guard let (box, near) = sender.representedObject as? (VerbatimBox, NSRange) else { return }
      let drawn =
        box.presentation == .figure
        ? FigureMenu.itemRange(of: box, touching: near, in: attributedString())
        : nil
      Clipboard.write(
        .figure(box.content, png: drawn.flatMap(figurePNG(of:))), announcing: .figure)
    }

    /// The block in `range` as it is drawn: its fragments, card and lines and all, on
    /// the page's background, in the view's appearance, at the window's scale; as
    /// the iOS figure menu draws it.
    private func figurePNG(of range: NSRange) -> Data? {
      guard let layout = textLayoutManager,
        let start = layout.location(layout.documentRange.location, offsetBy: range.location),
        let end = layout.location(start, offsetBy: range.length)
      else { return nil }
      var fragments: [NSTextLayoutFragment] = []
      layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
        guard fragment.rangeInElement.location.compare(end) == .orderedAscending else {
          return false
        }
        fragments.append(fragment)
        return true
      }
      let bounds = fragments.reduce(CGRect.null) { bounds, fragment in
        let origin = fragment.layoutFragmentFrame.origin
        return bounds.union(fragment.renderingSurfaceBounds.offsetBy(dx: origin.x, dy: origin.y))
      }
      guard !bounds.isNull, !bounds.isEmpty else { return nil }
      let scale = window?.backingScaleFactor ?? 2
      guard
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int((bounds.width * scale).rounded(.up)),
          pixelsHigh: Int((bounds.height * scale).rounded(.up)), bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0),
        let cgContext = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext
      else { return nil }
      // Flipped, as the text view is, at the window's scale; and said to be, for what
      // AppKit draws itself, such as a chip's image.
      cgContext.scaleBy(x: scale, y: scale)
      cgContext.translateBy(x: 0, y: bounds.height)
      cgContext.scaleBy(x: 1, y: -1)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
      effectiveAppearance.performAsCurrentDrawingAppearance {
        backgroundColor.setFill()
        CGRect(origin: .zero, size: bounds.size).fill()
        for fragment in fragments {
          let origin = fragment.layoutFragmentFrame.origin
          fragment.draw(
            at: CGPoint(x: origin.x - bounds.minX, y: origin.y - bounds.minY), in: cgContext)
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      // Its size in points, so it pastes at the size it shows, not twice it.
      bitmap.size = bounds.size
      return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - What VoiceOver reads (#12)

    /// A diagram is said as its label, not read out one box-drawing character at a
    /// time. `AccessibleReading` decides what each part of `range` becomes; the text
    /// parts come from `super`, so they keep every attribute AppKit gives VoiceOver.
    ///
    /// Only the per-range accessors. `accessibilityValue` stays the real text, because
    /// its length is the character count every range VoiceOver asks for is measured
    /// in.
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
      AccessibleReading.reading(
        range,
        in: attributedString(),
        text: { super.accessibilityAttributedString(for: $0) },
        label: { NSAttributedString(string: $0) },
        join: { parts in
          let joined = NSMutableAttributedString()
          parts.forEach(joined.append)
          return joined
        })
    }

    /// Each accessor asks its own `super` for the text, never the other override:
    /// whether AppKit builds one from the other is not ours to know, and if it did,
    /// the two overrides would call each other forever.
    override func accessibilityString(for range: NSRange) -> String? {
      AccessibleReading.reading(
        range,
        in: attributedString(),
        text: { super.accessibilityString(for: $0) },
        label: { $0 },
        join: { $0.joined() })
    }
  }
#endif
