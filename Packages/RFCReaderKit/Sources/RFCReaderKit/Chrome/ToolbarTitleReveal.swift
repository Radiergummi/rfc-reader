import CoreGraphics

/// How far the document's title has come into the reader's toolbar, from 0 to 1.
///
/// The header shows the title in full while it is on screen; as its heading scrolls
/// up under the toolbar, the toolbar's copy rises in to replace it, scrubbing with
/// the scroll rather than playing an animation. The transition runs over the
/// heading's last line — `distance` — so the toolbar's title arrives exactly as the
/// header's leaves: 0 while that line is wholly below the toolbar's bottom edge, 1
/// once it has passed wholly under it.
public enum ToolbarTitleReveal {
  /// `headingBottom` and `visibleTop` — the toolbar's bottom edge — are in the same
  /// coordinates, y growing down the document.
  public static func progress(
    headingBottom: CGFloat,
    visibleTop: CGFloat,
    distance: CGFloat
  ) -> CGFloat {
    guard distance > 0 else { return visibleTop >= headingBottom ? 1 : 0 }
    let traveled = (visibleTop - (headingBottom - distance)) / distance
    return min(1, max(0, traveled))
  }

  /// How opaque the toolbar's title is at a given progress: nothing for the first
  /// half of its travel, then fading in over the second. It rises from under the
  /// toolbar's bottom edge, and text faded in from the start is seen being cut by
  /// that edge; by halfway most of it is clear of it.
  public static func opacity(atProgress progress: CGFloat) -> CGFloat {
    min(1, max(0, (progress - 0.5) * 2))
  }
}
