import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Toolbar title reveal")
struct ToolbarTitleRevealTests {
  /// A 40 pt last line whose bottom sits at y = 200.
  private func progress(atToolbarEdge edge: CGFloat) -> CGFloat {
    ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: edge, distance: 40)
  }

  /// At the top of the document the header shows the title, so the toolbar does not.
  @Test func `hidden while the heading is below the toolbar`() {
    #expect(progress(atToolbarEdge: 0) == 0)
    #expect(progress(atToolbarEdge: 160) == 0, "the last line's top has only just reached the edge")
  }

  /// It scrubs with the scroll: half the line under the toolbar is half the way in.
  @Test func `follows the scroll across the last line`() {
    #expect(progress(atToolbarEdge: 170) == 0.25)
    #expect(progress(atToolbarEdge: 180) == 0.5)
  }

  /// Fully in once the line is fully under, and it stays there all the way down.
  @Test func `fully shown once the heading has passed`() {
    #expect(progress(atToolbarEdge: 200) == 1)
    #expect(progress(atToolbarEdge: 90_000) == 1)
  }

  /// A heading of several lines reveals over its last line only: the toolbar has
  /// room for one, and the lines above it are gone by then anyway.
  @Test func `a tall heading reveals over its last line only`() {
    let wrapped = ToolbarTitleReveal.progress(headingBottom: 300, visibleTop: 280, distance: 40)
    #expect(wrapped == 0.5)
  }

  /// Invisible while it crosses the toolbar's edge, then fading in to fully opaque.
  @Test func `opacity waits for the first half of the travel`() {
    #expect(ToolbarTitleReveal.opacity(atProgress: 0) == 0)
    #expect(ToolbarTitleReveal.opacity(atProgress: 0.5) == 0)
    #expect(ToolbarTitleReveal.opacity(atProgress: 0.75) == 0.5)
    #expect(ToolbarTitleReveal.opacity(atProgress: 1) == 1)
  }

  /// A heading with no measurable line switches at its bottom rather than dividing
  /// by zero.
  @Test func `a zero distance switches at the headings bottom`() {
    #expect(ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: 199, distance: 0) == 0)
    #expect(ToolbarTitleReveal.progress(headingBottom: 200, visibleTop: 200, distance: 0) == 1)
  }
}
