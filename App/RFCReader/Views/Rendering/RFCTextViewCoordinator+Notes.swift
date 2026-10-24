import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

// Notes (#523): markers in the trailing gutter, level with the first line of what
// each note is on, and the editor, opened from a marker, a highlight's popover, a
// menu, the contents panel or the Annotations tab. Where the markers go is
// `FragmentGeometry.noteMarkers`, over lines read from fragments laid out for real;
// they are views over the text view, as the header is, never part of the storage.

extension RFCTextViewCoordinator {
  // MARK: - Markers

  /// Stands the markers by their lines, over the viewport and a margin: after every
  /// placement, scroll and layout. A marker whose line is laid out on an estimate,
  /// or folded away, is left out until it is real.
  func layOutNoteMarkers() {
    guard let textView, let layout = textView.textLayoutManager, built != nil,
      !notePlacement.markers.isEmpty,
      let viewport = layout.textViewportLayoutController.viewportRange
    else {
      showNoteMarkers([])
      return
    }
    let start = layout.offset(of: viewport.location)
    let end = layout.offset(of: viewport.endLocation)
    let hidden = foldingDelegate.hidden
    var lines: [FragmentGeometry.NoteLine] = []
    for marker in notePlacement.markers
    where marker.location >= start && marker.location <= end && !hidden.contains(marker.location) {
      guard let location = layout.location(atOffset: marker.location),
        let fragment = layout.textLayoutFragment(for: location)
      else { continue }
      guard let fragmentLines = FragmentLines(fragment, in: layout),
        let line = FragmentGeometry.noteMarkerLine(at: marker.location, in: fragmentLines)
      else { continue }
      lines.append(
        FragmentGeometry.NoteLine(
          note: marker.note,
          y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY,
          height: line.typographicBounds.height,
          isLaidOut: fragment.state == .layoutAvailable))
    }
    let top = textView.viewportTop - FragmentGeometry.noteMarkerMargin
    let bottom =
      textView.viewportTop + textView.viewportHeight + FragmentGeometry.noteMarkerMargin
    showNoteMarkers(FragmentGeometry.noteMarkers(lines, visible: top...bottom))
  }

  private var containerOrigin: CGPoint {
    guard let textView else { return .zero }
    #if canImport(UIKit)
      return CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
    #else
      return textView.textContainerOrigin
    #endif
  }

  /// The marker views, one a marker, reused as the markers move.
  private func showNoteMarkers(_ markers: [FragmentGeometry.NoteMarker]) {
    guard let textView else { return }
    let shown = noteMarkers.map(\.notes)
    let bodies = notes.map(\.body)
    let changedBodies = noteMarkersBodies != bodies
    noteMarkers = markers
    noteMarkersBodies = bodies
    while noteMarkerViews.count > markers.count {
      noteMarkerViews.removeLast().removeFromSuperview()
    }
    while noteMarkerViews.count < markers.count {
      let view = makeMarkerView()
      textView.addSubview(view)
      noteMarkerViews.append(view)
    }
    let views = noteMarkerViews
    let origin = containerOrigin
    let container: NSTextContainer? = textView.textContainer
    let column = container?.size.width ?? textView.bounds.width
    for (index, (view, marker)) in zip(views, markers).enumerated() {
      view.frame = FragmentGeometry.noteMarkerFrame(
        marker, containerOrigin: origin, columnWidth: column, viewWidth: textView.bounds.width)
      // Only a marker that stands for other notes now, or whose notes' text changed:
      // this runs on every scroll tick, and its title reads the notes' Markdown.
      if changedBodies || index >= shown.count || shown[index] != marker.notes {
        configure(view, index: index, count: marker.notes.count)
      }
    }
  }

  /// The notes a marker view stands for.
  private func notes(ofMarker index: Int) -> [AnnotationSnapshot.NoteEntry] {
    guard noteMarkers.indices.contains(index) else { return [] }
    let identifiers = noteMarkers[index].notes
    return identifiers.compactMap { identifier in notes.first { $0.id == identifier } }
  }

  /// Where a marker's notes stand: the start of their line.
  private func markerRange(_ index: Int) -> NSRange? {
    guard let note = noteMarkers[safe: index]?.notes.first,
      let marker = notePlacement.markers.first(where: { $0.note == note })
    else { return nil }
    return NSRange(location: marker.location, length: 1)
  }

  // MARK: - Opening the editor

  /// Opens the editor on `request`, beside `range` of the text, or beside where the
  /// note is placed; at the top of the view where it is placed nowhere.
  func openNote(_ request: NoteRequest, at range: NSRange?) {
    guard let built, !built.isTranslation, let documentID, let environment else { return }
    let library = environment.library
    // The editor open now saves before another opens. Opened again on its own note,
    // the next one starts from what it saved while the store's change has not reached
    // `notes`, or the next editor's close would save the older text over it; once
    // `notes` has changed since it opened, from that, which may be another window's.
    let open = noteEditor
    open?.model.close()
    let identifier: UUID
    let owner: NoteOwner
    let body: String
    switch request {
    case .existing(let id):
      guard let note = notes.first(where: { $0.id == id }) else { return }
      identifier = id
      // What it would be made on again, should its text go and come back.
      if let highlight = notePlacement.highlight(of: note) {
        owner = .highlight(highlight)
      } else {
        owner = .target(note.target ?? .section(ModelText.abstractAnchor))
      }
      if let open, open.note == id, note.body == open.model.initialBody,
        let saved = open.model.saved
      {
        body = saved
      } else {
        body = note.body
      }
    case .new(let made):
      identifier = UUID()
      owner = made
      body = ""
    }
    let place = range ?? noteRange(identifier, owner: owner)
    let undoManager = undoManager
    let reader = environment.reader
    #if canImport(UIKit)
      let showInAnnotations: (() -> Void)? = nil
    #else
      let showInAnnotations: (() -> Void)? = { [weak self] in
        self?.notePopover?.close()
        reader.show(.annotations)
      }
    #endif
    let model = NoteEditorModel(
      body: body, font: Self.noteFont,
      save: { body in
        library.saveNote(identifier, on: owner, of: documentID, body: body)
      },
      delete: { [weak self] in
        library.deleteNote(identifier, undoManager: undoManager)
        self?.closeNoteEditor()
      },
      openLink: { [weak self] url in
        _ = self?.onLink(url, .current)
      },
      showInAnnotations: showInAnnotations)
    noteEditor = (identifier, model)
    presentNoteEditor(model, at: place, environment: environment)
  }

  /// Where a note is in the text: its marker's line, or its highlight's start.
  private func noteRange(_ identifier: UUID, owner: NoteOwner) -> NSRange? {
    if let marker = notePlacement.markers.first(where: { $0.note == identifier }) {
      return NSRange(location: marker.location, length: 1)
    }
    if case .highlight(let highlight) = owner, let range = highlightRange(of: highlight) {
      return NSRange(location: range.location, length: 1)
    }
    if case .target(let target) = owner, let built,
      let model = target.range(in: built.positions.model),
      let first = built.positions.drawnRanges(forModel: model, in: built.text.string as NSString)
        .first
    {
      return NSRange(location: first.location, length: 1)
    }
    return nil
  }

  /// The editor's body font: the system's, at the size a note is read at.
  static var noteFont: PlatformFont {
    #if canImport(UIKit)
      UIFont.preferredFont(forTextStyle: .body)
    #else
      NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    #endif
  }

  // MARK: - Starting a note

  /// Add Note on a selection: a highlight in the color last used, and a note on it.
  func addNote(onSelection range: NSRange) {
    guard let highlight = highlight(range, color: nil) else { return }
    openNote(.new(.highlight(highlight)), at: NSRange(location: range.location, length: 1))
  }

  /// What a block's context menu offers a note on, at storage offset `location`.
  func noteBlock(at location: Int) -> NoteBlock? {
    guard let built else { return nil }
    return NoteBlock(at: location, in: built)
  }

  /// The title of the item that puts a note on `block`.
  static func addNoteTitle(_ block: NoteBlock) -> String {
    switch block {
    case .figure: String(localized: "Add Note to Figure")
    case .table: String(localized: "Add Note to Table")
    case .paragraph: String(localized: "Add Note to Paragraph")
    case .section: String(localized: "Add Note to Section")
    }
  }

  /// A note on `block`, from its menu.
  func addNote(on block: NoteBlock, at location: Int) {
    openNote(.new(.target(block.target)), at: NSRange(location: location, length: 1))
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

#if canImport(UIKit)
  extension RFCTextViewCoordinator {
    /// A marker's one action, replaced as the button is reused.
    private static let markerAction = UIAction.Identifier("noteMarker")

    private func makeMarkerView() -> UIView {
      let button = UIButton(type: .system)
      button.setImage(
        UIImage(
          systemName: "note.text",
          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)),
        for: .normal)
      button.tintColor = RFCColors.secondaryLabel
      button.showsMenuAsPrimaryAction = false
      return button
    }

    private func configure(_ view: UIView, index: Int, count: Int) {
      guard let button = view as? UIButton else { return }
      button.accessibilityLabel =
        count == 1 ? String(localized: "Note") : String(localized: "\(count) Notes")
      button.removeAction(identifiedBy: Self.markerAction, for: .primaryActionTriggered)
      let notes = notes(ofMarker: index)
      let range = markerRange(index)
      if notes.count > 1 {
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(
          children: notes.map { note in
            UIAction(title: AnnotationList.NoteLine(of: note).firstLine) { [weak self] _ in
              self?.openNote(.existing(note.id), at: range)
            }
          })
      } else if let note = notes.first {
        button.showsMenuAsPrimaryAction = false
        button.menu = nil
        button.addAction(
          UIAction(identifier: Self.markerAction) { [weak self] _ in
            self?.openNote(.existing(note.id), at: range)
          },
          for: .primaryActionTriggered)
      }
    }

    private func presentNoteEditor(
      _ model: NoteEditorModel, at range: NSRange?, environment: ReaderEnvironment
    ) {
      guard let textView, var presenter = textView.window?.rootViewController else { return }
      while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
        presenter = presented
      }
      let host = UIHostingController(
        rootView: NoteEditor(model: model).readerEnvironment(environment))
      host.modalPresentationStyle = .pageSheet
      // The medium detent, so the passage stays in view above it.
      host.sheetPresentationController?.detents = [.medium(), .large()]
      host.sheetPresentationController?.prefersGrabberVisible = true
      noteEditorHost = host
      // UIKit presents nothing while a dismissal is under way, as the highlight's
      // popover's or the panel's sheet is when a note is opened from it: once it is
      // gone.
      if let dismissing = presenter.presentedViewController,
        let transition = dismissing.transitionCoordinator
      {
        transition.animate(alongsideTransition: nil) { [weak presenter] _ in
          presenter?.present(host, animated: true)
        }
      } else {
        presenter.present(host, animated: true)
      }
    }

    func closeNoteEditor() {
      noteEditorHost?.presentingViewController?.dismiss(animated: true)
      noteEditorHost = nil
    }
  }
#else
  extension RFCTextViewCoordinator {
    private func makeMarkerView() -> NSView {
      let button = NSButton(
        image: NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
          ?? NSImage(), target: nil, action: nil)
      button.isBordered = false
      button.imagePosition = .imageOnly
      button.contentTintColor = RFCColors.secondaryLabel
      return button
    }

    private func configure(_ view: NSView, index: Int, count: Int) {
      guard let button = view as? NSButton else { return }
      button.setAccessibilityLabel(
        count == 1 ? String(localized: "Note") : String(localized: "\(count) Notes"))
      button.toolTip =
        count == 1
        ? notes(ofMarker: index).first.map { AnnotationList.NoteLine(of: $0).firstLine }
        : String(localized: "\(count) Notes")
      button.tag = index
      button.target = self
      button.action = #selector(markerClicked(_:))
    }

    @objc private func markerClicked(_ sender: NSButton) {
      let notes = notes(ofMarker: sender.tag)
      let range = markerRange(sender.tag)
      if notes.count == 1, let note = notes.first {
        openNote(.existing(note.id), at: range)
        return
      }
      // Several on one line: a short list of them.
      let menu = NSMenu()
      for note in notes {
        let item = NSMenuItem(
          title: AnnotationList.NoteLine(of: note).firstLine, action: #selector(markerMenuItem(_:)),
          keyEquivalent: "")
        item.target = self
        item.representedObject = (note.id, range)
        menu.addItem(item)
      }
      menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }

    @objc private func markerMenuItem(_ sender: NSMenuItem) {
      guard let (note, range) = sender.representedObject as? (UUID, NSRange?) else { return }
      openNote(.existing(note), at: range)
    }

    private func presentNoteEditor(
      _ model: NoteEditorModel, at range: NSRange?, environment: ReaderEnvironment
    ) {
      guard let textView else { return }
      notePopover?.close()
      let popover = NSPopover()
      // Stays while the reader looks elsewhere in the text, and closes, saving, when
      // a click lands outside it.
      popover.behavior = .transient
      let host = NSHostingController(
        rootView: NoteEditor(model: model)
          .frame(width: NoteEditor.width, height: 280)
          .readerEnvironment(environment))
      host.sizingOptions = .preferredContentSize
      popover.contentViewController = host
      notePopover = popover
      let origin = textView.textContainerOrigin
      let visible = textView.visibleRect
      // Asked for from the panel, the place may be out of view still, the jump to it
      // under way: the popover opens at the top of the view rather than off it.
      let place = range.flatMap(referenceRect(for:))?.offsetBy(dx: origin.x, dy: origin.y)
      let rect =
        place.flatMap { visible.intersects($0) ? $0 : nil }
        ?? CGRect(x: visible.midX, y: visible.minY + 40, width: 1, height: 1)
      popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }

    func closeNoteEditor() {
      notePopover?.close()
      notePopover = nil
    }
  }
#endif
