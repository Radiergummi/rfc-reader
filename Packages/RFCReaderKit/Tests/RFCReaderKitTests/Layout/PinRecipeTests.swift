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

  /// A scroll view whose viewport moves as UIKit's does (#625): it remembers the
  /// fragment it put at the top and the y it put it at, and a scroll walks from there
  /// by the distance scrolled, through the fragments' heights. When a layout from the
  /// start has since moved that fragment, the walk still starts from the remembered y,
  /// so it lands as far off as the fragment moved. At the document's start the walk
  /// starts from the start. Until it is first laid out it has no viewport, and puts
  /// one where TextKit's estimates say, as after TextKit drops its layout.
  final class AnchoredSurface: PinSurface {
    let layout: NSTextLayoutManager
    var containerTop: CGFloat = 0
    private var remembered: (offset: Int, y: CGFloat)?

    init(layout: NSTextLayoutManager) { self.layout = layout }

    func scroll(toContainerY target: CGFloat) {
      containerTop = max(0, target)
      guard containerTop > 0 else {
        remembered = (0, 0)
        return
      }
      guard let remembered, var fragment = fragment(at: remembered.offset) else { return }
      var y = remembered.y
      while containerTop < y, let previous = self.fragment(at: start(of: fragment) - 1) {
        y -= previous.layoutFragmentFrame.height
        fragment = previous
      }
      while y + fragment.layoutFragmentFrame.height <= containerTop,
        let next = self.fragment(at: end(of: fragment))
      {
        y += fragment.layoutFragmentFrame.height
        fragment = next
      }
      self.remembered = (start(of: fragment), y)
    }

    func layOutViewport() {
      guard remembered == nil,
        let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: containerTop))
      else { return }
      remembered = (start(of: first), first.layoutFragmentFrame.minY)
    }

    /// What the viewport shows at its top.
    func shown() -> ReaderAnchor? {
      guard let remembered, let fragment = fragment(at: remembered.offset) else { return nil }
      return LinePin.anchor(
        atFragmentY: containerTop - remembered.y, in: fragment.textLineFragments,
        fragmentStart: remembered.offset
      ).anchor
    }

    /// The fragment holding `offset`, laid out, or nil outside the text.
    private func fragment(at offset: Int) -> NSTextLayoutFragment? {
      guard offset >= 0, let location = layout.location(atOffset: offset),
        location.compare(layout.documentRange.endLocation) == .orderedAscending,
        let fragment = layout.textLayoutFragment(for: location)
      else { return nil }
      layout.ensureLayout(for: fragment.rangeInElement)
      return layout.textLayoutFragment(for: location)
    }

    private func start(of fragment: NSTextLayoutFragment) -> Int {
      layout.offset(of: fragment.rangeInElement.location)
    }

    private func end(of fragment: NSTextLayoutFragment) -> Int {
      layout.offset(of: fragment.rangeInElement.endLocation)
    }
  }

  /// On an iPhone, a settle laid out from the start, which moved the fragments the
  /// viewport was showing, and the scroll to the target then walked from where the
  /// viewport remembered them: RFC 9000 showed §20.1 for §14.3.2, 80,000 characters on.
  @Test func `a settle lands its target where the viewport walks to`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = AnchoredSurface(layout: fixture.layout)
    let sections = built.anchors.sections.entries
    // The viewport on estimates, in the middle of the document.
    PinRecipe.pin(
      ReaderAnchor(characterOffset: sections[sections.count / 2].offset), in: fixture.layout,
      on: surface)
    for index in [sections.count * 3 / 4, sections.count / 3, sections.count - 1, 1] {
      let target = sections[index].offset
      PinRecipe.settle(ReaderAnchor(characterOffset: target), in: fixture.layout, on: surface)
      #expect(surface.shown()?.characterOffset == target, "jump to \(sections[index].anchor)")
    }
  }

  /// TextKit lays out no fragment at the end of the text, where ⌘↓ puts the
  /// insertion point: a settle there lands on the last character's line rather than
  /// placing nothing and leaving the viewport where it was (#726).
  @Test func `a settle at the end of the text lands on its last line`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let length = built.text.length
    PinRecipe.settle(ReaderAnchor(characterOffset: length), in: fixture.layout, on: surface)
    let landed = try #require(surface.anchor())
    // The last line, or the empty one TextKit lays out after a final line break.
    #expect(landed.anchor.characterOffset >= length - 1)
    #expect(surface.containerTop > 0)
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

  /// The header hangs in the text view's top inset, above the container. When it
  /// changes height — a cold launch's revisions banner arriving after the reading
  /// position was restored, 208 to 289 pt on RFC 8060 (#492) — the offset stays and
  /// the container moves under it, so the viewport's top in container coordinates
  /// moves the other way. No scroll of the reader's happened, so the keeper still
  /// names the line, and the engine's pin puts it back at the top.
  @Test func `a header inset change keeps the line at the top`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    var keeper = AnchorKeeper()
    let sections = built.anchors.sections.entries
    keeper.jumped(to: ReaderAnchor(characterOffset: sections[sections.count / 2].offset))
    for change: CGFloat in [81, -81, 160, -20] {
      guard case .line(let anchor) = keeper.place else {
        Issue.record("the place left its line")
        return
      }
      keeper.beginEngineMove()
      PinRecipe.settle(anchor, in: fixture.layout, on: surface)
      keeper.endEngineMove(top: surface.containerTop)
      let before = try #require(surface.anchor()).line
      surface.containerTop -= change
      keeper.beginEngineMove()
      PinRecipe.pin(anchor, in: fixture.layout, on: surface)
      keeper.endEngineMove(top: surface.containerTop)
      let after = try #require(surface.anchor())
      #expect(after.line == before, "header changed by \(change) pt")
      #expect(NSLocationInRange(anchor.characterOffset, after.line))
      // What the platform reports of the pin afterwards is the engine's, not the reader's.
      keeper.userScrolled(to: after.anchor, line: after.line, top: surface.containerTop)
      #expect(keeper.place == .line(anchor))
    }
  }

  /// After TextKit drops its layout, the viewport range can start far past the top
  /// for one pass; the first fragment from there is not what is at the top, and
  /// taking it moved the reader's place 150,000 characters on RFC 5661.
  @Test func `a lookup that starts past the top finds nothing`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let sections = built.anchors.sections.entries
    PinRecipe.pin(
      ReaderAnchor(characterOffset: sections[1].offset), in: fixture.layout, on: surface)
    let later = try #require(fixture.layout.location(atOffset: sections[sections.count / 2].offset))
    let stale = try #require(fixture.layout.textLayoutFragment(for: later))
    fixture.layout.ensureLayout(for: stale.rangeInElement)
    #expect(
      PinRecipe.anchor(
        atContainerTop: surface.containerTop, in: fixture.layout,
        from: stale.rangeInElement.location) == nil)
  }

  /// A settled line is where the layout of the whole document puts it, so laying out
  /// the rest never moves it. A pin alone leaves it where TextKit estimated it: on an
  /// iPhone, completion then moved the text under the reader 73,000 characters.
  @Test func `a settled line is where the whole document's layout puts it`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let target = try #require(built.anchors.sections.entries.last).offset
    PinRecipe.settle(ReaderAnchor(characterOffset: target), in: fixture.layout, on: surface)
    let settled = surface.containerTop
    fixture.layout.ensureLayout(for: fixture.layout.documentRange)
    let location = try #require(fixture.layout.location(atOffset: target))
    let fragment = try #require(fixture.layout.textLayoutFragment(for: location))
    #expect(abs(fragment.layoutFragmentFrame.minY - settled) < 1)
    #expect(try #require(surface.anchor()).anchor.characterOffset == target)
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
