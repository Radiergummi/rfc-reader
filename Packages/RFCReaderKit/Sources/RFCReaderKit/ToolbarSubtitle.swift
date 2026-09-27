import CoreGraphics

/// What the subtitle under the reader's toolbar title says as the document scrolls.
///
/// The document's title until the first section's heading passes under the
/// toolbar — over the title page and the abstract, which belong to no section —
/// and from then on the heading of the section being read, each heading handing
/// over to the next as it passes. The hand-over scrubs with the scroll like the
/// title's own reveal (`ToolbarTitleReveal`), so scrolling back up plays it in
/// reverse without being told which way the reader is going.
///
/// Deliberately not the section tracking that feeds the contents' highlight and
/// the reading position (`ReadingPlaceTracker`): that one counts the abstract as
/// section one and switches as a heading reaches the top, where this names no
/// section over the abstract and switches as a heading's last line passes.
public enum ToolbarSubtitle {
  public struct State: Equatable, Sendable {
    /// The heading on its way out, nil for the document's title.
    public let outgoing: String?
    /// The heading on its way in, nil for the document's title.
    public let incoming: String?
    /// How far `incoming` has replaced `outgoing`, from 0 to 1.
    public let progress: CGFloat

    public init(outgoing: String?, incoming: String?, progress: CGFloat) {
      self.outgoing = outgoing
      self.incoming = incoming
      self.progress = progress
    }

    /// Nothing moving: `heading` shown outright.
    public static func steady(_ heading: String?) -> State {
      State(outgoing: heading, incoming: heading, progress: 1)
    }
  }

  /// - Parameters:
  ///   - sections: the section anchors, each carrying its heading as drawn.
  ///   - topFragmentStart: where the paragraph under the toolbar's bottom edge
  ///     starts, as a character offset.
  ///   - crossing: how far that paragraph's last line has passed under the edge
  ///     (`ToolbarTitleReveal.progress`). Only read when the paragraph is a
  ///     heading: that is the one paragraph whose crossing changes the section.
  public static func state(
    in sections: AnchorIndex,
    topFragmentStart: Int,
    crossing: CGFloat
  ) -> State {
    let entries = sections.entries
    guard let index = sections.index(at: topFragmentStart) else { return .steady(nil) }
    let current = entries[index]
    guard current.offset == topFragmentStart else { return .steady(current.heading) }
    let previous = index > 0 ? entries[index - 1].heading : nil
    return State(outgoing: previous, incoming: current.heading, progress: crossing)
  }

  /// How far a paragraph's last line has passed under the toolbar's edge: the
  /// `crossing` that `state` takes. The last line rather than the paragraph,
  /// because a heading's layout fragment carries the space above it, and a
  /// wrapped heading hands over as its last line passes, the way the title's
  /// reveal does.
  ///
  /// - Parameters:
  ///   - edge: the toolbar's bottom edge, in the coordinates `fragmentTop` is in.
  ///   - lastLine: the last line's bounds, relative to the fragment; nil when the
  ///     fragment has no lines, which then counts as one line its own height.
  public static func crossing(
    edge: CGFloat,
    fragmentTop: CGFloat,
    fragmentHeight: CGFloat,
    lastLine: CGRect?
  ) -> CGFloat {
    let line = lastLine ?? CGRect(x: 0, y: 0, width: 0, height: fragmentHeight)
    return ToolbarTitleReveal.progress(
      headingBottom: fragmentTop + line.maxY,
      visibleTop: edge,
      distance: line.height
    )
  }
}

/// Everything the reader tells its toolbar title as it scrolls: how far the title
/// has come in (`ToolbarTitleReveal`), and what its subtitle says.
public struct ToolbarTitleState: Equatable, Sendable {
  public let reveal: CGFloat
  public let subtitle: ToolbarSubtitle.State

  public init(reveal: CGFloat, subtitle: ToolbarSubtitle.State) {
    self.reveal = reveal
    self.subtitle = subtitle
  }

  /// The title in full, over the document's own title: where there is no header
  /// on screen to show them instead.
  public static let shown = ToolbarTitleState(reveal: 1, subtitle: .steady(nil))

  /// Nothing in the toolbar, because the header is showing it.
  public static let hidden = ToolbarTitleState(reveal: 0, subtitle: .steady(nil))
}
