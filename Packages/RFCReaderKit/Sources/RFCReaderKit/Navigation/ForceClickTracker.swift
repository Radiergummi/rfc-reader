/// A References panel row's force click on the Mac (#580), from the window's mouse
/// and pressure events, which SwiftUI has no gesture for: `ForceClickReader` feeds it
/// what it sees, and does what comes out.
///
/// A force click counts once per click, and only for a click that began on the row
/// and is still on it: a press dragged in from elsewhere is not a click on this row.
public struct ForceClickTracker {
  public enum Event: Equatable {
    case mouseDown(inside: Bool)
    case mouseUp
    case pressure(stage: Int, inside: Bool)
  }

  public enum Outcome: Equatable {
    /// A click began on the row: whatever the last one left is over.
    case pressBegan
    /// The click pressed through to the second stage on the row.
    case forceClick
  }

  /// Whether the mouse went down on the row, and is still down.
  private var isPressing = false
  /// Whether this click has reported its force click already: stage 2 arrives again
  /// with every change of pressure past it.
  private var hasReported = false

  public init() {}

  public mutating func handle(_ event: Event) -> Outcome? {
    switch event {
    case .mouseDown(let inside):
      isPressing = inside
      hasReported = false
      return inside ? .pressBegan : nil
    case .mouseUp:
      isPressing = false
      return nil
    case .pressure(let stage, let inside):
      guard isPressing, inside, stage >= 2, !hasReported else { return nil }
      hasReported = true
      return .forceClick
    }
  }
}
