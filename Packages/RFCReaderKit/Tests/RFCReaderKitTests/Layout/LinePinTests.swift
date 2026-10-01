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
      atFragmentY: third.typographicBounds.midY, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(anchor.characterOffset == third.characterRange.location)
    #expect(abs(anchor.fraction - 0.5) < 0.01)
    #expect(line == third.characterRange)
  }

  @Test func `the spacing above a paragraph belongs to its first line`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: 0, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(anchor == ReaderAnchor(characterOffset: 0, fraction: 0))
  }

  @Test func `an anchor round-trips through its y`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let lines = fragment.textLineFragments
    for tenth in 0..<Int(fragment.layoutFragmentFrame.height / 10) {
      let height = CGFloat(tenth) * 10
      let (anchor, _) = LinePin.anchor(atFragmentY: height, in: lines, fragmentStart: 0)
      let back = LinePin.fragmentY(of: anchor, in: lines, fragmentStart: 0)
      #expect(abs(back - min(height, lines.last!.typographicBounds.maxY)) < 0.5)
    }
  }

  /// After a re-wrap the anchor's character is on another line: the y it gives is
  /// that line's, so the character stays at the top.
  @Test(arguments: [300.0, 180.0, 120.0])
  func `after a re-wrap the anchor's character is on the line at its y`(width: CGFloat) throws {
    let fixture = LayoutFixture(text: text, width: 400)
    var fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: fragment.textLineFragments[5].typographicBounds.minY + 3,
      in: fragment.textLineFragments, fragmentStart: 0)
    fixture.setWidth(width)
    fragment = try #require(fixture.fragment(at: 0))
    let height = LinePin.fragmentY(of: anchor, in: fragment.textLineFragments, fragmentStart: 0)
    let (_, line) = LinePin.anchor(
      atFragmentY: height, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(NSLocationInRange(anchor.characterOffset, line))
  }
}
