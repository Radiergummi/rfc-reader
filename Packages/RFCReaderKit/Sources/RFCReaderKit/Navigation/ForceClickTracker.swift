/// A References panel row's force click on the Mac (#580), from the window's mouse
/// and pressure events, which SwiftUI has no gesture for: `ForceClickReader` feeds it
/// what it sees, and does what comes out.
///
/// A force click counts once per click, and only for a click that began on the row
/// and is still on it: a press dragged in from elsewhere is not a click on this row.
/// The release of a click that pressed through opens nothing: the force click asked
/// for the preview, not the RFC.
///
/// A class, so that the row's button and the monitor watching the window's events
/// share one, and the pressure events, many a second, change nothing SwiftUI
/// observes.
public final class ForceClickTracker {
  public enum Event: Equatable {
    case mouseDown(inside: Bool)
    case mouseUp
    case pressure(stage: Int, inside: Bool)
  }

  /// Whether the mouse went down on the row, and is still down.
  private var isPressing = false
  /// Whether the last click pressed through: stage 2 arrives again with every change
  /// of pressure past it, and the click's release must not open the RFC. Kept until
  /// that release, or the next click, whatever the preview did meanwhile.
  private var hasPressedThrough = false

  public init() {}

  /// - Returns: Whether the event is the click pressing through to the second stage
  ///   on the row: the force click, once per click.
  public func handle(_ event: Event) -> Bool {
    switch event {
    case .mouseDown(let inside):
      isPressing = inside
      hasPressedThrough = false
      return false
    case .mouseUp:
      isPressing = false
      return false
    case .pressure(let stage, let inside):
      guard isPressing, inside, stage >= 2, !hasPressedThrough else { return false }
      hasPressedThrough = true
      return true
    }
  }

  /// The row's button was released, or pressed from the keyboard: whether that opens
  /// what the row names. Not after the click that pressed through, and once only, so
  /// the press after it opens again.
  public func opensOnRelease() -> Bool {
    defer { hasPressedThrough = false }
    return !hasPressedThrough
  }
}
