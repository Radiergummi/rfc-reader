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
    /// Whether a finger panned it: a pan, or the deceleration after one. Not a
    /// drag of the scroll indicator; see `Drag`.
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

  /// One drag on the text view, from the finger coming down to it lifting, told
  /// apart by how the text moves against the finger.
  ///
  /// A pan moves the text with the finger, which moves the offset against it. A
  /// drag of the scroll indicator moves the offset the way the finger goes, and
  /// much further, because the indicator stands for the whole document: down it
  /// and back up, it hid and showed the bars as fast as the finger turned. It is
  /// one interaction that neither hides nor shows them, so only a pan is
  /// `Scroll.isUserDriven`. Decided once, by the first movement of both the text
  /// and the finger, so a pan that wobbles at its end stays a pan.
  public struct Drag: Equatable, Sendable {
    /// Nil until the text and the finger first move together.
    public private(set) var kind: DragKind?
    private var startOffset: CGFloat
    private let startFinger: CGFloat
    private var isLifted = false

    /// `offset` is the content offset, growing down the document; `finger` is the
    /// pan's translation, growing down the screen.
    public init(offset: CGFloat, finger: CGFloat) {
      startOffset = offset
      startFinger = finger
    }

    /// Text that moves while the finger stays is not the finger's — the layout
    /// engine's pin after the header changed height, an inset clamping the offset,
    /// an offset applied before the pan's translation catches up — and decides
    /// nothing: the drag is measured from where it was moved to.
    public mutating func moved(offset: CGFloat, finger: CGFloat) {
      guard kind == nil else { return }
      let textMoved = offset - startOffset
      guard textMoved != 0 else { return }
      let fingerMoved = finger - startFinger
      guard fingerMoved != 0 else {
        startOffset = offset
        return
      }
      kind = textMoved * fingerMoved < 0 ? .pan : .indicator
    }

    /// The finger came off the text with the scroll still decelerating, which is
    /// still this drag's. The next touch starts another, even one the delegate
    /// hears nothing of: a finger that stops a deceleration and lifts without
    /// dragging ends neither the drag nor the deceleration, so this one is still
    /// there when that touch scrolls.
    public mutating func lifted() {
      isLifted = true
    }

    /// Whether a scroll in this drag is the reader's to hide or show the bars by:
    /// a pan, with the finger down or the scroll it flung decelerating, and not a
    /// scroll the layout engine makes during it.
    public func isUserDriven(touching: Bool, decelerating: Bool, engineMoving: Bool) -> Bool {
      kind == .pan && !engineMoving && (touching || decelerating)
    }

    /// The drag a scroll belongs to, given `drag`, the one before it.
    ///
    /// With a finger down (`touching`), a scroll with no drag, or only a lifted
    /// one, starts a drag, undecided until the text moves again. Without a finger,
    /// the drag is left as it is: a deceleration is still the pan's.
    public static func following(
      _ drag: Drag?, offset: CGFloat, finger: CGFloat, touching: Bool
    ) -> Drag? {
      guard touching else { return drag }
      var current = drag ?? Drag(offset: offset, finger: finger)
      if current.isLifted {
        current = Drag(offset: offset, finger: finger)
      }
      current.moved(offset: offset, finger: finger)
      return current
    }
  }

  /// What a `Drag` turned out to be.
  public enum DragKind: Equatable, Sendable {
    case pan
    case indicator
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
