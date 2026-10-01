import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A document laid out whole stays laid out once the layout manager is told to
/// keep every fragment (see ARCHITECTURE.md, "TextKit 2 traps").
///
/// `NSTextLayoutManager` keeps at most 2,000 layout fragments. Past that, moving
/// the viewport far throws away the layout on one side of it, and what was thrown
/// away is laid out again from estimates. RFC 9000 has 2,523 fragments and RFC 9110
/// 4,074, so in them a jump landed on an estimate and the content height kept
/// changing under the scroll indicator.
@Suite("Fragment cache")
@MainActor
struct FragmentCacheTests {
  /// A viewport of a phone's height whose top the test moves, as a scroll view's is.
  private final class Viewport: NSObject, NSTextViewportLayoutControllerDelegate {
    var top: CGFloat = 0

    func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController)
      -> CGRect
    {
      CGRect(x: 0, y: top, width: 350, height: 800)
    }

    func textViewportLayoutController(
      _ textViewportLayoutController: NSTextViewportLayoutController,
      configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {}
  }

  private struct Laid {
    /// Kept because the layout manager holds both weakly.
    let storage: NSTextContentStorage
    let viewport: Viewport
    let layout: NSTextLayoutManager
  }

  /// Three thousand paragraphs, laid out from the first to the last, as the reader
  /// lays out a document.
  private func laidOut(keepingEveryFragment: Bool) -> Laid {
    let paragraphs = (0..<3_000).map { index in
      "Paragraph \(index) " + String(repeating: "word ", count: index % 7 * 15 + 3)
    }
    let storage = NSTextContentStorage()
    storage.install(NSAttributedString(string: paragraphs.joined(separator: "\n")))
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 350, height: 10_000_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    let viewport = Viewport()
    layout.textViewportLayoutController.delegate = viewport
    if keepingEveryFragment {
      layout.keepEveryLaidOutFragment()
    }
    layout.ensureLayout(for: layout.documentRange)
    return Laid(storage: storage, viewport: viewport, layout: layout)
  }

  /// Moves the viewport to the end of the document and back, as a jump and a jump
  /// back do, and counts the fragments that are no longer laid out.
  private func fragmentsThrownAway(movingAbout laid: Laid) -> Int {
    let controller = laid.layout.textViewportLayoutController
    laid.viewport.top = laid.layout.usageBoundsForTextContainer.maxY - 800
    controller.layoutViewport()
    laid.viewport.top = 0
    controller.layoutViewport()
    var thrownAway = 0
    laid.layout.enumerateTextLayoutFragments(from: laid.layout.documentRange.location) {
      if $0.state != .layoutAvailable {
        thrownAway += 1
      }
      return true
    }
    return thrownAway
  }

  /// The trap itself, pinned so the day the framework stops doing this is noticed.
  @Test func `past two thousand fragments, moving the viewport throws layout away`() {
    let laid = laidOut(keepingEveryFragment: false)
    defer { withExtendedLifetime(laid) {} }

    #expect(fragmentsThrownAway(movingAbout: laid) > 0)
  }

  @Test func `a layout manager told to keep every fragment keeps them all`() {
    let laid = laidOut(keepingEveryFragment: true)
    defer { withExtendedLifetime(laid) {} }
    let height = laid.layout.usageBoundsForTextContainer.maxY

    #expect(fragmentsThrownAway(movingAbout: laid) == 0)
    #expect(laid.layout.usageBoundsForTextContainer.maxY == height)
  }
}
