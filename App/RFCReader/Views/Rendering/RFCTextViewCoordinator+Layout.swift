import RFCKit
import RFCReaderKit
import SwiftUI
import os

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension RFCTextViewCoordinator {
  // MARK: - Storage

  /// Swaps in a document and puts the reader's place back on it; the engine lays out
  /// what that needs and the rest in the background (`ReaderLayoutEngine`).
  func install(_ built: BuiltDocument, folding: Folding = Folding()) {
    guard let textView,
      let layout = textView.textLayoutManager,
      let storage = layout.textContentManager as? NSTextContentStorage
    else { return }
    #if !canImport(UIKit)
      // A preview timing or shown belongs to the document being replaced, and its
      // range means nothing in the new one.
      hover.send(.reset)
    #endif
    self.built = built
    lastReportedAnchor = nil
    sectionIndex = built.anchors.sections
    deriveAccessibilityItems()
    // Before the text, so the first layout skips what the reading mode folds.
    let foldingIndex = FoldingIndex(built)
    self.foldingIndex = foldingIndex
    self.folding = folding
    reportedFolding = nil
    forgetBands()
    foldingDelegate.fold(foldingIndex, by: folding, bands: RequirementBands())
    // Through `install`, never by assigning `storage.attributedString`, which
    // discards the text storage that selection and link clicks go through while
    // rendering perfectly. `NSTextContentStorage.install(_:)` has the story, and
    // `StorageInstallTests` pins it.
    signposter.withIntervalSignpost("Install document") {
      storage.install(built.text)
    }
    reportSelection()
    engine.installed(built, document: documentID)
    indexOverlay.installed(built) { [weak self] group in self?.jumpToIndexGroup(group) }
    reportVisibleAnchor()
    findBands()
  }

  // MARK: - Reading modes

  /// Folds what `folding` hides and unfolds the rest (#698): the storage stays as it
  /// is, the layout is made again, and the reader's line stays on top, or moves to
  /// the shown paragraph nearest it where its own is folded, or to `place`.
  ///
  /// From the scene, `folding` may be the one before a change this coordinator made
  /// itself and reported (`show`), whose report has not landed yet: that is ignored,
  /// or it would fold back what was just opened.
  func apply(_ folding: Folding, placeAt place: Int? = nil) {
    if let reported = reportedFolding {
      if folding == reported.before { return }
      if folding == reported.after { reportedFolding = nil }
    }
    guard folding != self.folding, let foldingIndex else { return }
    // Focus with no section yet: the one the reader's line is in; Implementer
    // becoming the outline: with the line's section open. Told to the scene as a
    // change of the coordinator's own. Unless there is none, which leaves nothing
    // to tell, and nothing to clear the report.
    let line = engine.placeOffset ?? 0
    let resolved = folding.focusingOnLine(at: line, in: foldingIndex)
      .keepingLine(at: line, after: self.folding, in: foldingIndex)
    if resolved != folding {
      reportedFolding = (folding, resolved)
      Task { self.onFoldingChange(resolved) }
    }
    let folding = resolved
    let place = place ?? folding.placeOfFocus(after: self.folding, in: foldingIndex)
    self.folding = folding
    // A new layout even when only a disclosure turned, or the bands came or went:
    // the chevron and the bands are drawn by the fragments, which have to be drawn
    // again.
    foldingDelegate.fold(foldingIndex, by: folding, bands: requirementBands ?? RequirementBands())
    engine.refold(foldingDelegate.hidden, placeAt: place)
    findBands()
    #if !canImport(UIKit)
      // Leaving the outline too, whose arrows go with it.
      if let textView { textView.window?.invalidateCursorRects(for: textView) }
    #endif
    reportVisibleAnchor()
  }

  /// The document's requirements, which come after its build (#700): their bands
  /// are found again, if Implementer is drawing them.
  func setRequirements(_ requirements: [Requirement]) {
    // Usually the same array, which compares by its storage first.
    guard requirements != self.requirements else { return }
    self.requirements = requirements
    forgetBands()
    findBands()
  }

  /// In a mode that bands the requirements, finds where they are in the installed
  /// build, off the main actor, and draws them once found, with the reader's line
  /// kept. Once per build and requirements, and only when asked for.
  private func findBands() {
    guard folding.mode.bandsRequirements, requirementBands == nil, bandsTask == nil,
      let built, !requirements.isEmpty
    else { return }
    let requirements = requirements
    bandsTask = Task {
      let bands = await Self.bands(of: requirements, in: built)
      // A later build or requirements have forgotten this task and started their own.
      guard self.built?.text === built.text, self.requirements == requirements else { return }
      bandsTask = nil
      requirementBands = bands
      guard folding.mode.bandsRequirements, let foldingIndex else { return }
      foldingDelegate.fold(foldingIndex, by: folding, bands: bands)
      engine.refold(foldingDelegate.hidden)
    }
  }

  /// Off the main actor, as the requirements are extracted: every sentence is looked
  /// for by its words, over the whole build.
  @concurrent
  private static func bands(of requirements: [Requirement], in built: BuiltDocument) async
    -> RequirementBands
  {
    RequirementBands(requirements, in: built)
  }

  /// Drops the bands of the build or requirements being replaced, and stops finding
  /// them.
  private func forgetBands() {
    bandsTask?.cancel()
    bandsTask = nil
    requirementBands = nil
  }

  /// A click or tap on a heading in the outline opens its section, or closes it;
  /// answers whether there was a heading to toggle there. From an event, not an
  /// update, so the scene is told at once.
  func toggleSection(atHeading offset: Int) -> Bool {
    guard let foldingIndex, let toggled = folding.toggling(heading: offset, in: foldingIndex)
    else { return false }
    apply(toggled)
    onFoldingChange(toggled)
    return true
  }

  /// A jump to `offset`, which the reading mode may have folded away: its section is
  /// expanded and the line put there, in one layout. Answers whether it did, which
  /// leaves the jump nothing to do.
  func show(_ offset: Int) -> Bool {
    guard let foldingIndex, foldingDelegate.hidden.contains(offset) else { return false }
    let before = folding
    let expanded = folding.expanding(toShow: offset, in: foldingIndex)
    apply(expanded, placeAt: offset)
    // After `apply`, which would take `expanded` for the scene catching up and forget
    // the report before it was made.
    reportedFolding = (before, expanded)
    // Deferred: a jump can run inside SwiftUI's update, where mutating state is illegal.
    Task { self.onFoldingChange(expanded) }
    return true
  }

  // MARK: - Geometry

  /// Centers the column and hangs the header in the top inset.
  ///
  /// This runs on every update pass — and an update pass happens on every section
  /// crossing, because `visibleAnchor` is `@State` — so nothing is written unless
  /// the gutter, the column or the header's height moved. A relayout costs more
  /// still, and only the column can force one: under the recommended measure, a
  /// window wider than it moves the gutters, not the text. Full width has no such
  /// slack — every change of width is a change of column, and re-wraps.
  ///
  /// `measure` is the live preference, which runs ahead of the storage for as long
  /// as a flip takes to rebuild, exactly as the width does during a resize: the
  /// text re-wraps at the new column at once and the rebuild re-measures artwork
  /// and tables for it when it lands.
  func layOut(width: CGFloat, measure: MeasurePreference) {
    guard let textView, width > 0 else { return }
    let gutter = ReaderLayout.gutter(forWidth: width, measure: measure)
    let column = ReaderLayout.column(forWidth: width, measure: measure)
    // Measured every pass, deliberately: the height depends on the width, on the
    // content size category, and on metadata that can arrive after the first
    // layout, and a cache keyed on any one of those goes stale as a header
    // overlapping the first paragraph. Only the writes below are conditional.
    let offered = CGFloat.greatestFiniteMagnitude
    let measured =
      headerHost?.sizeThatFits(in: CGSize(width: column, height: offered)).height ?? 0
    let headerHeight = ReaderLayout.headerHeight(measured: measured, offered: offered)
    guard column != laidOutColumn || gutter != laidOutGutter || headerHeight != laidOutHeaderHeight
    else { return }
    let columnChanged = column != laidOutColumn
    laidOutColumn = column
    laidOutGutter = gutter
    laidOutHeaderHeight = headerHeight

    #if canImport(UIKit)
      textView.textContainerInset = UIEdgeInsets(
        top: headerHeight, left: gutter, bottom: ReaderLayout.margin, right: gutter)
    #else
      // AppKit's inset is symmetric, so the header's height is echoed as padding
      // under the last line. NSTextView has no asymmetric equivalent.
      textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
      textView.textContainerInset = NSSize(width: gutter, height: headerHeight)
    #endif
    headerHost?.view.frame = CGRect(x: gutter, y: 0, width: column, height: headerHeight)

    // The container is the column, set here and nowhere else. Tracking the text
    // view's width instead re-wrapped the storage on *every* resize: the frame
    // and the inset cannot change in one step, so the container passed through a
    // width that was neither the old column nor the new one, and TextKit threw
    // away the whole document's layout for it — measured on RFC 9000, a resize
    // that only moved the gutters left the reader 39,000 characters further on,
    // with no rebuild coming to put it back.
    //
    // `DocumentView` derives the column from the same width and rebuilds, which
    // lands in `install()`; until it does, the engine holds the reader's line on
    // the storage re-wrapped at the new column.
    if columnChanged {
      #if canImport(UIKit)
        textView.textContainer.size = CGSize(width: column, height: .greatestFiniteMagnitude)
      #else
        textView.textContainer?.size = NSSize(width: column, height: .greatestFiniteMagnitude)
      #endif
      engine.columnChanged()
    } else {
      // The gutter or the header moved the container in the view: the same line stays on top.
      engine.pin()
    }
    updateIndexOverlay()
  }
}
