import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// Highlights (#522): drawn where the installed build places them, never written into
// the build, which is shared (`BuiltDocument`). Where each goes is
// `HighlightPlacement`'s, made off the main actor; this hands it to the fragments
// (`FoldingDelegate`), to VoiceOver and to the Annotations tab, and makes and changes
// highlights through the library.

extension AnnotationSnapshot.NoteEntry {
  /// What placing a note reads of it: not its text.
  fileprivate var placementKey: [AnyHashable] {
    [id, highlight as AnyHashable, target as AnyHashable, relocated as AnyHashable]
  }
}

extension RFCTextViewCoordinator {
  /// The document's highlights and notes (#523), as the library has them now: placed
  /// again when they changed.
  func setAnnotations(
    highlights entries: [AnnotationSnapshot.HighlightEntry],
    notes: [AnnotationSnapshot.NoteEntry]
  ) {
    // Called on every update of the representable: most change nothing.
    guard entries != highlights || notes != self.notes else { return }
    // A note's text changes as it is typed; where it goes does not.
    let moved = entries != highlights || notes.map(\.placementKey) != self.notes.map(\.placementKey)
    highlights = entries
    self.notes = notes
    // A note's text alone changed: its marker's title.
    if moved { placeHighlights() } else { layOutNoteMarkers() }
  }

  /// Places the highlights and notes in the installed build, off the main actor, and
  /// draws them once placed. After every install, whose build has its own positions.
  func placeHighlights() {
    highlightsTask?.cancel()
    highlightsTask = nil
    guard let built else { return }
    let entries = highlights
    let notes = notes
    guard !entries.isEmpty || !notes.isEmpty else {
      // A translation's build places nothing, which says so even with nothing to place.
      draw(HighlightPlacement([], in: built), notes: built.isTranslation ? nil : NotePlacement.none)
      return
    }
    highlightsTask = Task {
      let (placement, notePlacement) = await Self.place(entries, notes: notes, in: built)
      // A later build or set of annotations has started its own.
      guard !Task.isCancelled, self.built?.text === built.text, self.highlights == entries,
        self.notes.map(\.placementKey) == notes.map(\.placementKey)
      else { return }
      highlightsTask = nil
      draw(placement, notes: placement.isPlaced ? notePlacement : nil)
    }
  }

  @concurrent
  private static func place(
    _ entries: [AnnotationSnapshot.HighlightEntry], notes: [AnnotationSnapshot.NoteEntry],
    in built: BuiltDocument
  ) async -> (HighlightPlacement, NotePlacement) {
    let highlights = HighlightPlacement(entries, in: built)
    return (highlights, NotePlacement(notes, highlights: highlights, in: built))
  }

  /// Draws `placement`, says where each highlight and note is, stands the notes'
  /// markers by their lines, and writes back where relocation found one that moved.
  private func draw(_ placement: HighlightPlacement, notes: NotePlacement?) {
    let changed = placement.marks != highlightPlacement.marks
    highlightPlacement = placement
    notePlacement = notes ?? .none
    accessibilityHighlights = placement.marks.rotorItems()
    controller?.reportHighlights(placement.isPlaced ? placement.statuses : nil)
    controller?.reportNotes(notes)
    if changed {
      foldingDelegate.highlight(placement.marks)
      // Drawn again, not laid out again: a highlight changes no line.
      engine.redraw()
    }
    layOutNoteMarkers()
    if !placement.relocations.isEmpty {
      environment?.library.recordHighlightRelocations(placement.relocations)
    }
    if let notes { environment?.library.recordNotePlacement(notes) }
  }

  /// Drops what was placed in the build being replaced.
  func forgetHighlights() {
    highlightsTask?.cancel()
    highlightsTask = nil
    highlightPlacement = .none
    notePlacement = .none
    accessibilityHighlights = []
    foldingDelegate.highlight(HighlightMarks([]))
    layOutNoteMarkers()
  }

  // MARK: - Making and changing

  /// Highlights `range` of the reader's text in `color`, or in the color last used,
  /// out to whole words. Nothing in a translation, whose sentences are not the
  /// original's (#749).
  @discardableResult
  func highlight(_ range: NSRange, color: HighlightColor?) -> UUID? {
    guard let built, !built.isTranslation, let documentID, let library = environment?.library,
      let text = textView?.textLayoutManager?.attributedText
    else { return nil }
    let snapped = WordSnap.snapped(range, in: text.string as NSString)
    guard let model = built.positions.modelRange(forStorage: snapped) else { return nil }
    return library.highlight(
      model, of: documentID, in: built.positions.model,
      color: color ?? library.lastHighlightColor, undoManager: undoManager)
  }

  /// Where a change to a highlight registers its undo: the window's on the Mac, as a
  /// bookmark's does, which Edit ▸ Undo reaches wherever the focus is. A read-only
  /// text view's own undo manager is not that one: a highlight registered there
  /// left Undo grayed out.
  var undoManager: UndoManager? {
    #if canImport(UIKit)
      textView?.undoManager
    #else
      textView?.window?.undoManager
    #endif
  }

  /// The colors offered, the one last used first.
  var highlightColors: [HighlightColor] {
    let last = environment?.library.lastHighlightColor ?? .default
    return [last] + HighlightColor.allCases.filter { $0 != last }
  }

  /// The whole of a highlight as drawn (`HighlightMarks.range(of:)`).
  func highlightRange(of identifier: UUID) -> NSRange? {
    highlightPlacement.marks.range(of: identifier)
  }

  /// What the popover of the highlight at `offset` shows and does.
  func highlightPopover(at offset: Int, dismiss: @escaping () -> Void) -> HighlightPopover? {
    guard let mark = highlightPlacement.marks.highlight(at: offset),
      let library = environment?.library, let range = highlightRange(of: mark.highlight)
    else { return nil }
    let identifier = mark.highlight
    // A note opens beside the line clicked, as the popover does, not the whole
    // highlight, which may run off the screen.
    let line = NSRange(location: offset, length: 1)
    let undoManager = undoManager
    let notes = notes.filter { notePlacement.highlight(of: $0) == identifier }
      .map { AnnotationList.NoteLine(of: $0) }
    return HighlightPopover(
      color: mark.color, colors: HighlightColor.allCases, notes: notes,
      choose: { color in
        library.setHighlightColor(color, of: identifier, undoManager: undoManager)
        dismiss()
      },
      copyAsQuote: { [weak self] in
        if let quote = self?.quote(of: range) {
          Clipboard.write(.quote(quote), announcing: .quote)
        }
        dismiss()
      },
      delete: {
        library.deleteHighlight(identifier, undoManager: undoManager)
        dismiss()
      },
      addNote: { [weak self] in
        dismiss()
        self?.openNote(.new(.highlight(identifier)), at: line)
      },
      openNote: { [weak self] note in
        dismiss()
        self?.openNote(.existing(note), at: line)
      })
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator {
    /// A tap in a highlight, once a double tap has failed: its popover, pointing at it.
    func showHighlightPopover(at offset: Int) {
      guard let textView, var presenter = textView.window?.rootViewController,
        let mark = highlightPlacement.marks.highlight(at: offset),
        let range = highlightRange(of: mark.highlight),
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
        let end = textView.position(from: start, offset: range.length),
        let textRange = textView.textRange(from: start, to: end)
      else { return }
      while let presented = presenter.presentedViewController { presenter = presented }
      let host = UIHostingController<HighlightPopover?>(rootView: nil)
      guard
        let popover = highlightPopover(
          at: offset,
          dismiss: { [weak host] in host?.presentingViewController?.dismiss(animated: true) })
      else { return }
      host.rootView = popover
      host.modalPresentationStyle = .popover
      // Its size follows its content: Delete asks first, in rows of its own.
      host.sizingOptions = .preferredContentSize
      host.popoverPresentationController?.sourceView = textView
      host.popoverPresentationController?.sourceRect = textView.firstRect(for: textRange)
      host.popoverPresentationController?.delegate = self
      presenter.present(host, animated: true)
    }

    /// The edit menu's Highlight row: a palette of the colors, the one last used first.
    func highlightMenu(for range: NSRange) -> UIMenu {
      let actions = highlightColors.map { color in
        UIAction(title: color.title(), image: HighlightSwatch.image(color)) { [weak self] _ in
          self?.highlight(range, color: color)
        }
      }
      return UIMenu(
        title: String(localized: "Highlight"), image: UIImage(systemName: "highlighter"),
        options: .displayAsPalette, children: actions)
    }
  }
#else
  extension RFCTextViewCoordinator {
    /// A click on the text that selected nothing and cleared no selection: in a
    /// highlight, its popover, once the double-click interval has passed with no
    /// second click.
    func clickedText(_ event: NSEvent) {
      guard let textView else { return }
      let point = textView.convert(event.locationInWindow, from: nil)
      let origin = textView.textContainerOrigin
      guard
        let offset = characterOffset(
          atContainerPoint: CGPoint(x: point.x - origin.x, y: point.y - origin.y)),
        highlightPlacement.marks.highlight(at: offset) != nil,
        // A link in a highlight opens, and that is all the click does.
        link(at: offset) == nil
      else { return }
      highlightClick?.cancel()
      highlightClick = Task { [weak self] in
        try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
        guard !Task.isCancelled else { return }
        self?.showHighlightPopover(at: offset)
      }
    }

    /// The highlight's popover, beside it, closing when the reader clicks elsewhere.
    func showHighlightPopover(at offset: Int) {
      guard let textView, let mark = highlightPlacement.marks.highlight(at: offset),
        let range = highlightRange(of: mark.highlight), let rect = referenceRect(for: range)
      else { return }
      highlightPopover?.close()
      let popover = NSPopover()
      popover.behavior = .transient
      guard
        let content = highlightPopover(
          at: offset, dismiss: { [weak popover] in popover?.close() })
      else { return }
      let host = NSHostingController(rootView: content)
      host.sizingOptions = .preferredContentSize
      popover.contentViewController = host
      highlightPopover = popover
      // Beside the line clicked, not the whole highlight, which may run off the screen.
      let line = referenceRect(for: NSRange(location: offset, length: 1)) ?? rect
      let origin = textView.textContainerOrigin
      popover.show(
        relativeTo: line.offsetBy(dx: origin.x, dy: origin.y), of: textView, preferredEdge: .maxY)
    }
  }
#endif
