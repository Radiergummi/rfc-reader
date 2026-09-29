import Foundation
import Testing

@testable import RFCReaderKit

/// The reader's bars on iPhone: reading on hides them, a tap, scrolling back,
/// either end of the document or a jump brings them back.
@Suite("Reader chrome")
struct ReaderChromeTests {
  /// A document 10,000 pt long, scrolled by a finger unless said otherwise.
  private struct Reader {
    var chrome: ReaderChrome = {
      var chrome = ReaderChrome()
      chrome.isEnabled = true
      return chrome
    }()
    var offset: CGFloat = 0

    mutating func scroll(to offset: CGFloat, byFinger: Bool = true) {
      self.offset = offset
      chrome.scrolled(
        ReaderChrome.Scroll(
          position: offset, distanceFromTop: offset, distanceToEnd: 10_000 - offset,
          isUserDriven: byFinger))
    }

    mutating func scroll(by distance: CGFloat, byFinger: Bool = true) {
      scroll(to: offset + distance, byFinger: byFinger)
    }

    /// Into the document, well past where the bars may go, without hiding them.
    static func reading() -> Reader {
      var reader = Reader()
      reader.scroll(to: 2_000, byFinger: false)
      return reader
    }
  }

  @Test func `reading on past the distance hides the bars`() {
    var reader = Reader.reading()
    reader.scroll(by: 20)
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: 24)
    #expect(reader.chrome.isHidden)
  }

  @Test func `a nudge down does not hide them`() {
    var reader = Reader.reading()
    reader.scroll(by: ReaderChrome.hideDistance - 1)
    #expect(!reader.chrome.isHidden)
  }

  /// A run is measured from where the scroll last turned: down, a little back up,
  /// and down again does not add the two downs together.
  @Test func `a run starts where the scroll turned`() {
    var reader = Reader.reading()
    reader.scroll(by: 30)
    reader.scroll(by: -5)
    reader.scroll(by: 30)
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: 20)
    #expect(reader.chrome.isHidden)
  }

  @Test func `nothing hides near the top of the document`() {
    var reader = Reader()
    reader.scroll(to: 1)
    reader.scroll(to: ReaderChrome.hideFloor - 1)
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: ReaderChrome.hideDistance)
    #expect(reader.chrome.isHidden)
  }

  /// Hiding the bottom bar takes its height off the room to scroll past the last
  /// line, so nearer the end than that it would land on the end and show them again.
  @Test func `nothing hides near the end of the document`() {
    var reader = Reader()
    reader.scroll(to: 10_000 - ReaderChrome.hideFloor - ReaderChrome.hideDistance, byFinger: false)
    reader.scroll(by: ReaderChrome.hideDistance + 1)
    #expect(!reader.chrome.isHidden)
    reader.chrome.tapped()
    #expect(!reader.chrome.isHidden)
  }

  @Test func `scrolling back shows them`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    #expect(reader.chrome.isHidden)
    reader.scroll(by: -10)
    #expect(reader.chrome.isHidden, "a wobble at the end of a drag")
    reader.scroll(by: -10)
    #expect(!reader.chrome.isHidden)
  }

  @Test func `reaching the top shows them`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    reader.scroll(to: 0, byFinger: false)
    #expect(!reader.chrome.isHidden)
  }

  @Test func `reaching the end shows them`() {
    var reader = Reader()
    reader.scroll(to: 9_000, byFinger: false)
    reader.scroll(by: 100)
    #expect(reader.chrome.isHidden)
    reader.scroll(to: 10_000)
    #expect(!reader.chrome.isHidden)
  }

  /// A jump or a restored place: neither is the reader scrolling, in either
  /// direction.
  @Test func `a scroll the app makes neither hides nor shows`() {
    var reader = Reader.reading()
    reader.scroll(by: 500, byFinger: false)
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: 100)
    #expect(reader.chrome.isHidden)
    reader.scroll(by: -500, byFinger: false)
    #expect(reader.chrome.isHidden)
  }

  /// The bars going takes the top bar's height off the inset, and so off the
  /// distance from the top, while the text stays where it is: no scroll back.
  @Test func `the bars going is no scroll back`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    #expect(reader.chrome.isHidden)
    reader.chrome.scrolled(
      ReaderChrome.Scroll(
        position: reader.offset, distanceFromTop: reader.offset - 54,
        distanceToEnd: 10_000 - reader.offset, isUserDriven: true))
    #expect(reader.chrome.isHidden)
  }

  @Test func `a tap brings hidden bars back and puts shown ones away`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    reader.chrome.tapped()
    #expect(!reader.chrome.isHidden)
    reader.chrome.tapped()
    #expect(reader.chrome.isHidden)
  }

  @Test func `a tap at the top does not hide them`() {
    var reader = Reader()
    reader.scroll(to: 50)
    reader.chrome.tapped()
    #expect(!reader.chrome.isHidden)
  }

  @Test func `a tap before any scroll does not hide them`() {
    var chrome = ReaderChrome()
    chrome.isEnabled = true
    chrome.tapped()
    #expect(!chrome.isHidden)
  }

  @Test func `a jump shows them`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    reader.chrome.jumped()
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: ReaderChrome.hideDistance - 1)
    #expect(!reader.chrome.isHidden, "the run starts again after the jump")
  }

  @Test func `disabled, nothing hides and hidden bars come back`() {
    var reader = Reader.reading()
    reader.scroll(by: 100)
    #expect(reader.chrome.isHidden)
    reader.chrome.isEnabled = false
    #expect(!reader.chrome.isHidden)
    reader.scroll(by: 500)
    reader.chrome.tapped()
    #expect(!reader.chrome.isHidden)
  }
}
