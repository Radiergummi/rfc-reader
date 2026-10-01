import CoreGraphics

/// Whether the reader's bars are out of the way, on iPhone: reading on hides them,
/// and a tap, scrolling back, reaching either end of the document or jumping to a
/// place brings them back, as Books and Safari do.
///
/// Fed by the text view's scrolls and taps. Only a scroll the reader makes can hide
/// the bars or show them by its direction; one the app makes — a jump, a restored
/// place — moves where the next run is measured from and nothing else.
public struct ReaderChrome: Equatable, Sendable {
  /// One scroll, as the text view saw it.
  public struct Scroll: Equatable, Sendable {
    /// Where the text is on screen, y growing down the document: what the reader
    /// sees move. Not `distanceFromTop`, which also changes when the bars go and
    /// the top bar's inset with them while the text stays where it was.
    public var position: CGFloat
    /// How far the top of what is visible is below the top of the document.
    public var distanceFromTop: CGFloat
    /// How far the document can still scroll down; zero or less at its end.
    public var distanceToEnd: CGFloat
    /// Whether a finger moved it: dragging, or the deceleration after one.
    public var isUserDriven: Bool
    /// Whether it is the deceleration after a fling, the finger off the glass.
    public var isFlinging: Bool

    public init(
      position: CGFloat, distanceFromTop: CGFloat, distanceToEnd: CGFloat, isUserDriven: Bool,
      isFlinging: Bool = false
    ) {
      self.position = position
      self.distanceFromTop = distanceFromTop
      self.distanceToEnd = distanceToEnd
      self.isUserDriven = isUserDriven
      self.isFlinging = isFlinging
    }

    /// The scroll a scroll view is at, from its offset, its insets and its size.
    /// The position is the offset alone, which the insets changing leaves where it
    /// is.
    public init(
      offset: CGFloat, topInset: CGFloat, bottomInset: CGFloat, contentHeight: CGFloat,
      viewportHeight: CGFloat, isUserDriven: Bool, isFlinging: Bool = false
    ) {
      self.init(
        position: offset,
        distanceFromTop: offset + topInset,
        distanceToEnd: contentHeight + bottomInset - viewportHeight - offset,
        isUserDriven: isUserDriven, isFlinging: isFlinging)
    }
  }

  /// How far a scroll down runs before the bars go: a nudge to settle a line is
  /// not reading on.
  public static let hideDistance: CGFloat = 44
  /// How far a scroll back runs before the bars return: less than the way down,
  /// because someone scrolling back is usually looking for them, but not so little
  /// that a finger's wobble at the end of a drag brings them back.
  public static let showDistance: CGFloat = 20
  /// How near either end of the document the bars stay. More than the bottom bar
  /// is tall: the bars going takes its height off the bottom inset, and so off the
  /// distance to the end, and nearer than this that would land on the end, where
  /// the bars come straight back.
  public static let hideFloor: CGFloat = 120

  public private(set) var isHidden = false

  /// Whether the bars may go at all: in a single column, and not under VoiceOver,
  /// where a control that leaves may be gone before it is reached. Turning it off
  /// brings them back.
  public var isEnabled = false {
    didSet { if !isEnabled { isHidden = false } }
  }

  private var last: Scroll?
  /// Where the current run began, and which way it goes.
  private var runStart: CGFloat?
  private var runsDown: Bool?

  public init() {}

  public mutating func scrolled(_ scroll: Scroll) {
    defer { last = scroll }
    if scroll.distanceFromTop <= 0 || scroll.distanceToEnd <= 0 {
      isHidden = false
      restartRun()
      return
    }
    guard scroll.isUserDriven, let previous = last?.position else {
      restartRun()
      return
    }
    let position = scroll.position
    let delta = position - previous
    guard delta != 0 else { return }
    let down = delta > 0
    // A fling cannot turn by itself: what moves against it is the scroll view
    // keeping the text in place as TextKit corrects its estimates.
    if scroll.isFlinging, let runsDown, down != runsDown { return }
    if down != runsDown || runStart == nil {
      runsDown = down
      runStart = previous
    }
    guard let runStart else { return }
    if down {
      if position - runStart >= Self.hideDistance, Self.mayHide(at: scroll), isEnabled {
        isHidden = true
      }
    } else if runStart - position >= Self.showDistance {
      isHidden = false
    }
  }

  /// A tap on the text, not on a link: brings hidden bars back and puts shown ones
  /// away, where they may go.
  public mutating func tapped() {
    if isHidden {
      isHidden = false
    } else if isEnabled, let last, Self.mayHide(at: last) {
      isHidden = true
    }
    restartRun()
  }

  /// The reader was taken somewhere — a link, a contents row, Back within the
  /// document — and should see where it landed, with the way back in reach.
  public mutating func jumped() {
    isHidden = false
    restartRun()
  }

  /// The reader's top content inset for the top safe area, which is the top bar's
  /// bottom edge.
  ///
  /// While the bars are hidden it holds at their height rather than following the
  /// safe area in: what the uncovered viewport is measured from does not move, so a
  /// jump made while they are hidden lands its place just below where the bar comes
  /// back, and the bars going or coming back is no change of inset at all.
  public static func topInset(
    current: CGFloat, safeArea: CGFloat, barsHidden: Bool
  ) -> CGFloat {
    barsHidden ? max(current, safeArea) : safeArea
  }

  private static func mayHide(at scroll: Scroll) -> Bool {
    scroll.distanceFromTop >= hideFloor && scroll.distanceToEnd >= hideFloor
  }

  private mutating func restartRun() {
    runStart = nil
    runsDown = nil
  }
}
