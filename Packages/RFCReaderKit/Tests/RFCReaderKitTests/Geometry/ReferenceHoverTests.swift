import CoreGraphics
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The macOS reader's hover, force-click and preview rules
/// (`docs/decisions/2026-09-26-a-reference-previews-on-hover-and-force-click-on-macos-and-on-long-press-on-ios.md`).
@Suite("Reference hover")
struct ReferenceHoverTests {
  private let first = HoverTarget(
    box: ReferenceBox(CrossReference(target: .anchor("RFC2119"))),
    range: NSRange(location: 10, length: 9))
  private let second = HoverTarget(
    box: ReferenceBox(CrossReference(target: .anchor("RFC8174"))),
    range: NSRange(location: 40, length: 9))
  private let here = CGPoint(x: 100, y: 100)
  private let elsewhere = CGPoint(x: 300, y: 100)

  /// A card for `target` on screen, after its dwell.
  private func showingCard(_ target: HoverTarget) -> ReferenceHover {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: target))
    _ = hover.handle(.cardDwellElapsed(buttonPressed: false))
    _ = hover.handle(.cardShown)
    return hover
  }

  // MARK: - Hover

  @Test func `a reference under the pointer shows its card once the dwell ends`() {
    var hover = ReferenceHover()
    #expect(
      hover.handle(.pointerMoved(location: here, target: first)) == [.startDwell(.card(first))])
    #expect(hover.handle(.cardDwellElapsed(buttonPressed: false)) == [.showCard(first)])
  }

  @Test func `moving within the same reference does not restart its dwell`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: first)).isEmpty)
  }

  @Test func `moving to another reference closes the card and times the new one`() {
    var hover = showingCard(first)
    #expect(
      hover.handle(.pointerMoved(location: elsewhere, target: second)) == [
        .closePopover, .startDwell(.card(second)),
      ])
  }

  @Test func `leaving the reference closes its card`() {
    var hover = showingCard(first)
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: nil)) == [.closePopover])
    hover = showingCard(first)
    #expect(hover.handle(.pointerExited) == [.closePopover])
  }

  @Test func `a dwell that ends with a button held is a click or a drag, and shows nothing`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    #expect(hover.handle(.cardDwellElapsed(buttonPressed: true)).isEmpty)
  }

  @Test func `a mouse-down cancels a dwell in progress`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    #expect(hover.handle(.mouseDown(withControl: false)) == [.cancelDwell])
    #expect(hover.handle(.cardDwellElapsed(buttonPressed: false)).isEmpty)
  }

  @Test func `a context menu cancels a dwell and closes a card`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    #expect(hover.handle(.contextMenu) == [.cancelDwell])
    hover = showingCard(first)
    #expect(hover.handle(.contextMenu) == [.closePopover])
  }

  @Test func `a card that closed itself can show again without the pointer leaving`() {
    var hover = showingCard(first)
    #expect(hover.handle(.popoverClosedItself).isEmpty)
    #expect(
      hover.handle(.pointerMoved(location: elsewhere, target: first)) == [.startDwell(.card(first))]
    )
  }

  @Test func `a new document ends whatever is timing or showing`() {
    var hover = showingCard(first)
    #expect(hover.handle(.reset) == [.closePopover])
    #expect(hover.hovered == nil)
  }

  // MARK: - Scrolling

  @Test func `scrolling closes the card and previews what rests under the pointer once it stops`() {
    var hover = showingCard(first)
    #expect(hover.handle(.scrolled) == [.closePopover, .startDwell(.restingPointer)])
    // Every further tick restarts the one dwell, rather than hit-testing per tick.
    #expect(hover.handle(.scrolled) == [.cancelDwell, .startDwell(.restingPointer)])
    #expect(hover.handle(.restingDwellElapsed(target: second)) == [.showCard(second)])
    #expect(hover.hovered === second.box)
  }

  @Test func `a scroll that comes to rest over no reference shows nothing`() {
    var hover = ReferenceHover()
    _ = hover.handle(.scrolled)
    #expect(hover.handle(.restingDwellElapsed(target: nil)).isEmpty)
  }

  // MARK: - VoiceOver (#514)

  /// VoiceOver moves the pointer onto whatever it reads, and scrolls the text to
  /// it: neither is a reader resting the mouse on a reference.
  @Test func `with hover previews off, the pointer arriving on a reference times nothing`() {
    var hover = ReferenceHover()
    hover.previewsOnHover = false
    #expect(hover.handle(.pointerMoved(location: here, target: first)).isEmpty)
    #expect(hover.handle(.cardDwellElapsed(buttonPressed: false)).isEmpty)
  }

  @Test func `with hover previews off, a scroll previews nothing under the pointer`() {
    var hover = ReferenceHover()
    hover.previewsOnHover = false
    #expect(hover.handle(.scrolled).isEmpty)
    #expect(hover.handle(.restingDwellElapsed(target: first)).isEmpty)
  }

  @Test func `hover previews turned off during a dwell show nothing when it ends`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    hover.previewsOnHover = false
    #expect(hover.handle(.cardDwellElapsed(buttonPressed: false)).isEmpty)
    hover = ReferenceHover()
    _ = hover.handle(.scrolled)
    hover.previewsOnHover = false
    #expect(hover.handle(.restingDwellElapsed(target: first)).isEmpty)
  }

  @Test func `with hover previews off, a move looks at nothing unless a preview is up`() {
    var hover = ReferenceHover()
    hover.previewsOnHover = false
    #expect(!hover.wantsTarget(at: here))
    _ = hover.handle(.forceClickCard(first))
    _ = hover.handle(.cardShown)
    #expect(hover.wantsTarget(at: here))
  }

  @Test func `with hover previews off, a force click still previews, and moving keeps it`() {
    var hover = ReferenceHover()
    hover.previewsOnHover = false
    #expect(hover.handle(.forceClickCard(first)) == [.showCard(first)])
    _ = hover.handle(.cardShown)
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: first)).isEmpty)
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: nil)) == [.closePopover])
  }

  @Test func `with hover previews off, another reference closes a card and times nothing`() {
    var hover = ReferenceHover()
    hover.previewsOnHover = false
    _ = hover.handle(.forceClickCard(first))
    _ = hover.handle(.cardShown)
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: second)) == [.closePopover])
    #expect(hover.dwell == nil)
  }

  // MARK: - Following a link

  @Test func `following a link cancels a dwell, and follows`() {
    var hover = ReferenceHover()
    _ = hover.handle(.pointerMoved(location: here, target: first))
    #expect(
      hover.handle(.clickedLink(reference: first.box, pointer: here)) == [
        .cancelDwell, .followLink,
      ])
  }

  @Test
  func `nothing previews after following a link until the pointer moves from where it clicked`() {
    var hover = ReferenceHover()
    _ = hover.handle(.clickedLink(reference: first.box, pointer: here))
    // The jump the click caused is not the reader resting on what it landed on.
    #expect(hover.handle(.scrolled).isEmpty)
    // A move event is not proof the pointer moved.
    #expect(hover.handle(.pointerMoved(location: here, target: second)).isEmpty)
    #expect(
      hover.handle(.pointerMoved(location: elsewhere, target: second)) == [
        .startDwell(.card(second))
      ])
    #expect(hover.linkClickPointer == nil)
  }

  @Test func `a move whose target the rules would drop asks for no hit test`() {
    var afterLink = ReferenceHover()
    _ = afterLink.handle(.clickedLink(reference: first.box, pointer: here))
    #expect(!afterLink.wantsTarget(at: here))
    #expect(afterLink.wantsTarget(at: elsewhere))

    var previewing = ReferenceHover()
    _ = previewing.handle(.forceClickDocument(first))
    _ = previewing.handle(.documentPreviewShown)
    #expect(!previewing.wantsTarget(at: elsewhere))

    #expect(!ReferenceHover(isPreviewReader: true).wantsTarget(at: here))
    #expect(ReferenceHover().wantsTarget(at: here))
  }

  // MARK: - Force click

  @Test func `a force click shows the card, and its own click does not follow the link`() {
    var hover = ReferenceHover()
    #expect(hover.handle(.forceClickCard(first)) == [.showCard(first)])
    _ = hover.handle(.cardShown)
    #expect(hover.handle(.clickedLink(reference: first.box, pointer: here)) == [.swallowClick])
    // Swallowed once: the next click on it follows.
    #expect(
      hover.handle(.clickedLink(reference: first.box, pointer: here)) == [
        .closePopover, .followLink,
      ])
  }

  @Test func `a force click on a card showing adds nothing, and swallows its click`() {
    var hover = showingCard(first)
    #expect(hover.handle(.forceClickCard(first)).isEmpty)
    #expect(hover.handle(.clickedLink(reference: first.box, pointer: here)) == [.swallowClick])
  }

  @Test func `a mouse-down after a force click is a click of its own, and follows`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickCard(first))
    _ = hover.handle(.cardShown)
    _ = hover.handle(.mouseDown(withControl: false))
    #expect(hover.handle(.clickedLink(reference: first.box, pointer: here)) == [.followLink])
  }

  @Test func `a click on another reference after a force click follows it`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickCard(first))
    #expect(hover.handle(.clickedLink(reference: second.box, pointer: here)).contains(.followLink))
  }

  @Test func `a force click on a document replaces a hover card with the document preview`() {
    var hover = showingCard(first)
    #expect(
      hover.handle(.forceClickDocument(first)) == [.closePopover, .showDocumentPreview(first)])
    #expect(hover.presentation == nil)
    _ = hover.handle(.documentPreviewShown)
    #expect(hover.presentation == .documentPreview)
  }

  @Test func `the second report of one force click does not open the preview again`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickDocument(first))
    _ = hover.handle(.documentPreviewShown)
    #expect(hover.handle(.forceClickDocument(first)).isEmpty)
  }

  @Test func `a document preview that never appeared suppresses nothing`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickDocument(first))
    #expect(
      hover.handle(.pointerMoved(location: elsewhere, target: second)) == [
        .startDwell(.card(second))
      ])
  }

  @Test func `the pointer traveling into a document preview does not close it`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickDocument(first))
    _ = hover.handle(.documentPreviewShown)
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: nil)).isEmpty)
    #expect(hover.handle(.pointerExited).isEmpty)
    #expect(hover.presentation == .documentPreview)
  }

  @Test func `committing a document preview closes it, and previews nothing the jump lands on`() {
    var hover = ReferenceHover()
    _ = hover.handle(.forceClickDocument(first))
    _ = hover.handle(.documentPreviewShown)
    #expect(hover.handle(.previewCommitted(pointer: here)) == [.closePopover])
    #expect(hover.handle(.scrolled).isEmpty)
  }

  // MARK: - A heading's backlinks

  /// A backlink caption's list on screen, opened by a click on the caption, which is
  /// not a reference.
  private func showingBacklinks() -> ReferenceHover {
    var hover = ReferenceHover()
    _ = hover.handle(.clickedLink(reference: nil, pointer: here))
    _ = hover.handle(.backlinksShown)
    return hover
  }

  @Test func `the pointer traveling into a heading's backlinks does not close them`() {
    var hover = showingBacklinks()
    #expect(!hover.wantsTarget(at: elsewhere))
    #expect(hover.handle(.pointerMoved(location: elsewhere, target: first)).isEmpty)
    #expect(hover.handle(.pointerExited).isEmpty)
    #expect(hover.presentation == .backlinks)
  }

  @Test func `choosing a backlink closes the list, and previews nothing the jump lands on`() {
    var hover = showingBacklinks()
    #expect(hover.handle(.previewCommitted(pointer: elsewhere)) == [.closePopover])
    #expect(hover.handle(.scrolled).isEmpty)
  }

  // MARK: - A preview's own reader

  @Test func `a preview's reader previews nothing itself`() {
    var hover = ReferenceHover(isPreviewReader: true)
    #expect(hover.handle(.pointerMoved(location: here, target: first)).isEmpty)
    #expect(hover.handle(.forceClickCard(first)).isEmpty)
    #expect(hover.handle(.forceClickDocument(first)).isEmpty)
    _ = hover.handle(.scrolled)
    #expect(hover.handle(.restingDwellElapsed(target: first)).isEmpty)
  }

  @Test func `a click in a preview's reader commits it, and a control-click is its context menu`() {
    var hover = ReferenceHover(isPreviewReader: true)
    #expect(hover.handle(.mouseDown(withControl: false)) == [.commitPreview])
    #expect(hover.handle(.mouseDown(withControl: true)).isEmpty)
  }
}
