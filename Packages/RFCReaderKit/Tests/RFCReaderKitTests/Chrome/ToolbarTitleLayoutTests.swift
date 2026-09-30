import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Toolbar title layout")
struct ToolbarTitleLayoutTests {
  /// A short title takes the width of its text and no more — the point of drawing
  /// the title ourselves rather than letting AppKit's own block expand to fill.
  @Test func `a short title takes only the width of its text`() {
    #expect(ToolbarTitleLayout.width(forText: 120, inColumn: 400) == 136)
  }

  /// Capped to the column it names: a long RFC title ran past the list's trailing
  /// edge and over the reader's own toolbar section.
  @Test func `a long title stops short of the divider`() {
    let width = ToolbarTitleLayout.width(forText: 2000, inColumn: 300)
    #expect(width < 300)
    #expect(width == 276)
  }

  /// A column dragged to nothing still leaves the title a readable stub rather
  /// than a zero-width item the toolbar lays other items over.
  @Test func `a collapsed column still leaves a stub`() {
    #expect(ToolbarTitleLayout.width(forText: 2000, inColumn: 0) == 80)
  }

  /// The reader's title flexes down to nothing; below the stub width it hides
  /// rather than drawing an ellipsis on its own.
  @Test func `a title narrower than the stub is not drawn`() {
    #expect(ToolbarTitleLayout.isWorthDrawing(width: 80))
    #expect(!ToolbarTitleLayout.isWorthDrawing(width: 79))
    #expect(!ToolbarTitleLayout.isWorthDrawing(width: 0))
  }
}
