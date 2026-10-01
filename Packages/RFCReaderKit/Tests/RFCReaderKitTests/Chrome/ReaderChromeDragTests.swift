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

  /// Whatever moves the text while the finger stays, it is not the finger.
  @Test func `text that moves under a still finger is not a pan`() {
    var drag = ReaderChrome.Drag(offset: 1_000, finger: 0)
    drag.moved(offset: 4_000, finger: 0)
    #expect(drag.kind == .indicator)
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
      nil, offset: 1_000, finger: 0, touching: true, holding: false)
    #expect(started != nil)
    #expect(started?.kind == nil)
    let moved = ReaderChrome.Drag.following(
      started, offset: 9_000, finger: 40, touching: true, holding: false)
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
      flick, offset: 5_000, finger: 0, touching: true, holding: false)
    let moved = ReaderChrome.Drag.following(
      next, offset: 9_000, finger: 40, touching: true, holding: false)
    #expect(moved?.kind == .indicator)
  }

  /// The deceleration after a pan is still that pan's: lifting the finger keeps
  /// it until a touch starts another.
  @Test func `a lifted drag lasts through its deceleration`() {
    var flick = ReaderChrome.Drag(offset: 1_000, finger: 0)
    flick.moved(offset: 1_040, finger: -40)
    flick.lifted()
    let decelerating = ReaderChrome.Drag.following(
      flick, offset: 1_400, finger: -40, touching: false, holding: false)
    #expect(decelerating?.kind == .pan)
  }

  /// The header's hold moves the text under a finger that has not moved it yet:
  /// that is not the finger, and decided by it, the whole pan would count as the
  /// indicator's. A drag already decided stays decided.
  @Test func `the header's hold restarts an undecided drag, not a decided one`() {
    let undecided = ReaderChrome.Drag(offset: 1_000, finger: 0)
    let held = ReaderChrome.Drag.following(
      undecided, offset: 1_081, finger: 0, touching: true, holding: true)
    let panned = ReaderChrome.Drag.following(
      held, offset: 1_121, finger: -40, touching: true, holding: false)
    #expect(panned?.kind == .pan)

    var pan = ReaderChrome.Drag(offset: 1_000, finger: 0)
    pan.moved(offset: 1_040, finger: -40)
    let stillPan = ReaderChrome.Drag.following(
      pan, offset: 1_121, finger: -40, touching: true, holding: true)
    #expect(stillPan?.kind == .pan)
  }
}
