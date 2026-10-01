import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Original text layout")
struct OriginalTextLayoutTests {
  /// An iPhone's width against 72 columns at 13 pt: the lines run past the view,
  /// and the content has to reach their end and the inset after it.
  @Test func `lines wider than the view widen the content to their end and both insets`() {
    #expect(
      OriginalTextLayout.contentWidth(usedWidth: 578, horizontalInsets: 48, viewWidth: 390) == 626)
  }

  /// An iPad's width: nothing to scroll to sideways, so the content is the view.
  @Test func `lines that fit keep the content as wide as the view`() {
    #expect(
      OriginalTextLayout.contentWidth(usedWidth: 578, horizontalInsets: 48, viewWidth: 1024)
        == 1024)
  }

  /// Nothing laid out yet, as before the first layout pass.
  @Test func `no laid-out text keeps the content as wide as the view`() {
    #expect(
      OriginalTextLayout.contentWidth(usedWidth: 0, horizontalInsets: 48, viewWidth: 390) == 390)
  }

  /// A monospaced advance is fractional, and rounding down would clip the last glyph.
  @Test func `a fractional width rounds up to a whole point`() {
    #expect(
      OriginalTextLayout.contentWidth(usedWidth: 534.09375, horizontalInsets: 48, viewWidth: 390)
        == 583)
  }

  /// An iPad split view can be a fractional width: text that fits it must not
  /// scroll sideways by the half point that rounding up would add.
  @Test func `text that fits a fractional-width view keeps the view's width`() {
    #expect(
      OriginalTextLayout.contentWidth(usedWidth: 459.2, horizontalInsets: 48, viewWidth: 507.5)
        == 507.5)
  }

  /// UIKit clamps a touch into the text container before it finds the character
  /// under it, so a container with no height put every touch on the first line
  /// (#240).
  @Test func `the container is unbounded down`() {
    #expect(OriginalTextLayout.containerSize.height == .greatestFiniteMagnitude)
  }

  /// A `UITextView` takes a container 10,000,000 points wide or more as having no
  /// width and cuts its selection at the view's width instead, so past the right
  /// edge of an iPhone a selection had no highlight and its end handle stayed
  /// behind (#240).
  @Test func `the container is narrower than what UIKit takes as no width`() {
    #expect(OriginalTextLayout.containerSize.width < 10_000_000)
  }

  /// A thousand columns at a 24 pt advance, far past any published line at the
  /// largest text size: lines still never wrap.
  @Test func `the container is wider than any line`() {
    #expect(OriginalTextLayout.containerSize.width > 1_000 * 24)
  }

  /// A larger text size widens the content by its ratio, and the place in the
  /// line that was at the view's left edge stays there.
  @Test func `a sideways offset scales with the content width`() {
    #expect(
      OriginalTextLayout.horizontalOffset(
        150, scaledFrom: 600, to: 720, viewWidth: 390) == 180)
  }

  /// Scrolled to the end of the lines, then made smaller: the offset cannot run
  /// past the new end.
  @Test func `a scaled offset stops at the end of the content`() {
    #expect(
      OriginalTextLayout.horizontalOffset(
        236, scaledFrom: 626, to: 500, viewWidth: 390) == 110)
  }

  /// Text that now fits the view has nothing to scroll to sideways.
  @Test func `a scaled offset is zero when the content fits the view`() {
    #expect(
      OriginalTextLayout.horizontalOffset(
        200, scaledFrom: 626, to: 390, viewWidth: 390) == 0)
  }

  /// Nothing was laid out before, so there is no position to keep.
  @Test func `an offset into no content stays at the start`() {
    #expect(
      OriginalTextLayout.horizontalOffset(
        0, scaledFrom: 0, to: 626, viewWidth: 390) == 0)
  }
}
