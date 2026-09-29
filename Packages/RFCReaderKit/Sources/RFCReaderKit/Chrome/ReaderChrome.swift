import CoreGraphics

/// Whether the reader's bars are out of the way, on iPhone: reading on hides them,
/// and a tap, scrolling back, reaching either end of the document or jumping to a
/// place brings them back, as Books and Safari do.
///
/// Fed by the text view's scrolls and taps. Only a scroll the reader makes can hide
/// the bars or show them by its direction; one the app makes — a jump, a restored
/// place, the text view keeping the text still while the bars go — moves where the
/// next run is measured from and nothing else.
public struct ReaderChrome: Equatable, Sendable {
  /// One scroll, as the text view saw it.
  public struct Scroll: Equatable, Sendable {
    /// Where the text is on screen, y growing down the document: what the reader
    /// sees move. Not the scroll offset alone, which also changes when the bars go
    /// and the text view grows under them while the text stays where it was.
    public var position: CGFloat
    /// How far the top of what is visible is below the top of the document.
    public var distanceFromTop: CGFloat
    /// How far the document can still scroll down; zero or less at its end.
    public var distanceToEnd: CGFloat
    /// Whether a finger moved it: dragging, or the deceleration after one.
    public var isUserDriven: Bool

    public init(
      position: CGFloat, distanceFromTop: CGFloat, distanceToEnd: CGFloat, isUserDriven: Bool
    ) {
      self.position = position
      self.distanceFromTop = distanceFromTop
      self.distanceToEnd = distanceToEnd
      self.isUserDriven = isUserDriven
    }
  }

  /// How far a scroll down runs before the bars go: a nudge to settle a line is
  /// not reading on.
  public static let hideDistance: CGFloat = 44
  /// How far a scroll back runs before the bars return: less than the way down,
  /// because someone scrolling back is usually looking for them, but not so little
  /// that a finger's wobble at the end of a drag brings them back.
  public static let showDistance: CGFloat = 20
  /// How far into the document the bars first may go. More than the top bar is
  /// tall: when it goes, the text view grows up into its place and the scroll
  /// offset falls by its height to keep the text still, and from here that leaves
  /// the offset clear of the top, where the bars come back.
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
    let delta = scroll.position - previous
    guard delta != 0 else { return }
    let down = delta > 0
    if down != runsDown || runStart == nil {
      runsDown = down
      runStart = previous
    }
    guard let runStart else { return }
    if down {
      if scroll.position - runStart >= Self.hideDistance, Self.mayHide(at: scroll), isEnabled {
        isHidden = true
      }
    } else if runStart - scroll.position >= Self.showDistance {
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

  private static func mayHide(at scroll: Scroll) -> Bool {
    scroll.distanceFromTop >= hideFloor && scroll.distanceToEnd > 0
  }

  private mutating func restartRun() {
    runStart = nil
    runsDown = nil
  }
}
