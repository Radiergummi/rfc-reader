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
}
