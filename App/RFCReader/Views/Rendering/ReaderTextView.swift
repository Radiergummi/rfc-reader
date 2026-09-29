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
    /// The reader runs under the home indicator (`DocumentView` lets it into the
    /// bottom safe area), so the strip that area covers becomes room to scroll the
    /// last line clear of it rather than a place the text stops at.
    ///
    /// By hand, because `contentInsetAdjustmentBehavior` is `.never`: automatic
    /// adjustment would move `contentOffset`'s origin away from the top of the
    /// content, which is what the anchor arithmetic is expressed in. Only the
    /// bottom is set here, and a bottom inset leaves that origin where it is.
    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      guard contentInset.bottom != safeAreaInsets.bottom else { return }
      contentInset.bottom = safeAreaInsets.bottom
      verticalScrollIndicatorInsets.bottom = safeAreaInsets.bottom
    }

    /// Where the view's top edge is on screen, or nil outside a window. Measured
    /// against the root view rather than the window: a sheet scales the view behind
    /// it down, which moves its edge in the window without moving the text.
    var topEdge: CGFloat? {
      guard let window else { return nil }
      return convert(bounds.origin, to: window.rootViewController?.view ?? window).y
    }

    /// The top edge and the width at the last layout; see `keepTextInPlace()`.
    private var placed: (top: CGFloat, width: CGFloat)?

    override func layoutSubviews() {
      super.layoutSubviews()
      keepTextInPlace()
    }

    /// When the reader's bars go on iPhone (`ReaderChrome`), SwiftUI grows the
    /// reader up into the top bar's place, and the text would move up with the
    /// view's edge; when they come back, down again. The scroll offset moves by as
    /// much instead, so the text stays where it is and only the strip the bar left
    /// is new; at the top of the document the text follows the edge instead (see
    /// `ReaderChrome.offsetKeepingTextInPlace`). Not when the width changed as well
    /// — a rotation — which re-wraps and restores the place its own way
    /// (`RFCTextViewCoordinator.layOut`).
    private func keepTextInPlace() {
      guard let top = topEdge else {
        placed = nil
        return
      }
      let previous = placed
      placed = (top, bounds.width)
      guard let previous, previous.width == bounds.width, previous.top != top else { return }
      let lowest = -adjustedContentInset.top
      let highest = max(lowest, contentSize.height + adjustedContentInset.bottom - bounds.height)
      let y = ReaderChrome.offsetKeepingTextInPlace(
        contentOffset.y, edgeMovedBy: top - previous.top, within: lowest...highest)
      guard y != contentOffset.y else { return }
      contentOffset.y = y
    }

    /// The quote for a range of the text, from the coordinator (#186).
    var quoteSelection: (NSRange) -> QuoteCitation.Quote? = { _ in nil }

    /// Copy as Quote: one item carrying the Markdown as plain text and as Markdown, the
    /// HTML and the rich flavor as RTF. Offered in the edit menu beside Copy
    /// (`RFCTextViewCoordinator`).
    func copyAsQuote() {
      guard let quote = quoteSelection(selectedRange) else { return }
      var item: [String: Any] = [
        UTType.utf8PlainText.identifier: quote.plainText,
        QuoteCitation.Quote.markdownType: quote.markdown,
        UTType.html.identifier: quote.html,
      ]
      if let rtf = quote.rtf {
        item[UTType.rtf.identifier] = rtf
      }
      UIPasteboard.general.items = [item]
    }

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
      UIPasteboard.general.string = SelectionText.plainText(
        of: attributed.attributedSubstring(from: selection))
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
    /// Force click on a reference previews it; answers whether it did. Set by the
    /// representable, and a closure rather than the coordinator so this view stays
    /// about text.
    var quickLookReference: (NSEvent) -> Bool = { _ in false }
    /// The link, and the character it is on, that a click at a mouse-down follows
    /// when the mouse-down is on a reference, or nil anywhere else.
    var referenceLink: (NSEvent) -> (link: Any, characterIndex: Int)? = { _ in nil }
    /// Told before a click is tracked, so a force click's pending mouse-up is not
    /// mistaken for part of the next click. Answers whether it took the click
    /// itself, as the reader inside a link preview does, to commit it.
    var willTrackMouseDown: () -> Bool = { false }
    /// The quote for a range of the text, from the coordinator (#186).
    var quoteSelection: (NSRange) -> QuoteCitation.Quote? = { _ in nil }

    /// Edit ▸ Copy as Quote (⌥⇧⌘C), and the context menu's: the Markdown as plain text
    /// and as Markdown, the HTML and the rich flavor as RTF (#186).
    @objc func copyAsQuote(_ sender: Any?) {
      guard let quote = quoteSelection(selectedRange()) else { return }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(quote.plainText, forType: .string)
      pasteboard.setString(
        quote.markdown, forType: NSPasteboard.PasteboardType(QuoteCitation.Quote.markdownType))
      pasteboard.setString(quote.html, forType: .html)
      if let rtf = quote.rtf {
        pasteboard.setData(rtf, forType: .rtf)
      }
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
    /// author chips too, which are buttons, and its title, which cannot be selected.
    /// Over the header the pointer is the arrow. Both overrides are needed: a cursor
    /// update the hosting view does not handle arrives here through the responder
    /// chain, and every move resets it.
    override func cursorUpdate(with event: NSEvent) {
      guard !isOverHeader(event) else {
        NSCursor.arrow.set()
        return
      }
      super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
      guard !isOverHeader(event) else {
        NSCursor.arrow.set()
        return
      }
      super.mouseMoved(with: event)
    }

    private func isOverHeader(_ event: NSEvent) -> Bool {
      guard let header else { return false }
      return header.frame.contains(convert(event.locationInWindow, from: nil))
    }

    /// Before `super`, which runs the whole click — `clickedOnLink` included — in its
    /// own tracking loop and does not return until the button is up. A click that
    /// starts on a reference is tracked here instead — a single click without
    /// Control: a control-click is the context menu and a double-click selects,
    /// both `NSTextView`'s as they were before.
    override func mouseDown(with event: NSEvent) {
      guard !willTrackMouseDown() else { return }
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

    /// AppKit asks for each declared type in turn. Only the plain-text flavor is
    /// rewritten -- that is the one a terminal, a mail body or a code editor reads,
    /// and the one the chip's characters are wrong for. The rich flavors stay
    /// AppKit's, because a rich target receives the attachment as an image, which is
    /// the chip's symbol and is what it looks like on screen.
    override func writeSelection(
      to pboard: NSPasteboard,
      type: NSPasteboard.PasteboardType
    ) -> Bool {
      guard type == .string else { return super.writeSelection(to: pboard, type: type) }
      let selection = attributedString().attributedSubstring(from: selectedRange())
      pboard.setString(SelectionText.plainText(of: selection), forType: .string)
      return true
    }

    /// "Copy Figure" for the figure under the click, or else the one the selection
    /// holds (issue #15). First in the menu, because on a figure it is what the
    /// menu was opened for. Which figure and what it copies are `FigureCopy`'s.
    /// "Copy as Quote" right after Copy where there is a selection (#186).
    override func menu(for event: NSEvent) -> NSMenu? {
      let standard = super.menu(for: event)
      let text = attributedString()
      let clicked = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
      let figure =
        FigureCopy.figure(at: clicked, in: text) ?? FigureCopy.figure(in: selectedRange(), of: text)
      let quotes = selectedRange().length > 0
      guard figure != nil || quotes else { return standard }
      // A copy, so the items are never left behind in a menu AppKit hands out again.
      let result = (standard?.copy() as? NSMenu) ?? NSMenu()
      if quotes {
        let quote = NSMenuItem(
          title: "Copy as Quote", action: #selector(copyAsQuote(_:)), keyEquivalent: "")
        quote.target = self
        let copyIndex = result.items.firstIndex { $0.action == #selector(NSText.copy(_:)) }
        result.insertItem(quote, at: copyIndex.map { $0 + 1 } ?? result.items.count)
      }
      if let figure {
        let item = NSMenuItem(
          title: "Copy Figure", action: #selector(copyFigure(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = figure
        if !result.items.isEmpty {
          result.insertItem(.separator(), at: 0)
        }
        result.insertItem(item, at: 0)
      }
      return result
    }

    @objc private func copyFigure(_ sender: NSMenuItem) {
      guard let figure = sender.representedObject as? Preformatted else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(FigureCopy.pasteboardText(for: figure), forType: .string)
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
