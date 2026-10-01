import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The line at the top of the viewport is read from the fragments the viewport
/// was last laid out with, not from TextKit's hit test.
///
/// `UITextView` keeps the layout only around its viewport. What it threw away is
/// laid out again from estimates, and a fragment laid out for an earlier viewport
/// keeps the frame it had then. Measured on Mac Catalyst's `UITextView` over 3,000 paragraphs,
/// jumping and scrolling about: `textLayoutFragment(for:)` at the viewport's top
/// answered with another fragment than the one on screen 9 times in 98, once 378
/// paragraphs away, because more than one fragment's frame held the point. The
/// viewport's own fragments are the ones on screen.
@Suite("Reading place: the viewport's fragments")
@MainActor
struct ReadingPlaceViewportTests {
  /// Answers every hit test with the document's first fragment, as a fragment left
  /// from an earlier viewport does where its stale frame holds the point.
  private final class StaleHitTestLayoutManager: NSTextLayoutManager {
    override func textLayoutFragment(for position: CGPoint) -> NSTextLayoutFragment? {
      textLayoutFragment(for: documentRange.location)
    }
  }

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
    /// Where the section the viewport was relocated to starts.
    let sectionStart: Int
  }

  /// RFC 8999 at a phone's measure, with the viewport relocated to a section
  /// below the long header's packet diagram, as a jump puts it there.
  private func laidOutAtShortHeader() throws -> Laid {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle(measure: 350))
    let section = try #require(
      built.anchors.sections.entries.first { $0.heading?.contains("Short Header") == true })
    let storage = NSTextContentStorage()
    storage.install(built.text)
    let layout = StaleHitTestLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 350, height: 1_000_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    let viewport = Viewport()
    layout.textViewportLayoutController.delegate = viewport
    let location = try #require(layout.location(atOffset: section.offset))
    viewport.top = layout.textViewportLayoutController.relocateViewport(to: location)
    layout.textViewportLayoutController.layoutViewport()
    return Laid(storage: storage, viewport: viewport, layout: layout, sectionStart: section.offset)
  }

  @Test func `the line at the top is the viewport's, not the hit test's`() throws {
    let laid = try laidOutAtShortHeader()
    defer { withExtendedLifetime(laid) {} }

    let place = try #require(laid.layout.readingPlace(atViewportTop: laid.viewport.top))
    #expect(place.fragmentStart == laid.sectionStart)
    #expect(place.line.location == laid.sectionStart)
  }

  /// A top inside the fragment after the heading's is found by walking on through
  /// the viewport's fragments.
  @Test func `a top further down the viewport is read there too`() throws {
    let laid = try laidOutAtShortHeader()
    defer { withExtendedLifetime(laid) {} }

    let headingStart = try #require(laid.layout.location(atOffset: laid.sectionStart))
    let heading = try #require(laid.layout.textLayoutFragment(for: headingStart))
    let next = try #require(
      laid.layout.textLayoutFragment(for: heading.rangeInElement.endLocation))
    let top = next.layoutFragmentFrame.minY + 1

    let place = try #require(laid.layout.readingPlace(atViewportTop: top))
    #expect(place.fragmentStart == laid.layout.offset(of: next.rangeInElement.location))
  }
}
