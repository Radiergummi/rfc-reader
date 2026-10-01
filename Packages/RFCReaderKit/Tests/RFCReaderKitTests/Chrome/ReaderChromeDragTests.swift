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
}
