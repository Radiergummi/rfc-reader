import Foundation
import Testing

@testable import RFCReaderKit

/// A drag on the reader is a pan, which moves the bars, or a drag of the scroll
/// indicator, which does not (#492).
///
/// The offsets are the text view's content offset, which grows down the document,
/// and the finger is the pan's translation, which grows down the screen.
@Suite("Reader chrome: a drag")
struct ReaderChromeDragTests {
  @Test func `a drag that moves the text against the finger is a pan`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 1_040, finger: -40)
    #expect(drag.kind == .pan)
  }

  /// Back up the document, the finger going down.
  @Test func `a pan back up is a pan too`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 960, finger: 40)
    #expect(drag.kind == .pan)
  }

  /// The indicator stands for the whole document: a finger moving down it moves
  /// the text down the document, and much further than the finger went.
  @Test func `a drag that moves the text with the finger is the indicator's`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 9_000, finger: 40)
    #expect(drag.kind == .indicator)
  }

  /// Whatever moves the text while the finger stays — the engine's pin after the
  /// header changed height, an inset clamping the offset, the offset applied before
  /// the pan's translation catches up — it is not the finger, and decides nothing.
  /// The drag is measured from there on, so the finger's own movement decides it.
  @Test func `text that moves under a still finger decides nothing`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 4_000, finger: 0)
    #expect(drag.kind == nil)
    drag.moved(offset: 4_040, finger: -40)
    #expect(drag.kind == .pan)
  }

  /// Measured from where the text was moved to, not where the drag began: from the
  /// start, 1,081 to 1,061 would read as the text moving down the document.
  @Test func `a pan after the text moved under the finger is a pan`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 1_081, finger: 0)
    drag.moved(offset: 1_061, finger: 20)
    #expect(drag.kind == .pan)
  }

  @Test func `nothing is decided until the text moves`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 1_000, finger: 30)
    #expect(drag.kind == nil)
  }

  /// One drag is one interaction: an indicator drag that turns back up is still
  /// the indicator's, and a pan that wobbles at its end is still a pan.
  @Test func `a drag is told apart once, by its first movement`() {
    var indicator = ReaderChrome.Drag(offset: 1_000, finger: 0)
    indicator.moved(offset: 9_000, finger: 40)
    indicator.moved(offset: 2_000, finger: -10)
    #expect(indicator.kind == .indicator)

    var pan = ReaderChrome.Drag(offset: 1_000, finger: 0)
    pan.moved(offset: 1_040, finger: -40)
    pan.moved(offset: 1_045, finger: 5)
    #expect(pan.kind == .pan)
  }

  /// A scroll with a finger down and no drag yet starts one, undecided until the
  /// text moves again, and decided by the movement after.
  @Test func `a touch with no drag starts one`() {
    let started = ReaderChrome.Drag.following(
      nil, offset: 1_000, finger: 0, touching: true)
    #expect(started != nil)
    #expect(started?.kind == nil)
    let moved = ReaderChrome.Drag.following(
      started, offset: 9_000, finger: 40, touching: true)
    #expect(moved?.kind == .indicator)
  }

  /// A finger that stops a flick's deceleration and lifts without dragging tells
  /// the delegate nothing, so the flick's drag is still there when the next touch
  /// scrolls. Lifted, it is over, and the next touch is a drag of its own.
  @Test func `a touch after a lifted drag starts a new one`() {
    var flick = ReaderChrome.Drag(offset: 1_000, finger: 0)
    flick.moved(offset: 1_040, finger: -40)
    flick.lifted()
    let next = ReaderChrome.Drag.following(
      flick, offset: 5_000, finger: 0, touching: true)
    let moved = ReaderChrome.Drag.following(
      next, offset: 9_000, finger: 40, touching: true)
    #expect(moved?.kind == .indicator)
  }

  /// The deceleration after a pan is still that pan's: lifting the finger keeps
  /// it until a touch starts another.
  @Test func `a lifted drag lasts through its deceleration`() {
    var flick = ReaderChrome.Drag(offset: 1_000, finger: 0)
    flick.moved(offset: 1_040, finger: -40)
    flick.lifted()
    let decelerating = ReaderChrome.Drag.following(
      flick, offset: 1_400, finger: -40, touching: false)
    #expect(decelerating?.kind == .pan)
  }

  /// Only a pan moves the bars, while the finger is on the glass or the scroll it
  /// flung decelerates, and never during a scroll the layout engine makes.
  @Test func `only a pan the finger makes is user driven`() {
    var pan = ReaderChrome.Drag(offset: 1_000, finger: 0)
    pan.moved(offset: 1_040, finger: -40)
    var indicator = ReaderChrome.Drag(offset: 1_000, finger: 0)
    indicator.moved(offset: 9_000, finger: 40)
    let undecided = ReaderChrome.Drag(offset: 1_000, finger: 0)

    #expect(pan.isUserDriven(touching: true, decelerating: false, engineMoving: false))
    #expect(pan.isUserDriven(touching: false, decelerating: true, engineMoving: false))
    #expect(!pan.isUserDriven(touching: false, decelerating: false, engineMoving: false))
    #expect(!pan.isUserDriven(touching: true, decelerating: false, engineMoving: true))
    #expect(!indicator.isUserDriven(touching: true, decelerating: false, engineMoving: false))
    #expect(!undecided.isUserDriven(touching: true, decelerating: false, engineMoving: false))
  }
}
