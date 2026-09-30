import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The one recipe that puts the reader's line at the top of the viewport: after a
/// jump from anywhere, and through a change of column. The probe's two headline
/// results, as regression tests against real TextKit layout.
@Suite("Pin recipe")
@MainActor
struct PinRecipeTests {
  /// A scroll view reduced to what the recipe uses: a top, and a viewport that lays
  /// out what it covers, as the text view's viewport layout controller does.
  final class Surface: PinSurface {
    let layout: NSTextLayoutManager
    let height: CGFloat = 900
    var containerTop: CGFloat = 0

    init(layout: NSTextLayoutManager) { self.layout = layout }

    func scroll(toContainerY target: CGFloat) { containerTop = max(0, target) }

    func layOutViewport() {
      let top = containerTop
      guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
      layout.enumerateTextLayoutFragments(
        from: first.rangeInElement.location, options: [.ensuresLayout]
      ) {
        $0.layoutFragmentFrame.minY < top + self.height
      }
    }

    /// What is at the top, read from the fragments as the engine reads it.
    func anchor() -> (anchor: ReaderAnchor, line: NSRange)? {
      guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: containerTop)) else {
        return nil
      }
      return PinRecipe.anchor(
        atContainerTop: containerTop, in: layout, from: first.rangeInElement.location)
    }
  }

  @Test func `a jump lands its target at the top from wherever the last one left`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let sections = built.anchors.sections.entries
    // Far, near, backwards, forwards: every kind of move from every kind of state.
    let order =
      [sections.count - 1, 0, sections.count / 2, sections.count / 3, sections.count - 2, 1]
      + Array(stride(from: sections.count - 1, through: 0, by: -3))
    for index in order {
      let target = sections[index].offset
      PinRecipe.pin(ReaderAnchor(characterOffset: target), in: fixture.layout, on: surface)
      let landed = try #require(surface.anchor())
      #expect(landed.anchor.characterOffset == target, "jump to \(sections[index].anchor)")
      #expect(landed.anchor.fraction < 0.01)
    }
  }

  @Test func `a change of column keeps the line at the top`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let middle = built.anchors.sections.entries[built.anchors.sections.entries.count / 2]
    PinRecipe.pin(
      ReaderAnchor(characterOffset: middle.offset + 40, fraction: 0.3), in: fixture.layout,
      on: surface)
    let held = try #require(surface.anchor()).anchor
    let widths =
      Array(stride(from: 712, through: 120, by: -24))
      + Array(stride(from: 120, through: 712, by: 24))
    for width in widths {
      fixture.setWidth(CGFloat(width))
      PinRecipe.pin(held, in: fixture.layout, on: surface)
      let line = try #require(surface.anchor()).line
      #expect(NSLocationInRange(held.characterOffset, line), "at \(width) pt")
    }
  }

  @Test func `pinning an empty document does nothing`() {
    let fixture = LayoutFixture(text: NSAttributedString(), width: 712)
    let surface = Surface(layout: fixture.layout)
    #expect(PinRecipe.pin(ReaderAnchor(characterOffset: 0), in: fixture.layout, on: surface) == 0)
    #expect(surface.containerTop == 0)
  }

  @Test func `a pin never takes more than its passes`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let last = try #require(built.anchors.sections.entries.last)
    let passes = PinRecipe.pin(
      ReaderAnchor(characterOffset: last.offset), in: fixture.layout, on: surface)
    #expect(passes <= PinRecipe.maximumPasses)
  }
}
