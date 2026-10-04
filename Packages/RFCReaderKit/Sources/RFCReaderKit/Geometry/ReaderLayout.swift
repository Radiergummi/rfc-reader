import CoreGraphics

/// How wide the text column is, given how wide the view is and how wide the reader
/// wants its text.
///
/// A function of those two and nothing else, which is why it lives here rather
/// than inside the text view: the reader has to know the column *before* it
/// builds, because artwork scaling and table shape are measured against it, and a
/// document built against a guess has to be thrown away and built again.
public enum ReaderLayout {
  /// The design ceiling on the column: below this width the column tracks the view
  /// exactly (less `margin` on each side); above it the gutters grow instead, so
  /// the measure never exceeds what is comfortable to read.
  public static let idealMeasure: CGFloat = 712

  /// The smallest gutter beside the column, and the padding under the last line.
  public static let margin: CGFloat = 24

  /// The narrowest the reader's pane may be dragged to.
  ///
  /// The split view's other two columns declare their own minima; the detail
  /// column declared none, so it absorbed every pixel of a shrinking window and
  /// could be crushed to a few characters wide. This leaves a 372 pt column, a
  /// little wider than an iPhone's, and puts the window's floor at 900 pt with all
  /// three columns showing.
  public static let minimumPaneWidth: CGFloat = 420

  /// The narrowest the Mac's sidebar and list columns may be dragged to.
  public static let sidebarMinimum: CGFloat = 200
  public static let listMinimum: CGFloat = 280
  /// How wide the Mac's contents panel is drawn, and the most and least it can be.
  public static let panelWidth: CGFloat = 320

  /// The narrowest the Mac's window may be: the two fixed columns plus a readable
  /// pane, so dragging a column's floor cannot leave the window's behind.
  ///
  /// Less the panel's width while it shows. AppKit adds an open inspector's thickness
  /// on top of `contentMinSize`, so a fixed 900 pt minimum became 1222 the moment the
  /// panel appeared and the window grew to meet it — which widens the pane, changes
  /// the column, rebuilds the document and loses the reader's place. Taken off, the
  /// floor AppKit enforces is the same open or shut, and the window never moves.
  public static func minimumWindowWidth(panelIsOpen: Bool) -> CGFloat {
    sidebarMinimum + listMinimum + minimumPaneWidth - (panelIsOpen ? panelWidth : 0)
  }

  /// Both the build and the text view's inset ask this, with the same two inputs;
  /// the column is only ever what the gutters leave, so the two cannot drift.
  public static func gutter(forWidth width: CGFloat, measure: MeasurePreference) -> CGFloat {
    switch measure {
    case .recommended: max(margin, (width - idealMeasure) / 2)
    case .fullWidth: margin
    }
  }

  public static func column(forWidth width: CGFloat, measure: MeasurePreference) -> CGFloat {
    width - gutter(forWidth: width, measure: measure) * 2
  }

  /// The inset a hosted header takes, given what it measured when `offered` a
  /// height. A header with no height of its own — `EmptyView`, as a link preview's
  /// reader has (#29) — answers with the height it was offered, 1.8e308, and that
  /// inset made the text view's frame height NaN, which AppKit traps on. Such a
  /// header has no height.
  public static func headerHeight(measured: CGFloat, offered: CGFloat) -> CGFloat {
    measured < offered ? measured : 0
  }

  /// The scroll view's origin for a scroll to `target`, kept to what it can show:
  /// no higher than the top, under the toolbar's `topInset`, and no lower than where
  /// the end of the text, with `bottomInset` under it, meets the bottom of the
  /// viewport. Text shorter than the viewport sits at the top. AppKit's clip view
  /// and UIKit's offset take any origin they are given, so a jump that pins a line
  /// near the end at the top, and a reveal that moves it a third down from there, had
  /// scrolled past the end and back up under the toolbar.
  ///
  /// `contentHeight` is nil while the end is an estimate, under viewport layout,
  /// which only the top is then held to: an estimate short of the real end would pull
  /// a jump short of its line (`docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`).
  public static func scrollOrigin(
    _ target: CGFloat, contentHeight: CGFloat?, viewportHeight: CGFloat, topInset: CGFloat,
    bottomInset: CGFloat
  ) -> CGFloat {
    let highest = -topInset
    guard let contentHeight else { return max(target, highest) }
    let lowest = max(highest, contentHeight + bottomInset - viewportHeight)
    return min(max(target, highest), lowest)
  }
}
