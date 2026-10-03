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
  func install(_ built: BuiltDocument) {
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
    // Through `install`, never by assigning `storage.attributedString`, which
    // discards the text storage that selection and link clicks go through while
    // rendering perfectly. `NSTextContentStorage.install(_:)` has the story, and
    // `StorageInstallTests` pins it.
    signposter.withIntervalSignpost("Install document") {
      storage.install(built.text)
    }
    reportSelection()
    engine.installed(built, document: documentID)
    reportVisibleAnchor()
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
  }
}
