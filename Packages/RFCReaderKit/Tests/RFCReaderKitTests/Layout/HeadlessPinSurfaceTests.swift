import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The viewport layout every `PinSurface` goes through, and the live-resize gate in
/// it: during a live resize the viewport is left to AppKit's display pass
/// (docs/ARCHITECTURE.md, "TextKit 2 traps").
@Suite("Headless pin surface")
@MainActor
struct HeadlessPinSurfaceTests {
  @Test func `a live resize lays out nothing of the viewport`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = HeadlessPinSurface(layout: fixture.layout)
    surface.isInLiveResize = true
    surface.layOutViewport()
    #expect(try firstFragment(in: fixture).state != .layoutAvailable)
  }

  @Test func `outside a live resize the viewport is laid out`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = HeadlessPinSurface(layout: fixture.layout)
    surface.isInLiveResize = true
    surface.layOutViewport()
    surface.isInLiveResize = false
    surface.layOutViewport()
    #expect(try firstFragment(in: fixture).state == .layoutAvailable)
  }

  @Test func `a scroll never goes above the container`() {
    let fixture = LayoutFixture(text: NSAttributedString(), width: 712)
    let surface = HeadlessPinSurface(layout: fixture.layout)
    surface.scroll(toContainerY: -40)
    #expect(surface.containerTop == 0)
  }

  /// The fragment at the top of the document, as it is, laid out or not.
  private func firstFragment(in fixture: LayoutFixture) throws -> NSTextLayoutFragment {
    let start = fixture.layout.documentRange.location
    return try #require(fixture.layout.textLayoutFragment(for: start))
  }
}
