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

  /// The container y to put at the viewport's top once the header above the text
  /// has changed from `oldHeight` to `newHeight`, given the viewport's top, in
  /// container coordinates, before it did — or nil when there is nothing to hold.
  ///
  /// The header is the text container's top inset, so a change of its height moves
  /// every line by the change while the scroll offset stays put. Metadata that
  /// arrives after a place was restored — the revisions banner, on a cold launch
  /// into a section — did exactly that, and left the end of the previous section
  /// showing above the place (#492). A line's container y does not move with the
  /// inset, so holding it is putting the same y back at the top.
  ///
  /// A viewport whose top is above the container is looking at the header, which
  /// belongs to no line, as `ReadingPlaceTracker` has it: there the header keeps
  /// its place on screen instead, and changes height in place — but a header that
  /// shrinks past the viewport's top leaves it at the text's first line, not in it.
  ///
  /// Nil on a change of column, which re-wraps the storage under the offset:
  /// the reader restores the place, or waits for its rebuild to.
  public static func containerTopAfterHeaderChange(
    viewportTop: CGFloat, from oldHeight: CGFloat, to newHeight: CGFloat, columnChanged: Bool
  ) -> CGFloat? {
    guard !columnChanged, newHeight != oldHeight else { return nil }
    guard viewportTop < 0 else { return viewportTop }
    return min(0, viewportTop + oldHeight - newHeight)
  }
}
