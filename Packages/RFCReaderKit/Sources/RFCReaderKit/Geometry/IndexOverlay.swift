import Foundation

/// What the index's overlays show, as functions of where the reader is: the App
/// target reads the viewport and places views by these, and decides nothing itself.
/// Offsets are UTF-16 offsets into the built text; distances are points from the top
/// of the part of the viewport the bars leave uncovered, down positive.
extension IndexMap {
  /// Whether any of the index is on screen: its range meets `visible` somewhere a
  /// folding does not hide. The viewport can span a folded index, as the outline
  /// shows the headings around it.
  public func isShowing(visible: NSRange, hidden: HiddenText) -> Bool {
    guard !isEmpty else { return false }
    let shown = NSIntersectionRange(range, visible)
    guard shown.length > 0 else { return false }
    // The runs are in order and do not overlap: skip every one that covers where
    // the shown part has got to.
    var location = shown.location
    for run in hidden.ranges {
      if run.location > location { break }
      location = max(location, NSMaxRange(run))
    }
    return location < NSMaxRange(shown)
  }

  /// The group the character at `offset` is in: the last whose letter starts at or
  /// before it. Nil above the first, where the index's own heading is.
  public func group(at offset: Int) -> Int? {
    groups.lastIndex { $0.labelRange.location <= offset }
  }
}

/// The current group's letter pinned at the top of the text, as Contacts pins a
/// section's.
public enum StickyLetter {
  /// How far above its place the letter is drawn, 0 or less; nil while it should not
  /// show at all, which is while the current group's own label is in view at or below
  /// the top, so a letter is never on screen twice. The next group's label, rising
  /// under the pinned letter, pushes it up by as much as they overlap.
  ///
  /// - Parameter currentLabelTop: where the current group's label starts, nil when
  ///   its fragment is not on screen (scrolled away above).
  /// - Parameter nextLabelTop: where the next group's label starts, nil when it is not
  ///   on screen.
  /// - Parameter height: the pinned letter's height.
  public static func offset(currentLabelTop: CGFloat?, nextLabelTop: CGFloat?, height: CGFloat)
    -> CGFloat?
  {
    if let currentLabelTop, currentLabelTop >= 0 { return nil }
    guard let nextLabelTop else { return 0 }
    return min(0, nextLabelTop - height)
  }
}
