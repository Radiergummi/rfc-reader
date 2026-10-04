import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's place within one paragraph: which line's first character is at the
/// top of the viewport, and how far down that line the top is.
@Suite("Line pin")
@MainActor
struct LinePinTests {
  /// One long paragraph that wraps many times at any of the widths below, and a
  /// short one after it. Hand-written: nothing here is parsed.
  private let text = NSAttributedString(
    string: String(repeating: "a word that wraps ", count: 120) + "\nA short one.\n",
    attributes: [.font: PlatformFont.systemFont(ofSize: 17)])

  @Test func `a point on a line anchors that line's first character`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let third = fragment.textLineFragments[2]
    let (anchor, line) = LinePin.anchor(
      atFragmentY: third.typographicBounds.midY,
      in: try #require(FragmentLines(fragment, in: fixture.layout)))
    #expect(anchor.characterOffset == third.characterRange.location)
    #expect(abs(anchor.fraction - 0.5) < 0.01)
    #expect(line == third.characterRange)
  }

  @Test func `the spacing above a paragraph belongs to its first line`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: 0, in: try #require(FragmentLines(fragment, in: fixture.layout)))
    #expect(anchor == ReaderAnchor(characterOffset: 0, fraction: 0))
  }

  @Test func `an anchor round-trips through its y`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let paragraph = try #require(FragmentLines(fragment, in: fixture.layout))
    for tenth in 0..<Int(fragment.layoutFragmentFrame.height / 10) {
      let height = CGFloat(tenth) * 10
      let (anchor, _) = LinePin.anchor(atFragmentY: height, in: paragraph)
      let back = LinePin.fragmentY(of: anchor, in: paragraph)
      #expect(abs(back - min(height, paragraph.lines.last!.typographicBounds.maxY)) < 0.5)
    }
  }

  /// A paragraph that is not the document's first: its lines count from its own
  /// start, and the anchor and the line it names are document-relative. The only
  /// shape where dropping the start, or adding a line's, goes wrong.
  @Test func `a later paragraph's anchor counts from the document's start`() throws {
    let later = NSAttributedString(
      string: "A short one.\n" + String(repeating: "a word that wraps ", count: 120) + "\n",
      attributes: [.font: PlatformFont.systemFont(ofSize: 17)])
    let fixture = LayoutFixture(text: later, width: 400)
    let start = ("A short one.\n" as NSString).length
    let fragment = try #require(fixture.fragment(at: start))
    let paragraph = try #require(FragmentLines(fragment, in: fixture.layout))
    #expect(paragraph.start == start)
    let third = fragment.textLineFragments[2]
    let (anchor, line) = LinePin.anchor(atFragmentY: third.typographicBounds.midY, in: paragraph)
    #expect(anchor.characterOffset == start + third.characterRange.location)
    #expect(line == NSRange(location: anchor.characterOffset, length: third.characterRange.length))
    let back = LinePin.fragmentY(of: anchor, in: paragraph)
    #expect(abs(back - third.typographicBounds.midY) < 0.5)
  }

  /// After a re-wrap the anchor's character is on another line: the y it gives is
  /// that line's, so the character stays at the top.
  @Test(arguments: [300.0, 180.0, 120.0])
  func `after a re-wrap the anchor's character is on the line at its y`(width: CGFloat) throws {
    let fixture = LayoutFixture(text: text, width: 400)
    var fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: fragment.textLineFragments[5].typographicBounds.minY + 3,
      in: try #require(FragmentLines(fragment, in: fixture.layout)))
    fixture.setWidth(width)
    fragment = try #require(fixture.fragment(at: 0))
    let rewrapped = try #require(FragmentLines(fragment, in: fixture.layout))
    let height = LinePin.fragmentY(of: anchor, in: rewrapped)
    let (_, line) = LinePin.anchor(atFragmentY: height, in: rewrapped)
    #expect(NSLocationInRange(anchor.characterOffset, line))
  }
}
