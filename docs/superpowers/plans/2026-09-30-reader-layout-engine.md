# The reader's layout engine — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reader's whole-document layout with viewport layout that holds the reader's line through every change of geometry, completes layout in the background, and drives the macOS scroller from a height model of its own.

**Architecture:** Every piece of arithmetic is a pure, tested type in `RFCReaderKit/Layout/`: the anchor (`ReaderAnchor`, `LinePin`), the pin recipe over a `PinSurface` protocol (`PinRecipe`), the height model (`ParagraphMetrics`, `HeightModel`), the scroller's smoothing (`ScrollerHeight`), the slice planner (`SlicePlanner`) and the place keeper (`AnchorKeeper`). The App target gets one adapter, `ReaderLayoutEngine`, which the coordinator drives. It arrives behind a launch flag, is checked by hand on both platforms, and only then replaces the old path.

**Tech Stack:** Swift 6, TextKit 2 (`NSTextLayoutManager`, `NSTextViewportLayoutController`), AppKit/UIKit, Swift Testing, package-benchmark.

**Spec:** `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`. Read it first; this plan argues from it.

## Global Constraints

- Read `CLAUDE.md` before starting; every standing constraint there applies.
- One text storage per document; nothing in the body becomes an attachment or a hosted view.
- Nothing testable in the App target: arithmetic goes in `RFCReaderKit`, the App keeps only TextKit/AppKit/UIKit calls.
- Never assign `NSTextContentStorage.attributedString`; install through `NSTextContentStorage.install(_:)`.
- `DocumentTextBuilder` stays off the main actor; `BuiltDocument` stays immutable after `build`.
- Anchors are stable strings; a place carried across a rebuild is a `ReadingPlace`.
- Print and export keep their own off-screen build and full layout: `DocumentPDF` is not touched.
- Do not use `NSTextViewportLayoutController.relocateViewport(to:)` (the probe measured it landing 1/40 exact) or a point lookup (`textLayoutFragment(for: CGPoint)`) to find what is at the top after a relocation.
- Tests: Swift Testing, raw-identifier names that say what they pin. A test that builds a document reads a committed fixture through `Fixtures.document(named:)` (`rfc8999.xml`); hand-written text is fine for a test that never calls `parse`. No RFC text is committed.
- SwiftLint `--strict` stays clean: identifiers of at least three characters, at most five function parameters, one level of type nesting, lines up to 200 characters. `make fmt` before `make lint`.
- American spelling everywhere.
- Gate for every task: `make check`; after any App change also `make build-app` and `make ios-sim`.
- Commits are signed. If Secretive fails, sign with `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`. End every commit message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- The app is driven only in the background (`open -g -n -a`, JXA by PID, `screencapture -l`); hover, drags and anything needing focus are the maintainer's to check.

## Review Focus

1. **A document shorter than the viewport** (a one-page RFC): pinning must not loop, the model must not index an empty array, and the knob must not divide by zero. Tests in Tasks 2 and 3; the knob's guards in Task 9.
2. **A place carried into a rebuild whose anchor's block came back shorter** (a table re-shaped for a narrow column): the restored character must stay inside the document. Test in Task 6.
3. **The reader at the very top, over the header, through a resize**: the place stays `.top` and the header stays in view, rather than snapping to the first line. Tests in Task 6 and the hand check in Task 7.
4. **A very narrow column** (split view on iPad, about 120 pt of text): many lines per paragraph, fractions near line ends. The resize test in Task 2 runs down to 120 pt.
5. **The knob dragged to the very bottom or top**: it lands exactly at the end or the start, not a paragraph short. The model's ends are tested in Task 3; the knob is checked by hand in Task 9.

---

## File map

Created in `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/`:

| File | Responsibility |
|---|---|
| `LinePin.swift` | `ReaderAnchor`, and `LinePin`: anchor ↔ y within one paragraph fragment |
| `PinRecipe.swift` | `PinSurface` protocol; `PinRecipe.pin` and `PinRecipe.anchor(atContainerTop:…)` |
| `HeightModel.swift` | `ParagraphMetrics` (measured at build) and `HeightModel` (estimate, refine, look up) |
| `ScrollerHeight.swift` | The knob's height: frozen while interacting, eased over 150 ms |
| `SlicePlanner.swift` | Which slice of background layout comes next |
| `AnchorKeeper.swift` | The reader's place: only the reader moves it; carried across a rebuild |

Tests in `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/`, one file per source file, plus `LayoutFixture.swift` (shared headless-layout helper).

Created in the App: `App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift`.

Modified: `BuiltDocument.swift`, `DocumentTextBuilder.swift` (metrics), `RFCTextViewCoordinator.swift`, `RFCTextView.swift` (scroller, scroll target), `ReaderTextView.swift` (`scrollRangeToVisible`, iOS content size), `DocumentView.swift` (#322), `Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift`, `docs/ARCHITECTURE.md`. Deleted in Task 12: `ReadingPlaceTracker.swift` and its tests.

---

### Task 1: The anchor and its line arithmetic

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/LinePin.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/LayoutFixture.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/LinePinTests.swift`

**Interfaces:**
- Produces: `public struct ReaderAnchor { characterOffset: Int; fraction: CGFloat; init(characterOffset:fraction:) }`; `public enum LinePin { static func anchor(atFragmentY:in:fragmentStart:) -> (anchor: ReaderAnchor, line: NSRange); static func fragmentY(of:in:fragmentStart:) -> CGFloat }`; test helper `LayoutFixture` (`init(text:width:)`, `layout`, `setWidth(_:)`, `fragment(at:)`).

- [ ] **Step 1: Write the shared test fixture**

```swift
// LayoutFixture.swift
import Foundation

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A text laid out headless: a content storage, a layout manager and a container.
/// The storage is kept because the layout manager holds it weakly. Written through
/// `install`, never `attributedString`: see CLAUDE.md.
@MainActor
final class LayoutFixture {
  let storage = NSTextContentStorage()
  let layout = NSTextLayoutManager()

  init(text: NSAttributedString, width: CGFloat) {
    storage.install(text)
    storage.addTextLayoutManager(layout)
    layout.textContainer = NSTextContainer(size: CGSize(width: width, height: 10_000_000))
  }

  /// The built text of a committed fixture, at the reader's default style.
  static func built(_ name: String = "rfc8999.xml", measure: CGFloat = 712) throws -> BuiltDocument {
    DocumentTextBuilder.build(try Fixtures.document(named: name), style: ReadingStyle(measure: measure))
  }

  func setWidth(_ width: CGFloat) {
    layout.textContainer?.size = CGSize(width: width, height: 10_000_000)
  }

  /// The paragraph fragment holding `characterOffset`, laid out.
  func fragment(at characterOffset: Int) -> NSTextLayoutFragment? {
    guard let location = layout.location(atOffset: characterOffset),
      let fragment = layout.textLayoutFragment(for: location)
    else { return nil }
    layout.ensureLayout(for: fragment.rangeInElement)
    return layout.textLayoutFragment(for: location)
  }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// LinePinTests.swift
import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's place within one paragraph: which line's first character is at the
/// top of the viewport, and how far down that line the top is.
@Suite("Line pin")
@MainActor
struct LinePinTests {
  /// One long paragraph that wraps many times at any of the widths below, and a
  /// short one after it. Hand-written: nothing here is parsed.
  private let text = NSAttributedString(
    string: String(repeating: "a word that wraps ", count: 120) + "\nA short one.\n",
    attributes: [.font: PlatformFont.systemFont(ofSize: 17)])

  @Test func `a point on a line anchors that line's first character`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let third = fragment.textLineFragments[2]
    let (anchor, line) = LinePin.anchor(
      atFragmentY: third.typographicBounds.midY, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(anchor.characterOffset == third.characterRange.location)
    #expect(abs(anchor.fraction - 0.5) < 0.01)
    #expect(line == third.characterRange)
  }

  @Test func `the spacing above a paragraph belongs to its first line`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: 0, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(anchor == ReaderAnchor(characterOffset: 0, fraction: 0))
  }

  @Test func `an anchor round-trips through its y`() throws {
    let fixture = LayoutFixture(text: text, width: 400)
    let fragment = try #require(fixture.fragment(at: 0))
    let lines = fragment.textLineFragments
    for tenth in 0..<Int(fragment.layoutFragmentFrame.height / 10) {
      let height = CGFloat(tenth) * 10
      let (anchor, _) = LinePin.anchor(atFragmentY: height, in: lines, fragmentStart: 0)
      let back = LinePin.fragmentY(of: anchor, in: lines, fragmentStart: 0)
      #expect(abs(back - min(height, lines.last!.typographicBounds.maxY)) < 0.5)
    }
  }

  /// After a re-wrap the anchor's character is on another line: the y it gives is
  /// that line's, so the character stays at the top.
  @Test(arguments: [300.0, 180.0, 120.0])
  func `after a re-wrap the anchor's character is on the line at its y`(width: CGFloat) throws {
    let fixture = LayoutFixture(text: text, width: 400)
    var fragment = try #require(fixture.fragment(at: 0))
    let (anchor, _) = LinePin.anchor(
      atFragmentY: fragment.textLineFragments[5].typographicBounds.minY + 3,
      in: fragment.textLineFragments, fragmentStart: 0)
    fixture.setWidth(width)
    fragment = try #require(fixture.fragment(at: 0))
    let height = LinePin.fragmentY(of: anchor, in: fragment.textLineFragments, fragmentStart: 0)
    let (_, line) = LinePin.anchor(
      atFragmentY: height, in: fragment.textLineFragments, fragmentStart: 0)
    #expect(NSLocationInRange(anchor.characterOffset, line))
  }
}
```

- [ ] **Step 3: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter LinePinTests`
Expected: FAIL, "cannot find 'LinePin' in scope".

- [ ] **Step 4: Implement**

```swift
// LinePin.swift
import CoreGraphics
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's place: the character that starts the line at the top of the
/// viewport, and how far into that line the viewport's top is, as a share of the
/// line's height. A line, not a paragraph: after a re-wrap the character is still at
/// the top, not the first line of its paragraph.
public struct ReaderAnchor: Sendable, Equatable {
  public let characterOffset: Int
  public let fraction: CGFloat

  public init(characterOffset: Int, fraction: CGFloat = 0) {
    self.characterOffset = characterOffset
    self.fraction = fraction
  }
}

/// An anchor and a y within one paragraph fragment, each from the other.
///
/// A line's span runs from its top to its bottom, except that a fragment's first
/// line starts at the fragment's top, the spacing above it included, which is where
/// `FragmentGeometry.scrollTarget` has always put a paragraph's first character.
/// Both directions measure against the same span, so they are inverses.
public enum LinePin {
  /// The anchor for the viewport's top at `fragmentY`, in the fragment's own
  /// coordinates, and the range of the line it names, document-relative.
  public static func anchor(
    atFragmentY fragmentY: CGFloat, in lines: [NSTextLineFragment], fragmentStart: Int
  ) -> (anchor: ReaderAnchor, line: NSRange) {
    guard let line = lines.first(where: { fragmentY < $0.typographicBounds.maxY }) ?? lines.last
    else {
      return (ReaderAnchor(characterOffset: fragmentStart), NSRange(location: fragmentStart, length: 0))
    }
    let range = NSRange(
      location: fragmentStart + line.characterRange.location, length: line.characterRange.length)
    let span = span(of: line)
    let share = span.height > 0 ? (fragmentY - span.top) / span.height : 0
    let fraction = min(max(share, 0), maximumFraction)
    return (ReaderAnchor(characterOffset: range.location, fraction: fraction), range)
  }

  /// Where the viewport's top goes, in the fragment's own coordinates, to show
  /// `anchor`: the top of the line holding its character, plus its fraction.
  public static func fragmentY(
    of anchor: ReaderAnchor, in lines: [NSTextLineFragment], fragmentStart: Int
  ) -> CGFloat {
    let index = anchor.characterOffset - fragmentStart
    guard let line = lines.first(where: { index < NSMaxRange($0.characterRange) }) ?? lines.last
    else { return 0 }
    let span = span(of: line)
    return span.top + anchor.fraction * span.height
  }

  /// Short of 1, so a fraction never names the next line's top.
  static let maximumFraction: CGFloat = 0.999

  private static func span(of line: NSTextLineFragment) -> (top: CGFloat, height: CGFloat) {
    let bounds = line.typographicBounds
    let top = line.characterRange.location == 0 ? 0 : bounds.minY
    return (top, bounds.maxY - top)
  }
}
```

- [ ] **Step 5: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter LinePinTests`
Expected: PASS, 4 tests (one with three arguments).

- [ ] **Step 6: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/LinePin.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/LayoutFixture.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/LinePinTests.swift
git commit -m "The reader's place is a line's first character and how far into the line the top is

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The pin recipe

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/PinRecipe.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/PinRecipeTests.swift`

**Interfaces:**
- Consumes: `ReaderAnchor`, `LinePin` (Task 1); `NSTextLayoutManager.location(atOffset:)`, `.offset(of:)` (existing, `TextLayoutManager+Offsets.swift`).
- Produces: `@MainActor public protocol PinSurface: AnyObject { var containerTop: CGFloat { get }; func scroll(toContainerY: CGFloat); func layOutViewport() }`; `public enum PinRecipe { @MainActor static func pin(_:in:on:) -> Int; @MainActor static func anchor(atContainerTop:in:from:) -> (anchor: ReaderAnchor, line: NSRange)?; static let maximumPasses: Int }`.

- [ ] **Step 1: Write the failing tests**

```swift
// PinRecipeTests.swift
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
      layout.enumerateTextLayoutFragments(from: first.rangeInElement.location, options: [.ensuresLayout]) {
        $0.layoutFragmentFrame.minY < top + self.height
      }
    }

    /// What is at the top, read from the fragments as the engine reads it.
    func anchor() -> (anchor: ReaderAnchor, line: NSRange)? {
      guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: containerTop)) else { return nil }
      return PinRecipe.anchor(atContainerTop: containerTop, in: layout, from: first.rangeInElement.location)
    }
  }

  @Test func `a jump lands its target at the top from wherever the last one left`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    let surface = Surface(layout: fixture.layout)
    let sections = built.anchors.sections.entries
    // Far, near, backwards, forwards: every kind of move from every kind of state.
    let order = [sections.count - 1, 0, sections.count / 2, sections.count / 3, sections.count - 2, 1]
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
    PinRecipe.pin(ReaderAnchor(characterOffset: middle.offset + 40, fraction: 0.3), in: fixture.layout, on: surface)
    let held = try #require(surface.anchor()).anchor
    let widths = Array(stride(from: 712, through: 120, by: -24)) + Array(stride(from: 120, through: 712, by: 24))
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
    let passes = PinRecipe.pin(ReaderAnchor(characterOffset: last.offset), in: fixture.layout, on: surface)
    #expect(passes <= PinRecipe.maximumPasses)
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter PinRecipeTests`
Expected: FAIL, "cannot find type 'PinSurface' in scope".

- [ ] **Step 3: Implement**

```swift
// PinRecipe.swift
import CoreGraphics
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What the pin recipe needs of a scrolling text view: where the viewport's top is
/// and a way to move it, both in text-container coordinates, and a way to lay out
/// what the viewport now covers. The App's `ReaderLayoutEngine` is one, over
/// `NSTextView` and `UITextView`; the tests have their own.
@MainActor
public protocol PinSurface: AnyObject {
  var containerTop: CGFloat { get }
  func scroll(toContainerY target: CGFloat)
  func layOutViewport()
}

/// The one way the reader's line is put at the top of the viewport, measured in
/// the probe for the layout engine (see the spec): 40 of 40 random jumps exact, and
/// the line held in 276 of 276 resize steps, on RFC 9000 and RFC 5661.
///
/// Lay out only the anchor's paragraph, scroll so its line meets the top, lay out
/// the viewport, and settle again if the estimates above it moved the paragraph.
/// Not `relocateViewport(to:)`, which from a prior relocation put its target at
/// y = 0 or collapsed the viewport.
public enum PinRecipe {
  public static let maximumPasses = 4
  static let settleTolerance: CGFloat = 0.5

  /// Puts `anchor` at the top of `surface`. Answers how many scrolls it took.
  @MainActor
  @discardableResult
  public static func pin(
    _ anchor: ReaderAnchor, in layout: NSTextLayoutManager, on surface: some PinSurface
  ) -> Int {
    guard let location = layout.location(atOffset: anchor.characterOffset),
      let paragraph = layout.textLayoutFragment(for: location)
    else { return 0 }
    layout.ensureLayout(for: paragraph.rangeInElement)
    var passes = 0
    while passes < maximumPasses, let fragment = layout.textLayoutFragment(for: location) {
      let start = layout.offset(of: fragment.rangeInElement.location)
      let wanted =
        fragment.layoutFragmentFrame.minY
        + LinePin.fragmentY(of: anchor, in: fragment.textLineFragments, fragmentStart: start)
      if abs(surface.containerTop - wanted) < settleTolerance { break }
      surface.scroll(toContainerY: wanted)
      surface.layOutViewport()
      passes += 1
    }
    return passes
  }

  /// The anchor at the viewport's top, `top` in container coordinates, read from the
  /// fragments laid out from `start` on: the viewport's own, never a point lookup,
  /// which can answer with a stale fragment. Nil when nothing is laid out there.
  @MainActor
  public static func anchor(
    atContainerTop top: CGFloat, in layout: NSTextLayoutManager, from start: any NSTextLocation
  ) -> (anchor: ReaderAnchor, line: NSRange)? {
    var found: (anchor: ReaderAnchor, line: NSRange)?
    layout.enumerateTextLayoutFragments(from: start, options: []) { fragment in
      let frame = fragment.layoutFragmentFrame
      guard frame.maxY > top else { return true }
      found = LinePin.anchor(
        atFragmentY: max(0, top - frame.minY), in: fragment.textLineFragments,
        fragmentStart: layout.offset(of: fragment.rangeInElement.location))
      return false
    }
    return found
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter PinRecipeTests`
Expected: PASS, 4 tests. If the jump test misses, print the pass count and the target's frame per jump before changing the recipe; the probe's numbers were measured with a text view, and a headless layout manager may estimate differently.

- [ ] **Step 5: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/PinRecipe.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/PinRecipeTests.swift
git commit -m "One recipe puts the reader's line at the top, from anywhere and through a re-wrap

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Paragraph metrics and the height model

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/HeightModel.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/BuiltDocument.swift` (add `paragraphs`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder.swift:93-107` (`build` measures)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/HeightModelTests.swift`

**Interfaces:**
- Produces: `public struct ParagraphMetrics { length, naturalWidth, indent, lineHeight, spacing: …; wraps: Bool (no public init); static func measure(_: NSAttributedString) -> [ParagraphMetrics]; func estimatedHeight(atColumn:) -> CGFloat }`; `public struct HeightModel { init(paragraphs:column:); column; count; total; mutating setColumn(_:); mutating measure(_ heights: [(paragraph: Int, height: CGFloat)]); top(ofParagraph:) -> CGFloat; paragraph(containing:) -> Int; paragraph(atHeight:) -> Int; characterOffset(ofParagraph:) -> Int }`; `BuiltDocument.paragraphs: [ParagraphMetrics]`.

- [ ] **Step 1: Write the failing tests**

```swift
// HeightModelTests.swift
import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The document's height as the scroller sees it: estimated per paragraph from
/// what the builder measured, and exact wherever TextKit has laid a paragraph out.
@Suite("Height model")
@MainActor
struct HeightModelTests {
  @Test func `the builder measures one entry per paragraph`() throws {
    let built = try LayoutFixture.built()
    let string = built.text.string as NSString
    var paragraphs = 0
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]
    ) { _, _, _, _ in paragraphs += 1 }
    #expect(built.paragraphs.count == paragraphs)
    #expect(built.paragraphs.map(\.length).reduce(0, +) == built.text.length)
  }

  /// The probe's crude model was within 6%; the measured one must do better.
  @Test(arguments: [712.0, 320.0])
  func `the estimate is within five percent of the laid-out height`(column: CGFloat) throws {
    let built = try LayoutFixture.built(measure: column)
    let fixture = LayoutFixture(text: built.text, width: column)
    fixture.layout.ensureLayout(for: fixture.layout.documentRange)
    let truth = fixture.layout.usageBoundsForTextContainer.height
    let model = HeightModel(paragraphs: built.paragraphs, column: column)
    #expect(abs(model.total - truth) / truth < 0.05, "estimate \(model.total), truth \(truth)")
  }

  @Test func `measuring every paragraph makes the model exact`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    fixture.layout.ensureLayout(for: fixture.layout.documentRange)
    var model = HeightModel(paragraphs: built.paragraphs, column: 712)
    var heights: [(paragraph: Int, height: CGFloat)] = []
    fixture.layout.enumerateTextLayoutFragments(from: fixture.layout.documentRange.location, options: []) {
      heights.append(
        (model.paragraph(containing: fixture.layout.offset(of: $0.rangeInElement.location)), $0.layoutFragmentFrame.height))
      return true
    }
    model.measure(heights)
    #expect(abs(model.total - fixture.layout.usageBoundsForTextContainer.height) < 1)
  }

  @Test func `a paragraph's top finds the paragraph again`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    for index in stride(from: 0, to: model.count, by: 7) {
      #expect(model.paragraph(atHeight: model.top(ofParagraph: index)) == index)
      #expect(model.paragraph(containing: model.characterOffset(ofParagraph: index)) == index)
    }
  }

  @Test func `the ends of the model are its first and last paragraphs`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    #expect(model.paragraph(atHeight: -50) == 0)
    #expect(model.paragraph(atHeight: model.total) == model.count - 1)
    #expect(model.paragraph(atHeight: model.total + 500) == model.count - 1)
  }

  @Test func `an empty document has no height and answers for paragraph zero`() {
    let model = HeightModel(paragraphs: [], column: 712)
    #expect(model.total == 0)
    #expect(model.paragraph(atHeight: 100) == 0)
    #expect(model.paragraph(containing: 0) == 0)
  }

  @Test func `a narrower column estimates a taller document`() throws {
    var model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    let wide = model.total
    model.setColumn(320)
    #expect(model.total > wide)
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter HeightModelTests`
Expected: FAIL, "value of type 'BuiltDocument' has no member 'paragraphs'".

- [ ] **Step 3: Implement the model**

```swift
// HeightModel.swift
import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What the builder measures of one paragraph, so its height can be estimated at
/// any column without laying it out: its width set on a single line, its line
/// height and the spacing around it.
public struct ParagraphMetrics: Sendable, Equatable {
  public let length: Int
  public let naturalWidth: CGFloat
  public let indent: CGFloat
  public let lineHeight: CGFloat
  public let spacing: CGFloat
  /// False for a verbatim line, which is never wrapped.
  public let wraps: Bool

  // No public initializer: only `measure` makes one, through the memberwise one,
  // whose six parameters SwiftLint would refuse on a public signature.

  /// Every paragraph of `text`, in order, split as `NSTextContentStorage` splits them.
  public static func measure(_ text: NSAttributedString) -> [ParagraphMetrics] {
    let string = text.string as NSString
    var metrics: [ParagraphMetrics] = []
    var start = 0
    while start < string.length {
      let range = string.paragraphRange(for: NSRange(location: start, length: 0))
      metrics.append(measure(range, of: text))
      start = NSMaxRange(range)
    }
    return metrics
  }

  private static func measure(_ range: NSRange, of text: NSAttributedString) -> ParagraphMetrics {
    let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: range) as CFAttributedString)
    let font =
      text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
      ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
    let style =
      text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
      ?? NSParagraphStyle.default
    let natural = font.ascender - font.descender + font.leading
    let multiple = style.lineHeightMultiple > 0 ? style.lineHeightMultiple : 1
    return ParagraphMetrics(
      length: range.length,
      naturalWidth: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
      indent: max(style.headIndent, style.firstLineHeadIndent),
      lineHeight: natural * multiple + style.lineSpacing,
      spacing: style.paragraphSpacing + style.paragraphSpacingBefore,
      wraps: style.lineBreakMode != .byClipping)
  }

  public func estimatedHeight(atColumn column: CGFloat) -> CGFloat {
    guard wraps else { return lineHeight + spacing }
    let lines = max(1, (naturalWidth / max(1, column - indent)).rounded(.up))
    return lines * lineHeight + spacing
  }
}

/// The document's height, paragraph by paragraph: estimated from `ParagraphMetrics`
/// at the column, and exact for every paragraph TextKit has laid out and reported
/// through `measure(_:)`. What the scroller reads, since TextKit's own estimate
/// swings by up to the whole document's height as it lays out (see the spec).
public struct HeightModel: Sendable {
  public private(set) var column: CGFloat
  private let paragraphs: [ParagraphMetrics]
  private let starts: [Int]
  private var heights: [CGFloat]
  /// Each paragraph's top, and the total last: one more than `paragraphs`.
  private var tops: [CGFloat] = [0]

  public init(paragraphs: [ParagraphMetrics], column: CGFloat) {
    self.paragraphs = paragraphs
    self.column = column
    var starts: [Int] = []
    starts.reserveCapacity(paragraphs.count)
    var offset = 0
    for paragraph in paragraphs {
      starts.append(offset)
      offset += paragraph.length
    }
    self.starts = starts
    heights = paragraphs.map { $0.estimatedHeight(atColumn: column) }
    recomputeTops()
  }

  public var count: Int { paragraphs.count }
  public var total: CGFloat { tops.last ?? 0 }

  /// Estimates every paragraph again at `column`; what was measured at the old
  /// column is forgotten, since a re-wrap changed it.
  public mutating func setColumn(_ column: CGFloat) {
    guard column != self.column else { return }
    self.column = column
    heights = paragraphs.map { $0.estimatedHeight(atColumn: column) }
    recomputeTops()
  }

  /// Replaces the estimates of the paragraphs TextKit has laid out.
  public mutating func measure(_ measured: [(paragraph: Int, height: CGFloat)]) {
    guard !measured.isEmpty else { return }
    for entry in measured where heights.indices.contains(entry.paragraph) {
      heights[entry.paragraph] = entry.height
    }
    recomputeTops()
  }

  public func top(ofParagraph index: Int) -> CGFloat {
    tops[min(max(index, 0), tops.count - 1)]
  }

  public func characterOffset(ofParagraph index: Int) -> Int {
    starts.isEmpty ? 0 : starts[min(max(index, 0), starts.count - 1)]
  }

  public func paragraph(containing characterOffset: Int) -> Int {
    max(0, starts.partitioningIndex { $0 > characterOffset } - 1)
  }

  /// The paragraph at `height`, clamped to the first and the last.
  public func paragraph(atHeight height: CGFloat) -> Int {
    guard !paragraphs.isEmpty else { return 0 }
    return min(max(0, tops.partitioningIndex { $0 > height } - 1), paragraphs.count - 1)
  }

  private mutating func recomputeTops() {
    var tops: [CGFloat] = [0]
    tops.reserveCapacity(heights.count + 1)
    var running: CGFloat = 0
    for height in heights {
      running += height
      tops.append(running)
    }
    self.tops = tops
  }
}
```

- [ ] **Step 4: Record the metrics in the build**

In `BuiltDocument.swift`, add the property and the init parameter (default empty, so every existing caller compiles):

```swift
  /// Every paragraph's measurements, for the reader's height model
  /// (`HeightModel`). Empty in a build nothing scrolls, such as a print's.
  public let paragraphs: [ParagraphMetrics]

  public init(
    text: NSAttributedString, anchors: AnchorIndex, keepsWithNext: Set<Int> = [],
    backlinks: [String: [Backlink]] = [:], paragraphs: [ParagraphMetrics] = []
  ) {
    self.text = text
    self.anchors = anchors
    self.keepsWithNext = keepsWithNext
    self.backlinks = backlinks
    self.paragraphs = paragraphs
  }
```

In `DocumentTextBuilder.build`, pass them only for a build with live links (the reader's; a print never scrolls):

```swift
    return BuiltDocument(
      text: builder.output, anchors: AnchorIndex(builder.entries),
      keepsWithNext: builder.keepsWithNext, backlinks: builder.backlinks,
      paragraphs: style.emitsLinks ? ParagraphMetrics.measure(builder.output) : [])
```

- [ ] **Step 5: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter HeightModelTests`
Expected: PASS, 8 test cases. If the five-percent test fails at 320 pt, compare per-paragraph estimates against their fragments for the ten worst paragraphs and fix `estimatedHeight` (list items with a hanging indent are the likeliest culprits); do not loosen the tolerance.

- [ ] **Step 6: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/HeightModel.swift \
  Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/BuiltDocument.swift \
  Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/HeightModelTests.swift
git commit -m "The builder measures every paragraph, and a model estimates the document's height at any column

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The scroller's height, smoothed

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/ScrollerHeight.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/ScrollerHeightTests.swift`

**Interfaces:**
- Produces: `public struct ScrollerHeight { init(total:); shown: CGFloat; isEasing: Bool; mutating modelChanged(to:now:); columnChanged(to:); interactionBegan(); interactionEnded(now:); advance(to:); static let easeDuration: TimeInterval }`.

- [ ] **Step 1: Write the failing tests**

```swift
// ScrollerHeightTests.swift
import Foundation
import Testing

@testable import RFCReaderKit

/// The height the knob is drawn against: never moved under the reader while they
/// scroll or drag, eased to a new total once they stop, and moved at once when the
/// column changes, when everything is moving anyway.
@Suite("Scroller height")
struct ScrollerHeightTests {
  @Test func `a change while the reader scrolls waits until they stop`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.modelChanged(to: 1200, now: 0)
    height.advance(to: 1)
    #expect(height.shown == 1000)
    height.interactionEnded(now: 2)
    height.advance(to: 2 + ScrollerHeight.easeDuration)
    #expect(height.shown == 1200)
  }

  @Test func `a change at rest eases over the ease duration`() {
    var height = ScrollerHeight(total: 1000)
    height.modelChanged(to: 2000, now: 10)
    height.advance(to: 10 + ScrollerHeight.easeDuration / 2)
    #expect(height.shown > 1000 && height.shown < 2000)
    #expect(height.isEasing)
    height.advance(to: 10 + ScrollerHeight.easeDuration)
    #expect(height.shown == 2000)
    #expect(!height.isEasing)
  }

  @Test func `a change of column is shown at once`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.columnChanged(to: 3000)
    #expect(height.shown == 3000)
    #expect(!height.isEasing)
  }

  @Test func `an interaction that ends with nothing changed starts no ease`() {
    var height = ScrollerHeight(total: 1000)
    height.interactionBegan()
    height.interactionEnded(now: 5)
    #expect(!height.isEasing)
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter ScrollerHeightTests`
Expected: FAIL, "cannot find 'ScrollerHeight' in scope".

- [ ] **Step 3: Implement**

```swift
// ScrollerHeight.swift
import CoreGraphics
import Foundation

/// The document height the scroller's knob is drawn against, which follows the
/// `HeightModel` without ever jumping under the reader: frozen while they scroll or
/// drag the knob, eased to the model's total over `easeDuration` once they stop,
/// and moved at once by a change of column.
public struct ScrollerHeight: Sendable, Equatable {
  public static let easeDuration: TimeInterval = 0.15

  public private(set) var shown: CGFloat
  private var target: CGFloat
  private var easeFrom: CGFloat
  private var easeStart: TimeInterval?
  private var isInteracting = false

  public init(total: CGFloat) {
    shown = total
    target = total
    easeFrom = total
  }

  public var isEasing: Bool { easeStart != nil }

  public mutating func modelChanged(to total: CGFloat, now: TimeInterval) {
    target = total
    guard !isInteracting, total != shown else { return }
    easeFrom = shown
    easeStart = now
  }

  public mutating func columnChanged(to total: CGFloat) {
    target = total
    shown = total
    easeStart = nil
  }

  /// Freezes the knob's height where it is.
  public mutating func interactionBegan() {
    isInteracting = true
    easeStart = nil
  }

  public mutating func interactionEnded(now: TimeInterval) {
    isInteracting = false
    guard target != shown else { return }
    easeFrom = shown
    easeStart = now
  }

  public mutating func advance(to now: TimeInterval) {
    guard let easeStart else { return }
    let progress = min(1, max(0, (now - easeStart) / Self.easeDuration))
    let eased = 1 - pow(1 - progress, 3)
    shown = easeFrom + (target - easeFrom) * CGFloat(eased)
    if progress >= 1 {
      shown = target
      self.easeStart = nil
    }
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter ScrollerHeightTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/ScrollerHeight.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/ScrollerHeightTests.swift
git commit -m "The scroller's height never moves under the reader and eases once they stop

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The slice planner

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/SlicePlanner.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/SlicePlannerTests.swift`

**Interfaces:**
- Produces: `public struct SlicePlanner { static let sliceLength = 6_000; init(length:); length; laidOutThrough; isComplete; mutating restart(); mutating nextSlice() -> NSRange? }` — `nextSlice` answers the new range to lay out; the caller lays out from the document's start through its end, because TextKit's positions are exact only once everything above is laid out.

- [ ] **Step 1: Write the failing tests**

```swift
// SlicePlannerTests.swift
import Foundation
import Testing

@testable import RFCReaderKit

/// Background completion's schedule: small slices from the document's start, each
/// one frame's worth of layout, restarted by every change of geometry.
@Suite("Slice planner")
struct SlicePlannerTests {
  @Test func `slices cover the document once, in order`() {
    var planner = SlicePlanner(length: 20_000)
    var covered: [NSRange] = []
    while let slice = planner.nextSlice() { covered.append(slice) }
    #expect(covered.first?.location == 0)
    #expect(covered.map(\.length).reduce(0, +) == 20_000)
    #expect(zip(covered, covered.dropFirst()).allSatisfy { NSMaxRange($0) == $1.location })
    #expect(planner.isComplete)
  }

  @Test func `a slice is never longer than a slice`() {
    var planner = SlicePlanner(length: 50_000)
    while let slice = planner.nextSlice() { #expect(slice.length <= SlicePlanner.sliceLength) }
  }

  @Test func `a restart lays the document out again from its start`() {
    var planner = SlicePlanner(length: 20_000)
    _ = planner.nextSlice()
    _ = planner.nextSlice()
    planner.restart()
    #expect(planner.nextSlice()?.location == 0)
  }

  @Test func `an empty document is complete from the start`() {
    var planner = SlicePlanner(length: 0)
    #expect(planner.isComplete)
    #expect(planner.nextSlice() == nil)
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter SlicePlannerTests`
Expected: FAIL, "cannot find 'SlicePlanner' in scope".

- [ ] **Step 3: Implement**

```swift
// SlicePlanner.swift
import Foundation

/// Which slice of the document background completion lays out next. Slices run
/// from the document's start, because TextKit's positions are exact only once
/// everything above them is laid out, and are small enough to fit in a frame: the
/// probe measured 10–16 ms for 20,000 characters, so 6,000 is about 3–5 ms.
public struct SlicePlanner: Sendable, Equatable {
  public static let sliceLength = 6_000

  public let length: Int
  public private(set) var laidOutThrough = 0

  public init(length: Int) {
    self.length = length
  }

  public var isComplete: Bool { laidOutThrough >= length }

  /// After a change of geometry every fragment is at a new column.
  public mutating func restart() {
    laidOutThrough = 0
  }

  /// The next slice, or nil once the document is laid out. The caller lays out from
  /// the document's start through the slice's end.
  public mutating func nextSlice() -> NSRange? {
    guard !isComplete else { return nil }
    let start = laidOutThrough
    laidOutThrough = min(length, start + Self.sliceLength)
    return NSRange(location: start, length: laidOutThrough - start)
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter SlicePlannerTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/SlicePlanner.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/SlicePlannerTests.swift
git commit -m "Background completion lays the document out in frame-sized slices from its start

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The place keeper

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/AnchorKeeper.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/AnchorKeeperTests.swift`

**Interfaces:**
- Consumes: `ReaderAnchor` (Task 1), `ReadingPlace`, `AnchorIndex` (existing).
- Produces: `public struct AnchorKeeper { enum Place { case top; case line(ReaderAnchor) }; enum Carried { case top; case line(ReadingPlace, fraction: CGFloat) }; place; isEngineMoving; mutating beginEngineMove(); endEngineMove(); userScrolled(to:line:); userScrolledAboveText(); jumped(to:); func carried(in:) -> Carried; mutating restore(_:in:length:); func readingPlace(in:) -> ReadingPlace? }`.

- [ ] **Step 1: Write the failing tests**

```swift
// AnchorKeeperTests.swift
import Foundation
import Testing

@testable import RFCReaderKit

/// The reader's place, which only the reader moves: the engine's own scrolls never
/// record it, a re-wrap never walks it back, and it survives a rebuild.
@Suite("Anchor keeper")
struct AnchorKeeperTests {
  private let index = AnchorIndex([
    AnchorIndex.Entry(anchor: "section-1", offset: 0, heading: "One"),
    AnchorIndex.Entry(anchor: "section-2", offset: 500, heading: "Two"),
  ])

  @Test func `a scroll the engine makes is not the reader's`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 120))
    keeper.beginEngineMove()
    keeper.userScrolled(to: ReaderAnchor(characterOffset: 900), line: NSRange(location: 900, length: 40))
    keeper.endEngineMove()
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 120)))
  }

  @Test func `a scroll the reader makes moves the place`() {
    var keeper = AnchorKeeper()
    keeper.userScrolled(to: ReaderAnchor(characterOffset: 900, fraction: 0.2), line: NSRange(location: 900, length: 40))
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 900, fraction: 0.2)))
  }

  /// A re-wrap starts the line earlier than the place; recording the line's start
  /// would walk the place back on every step of a resize.
  @Test func `a line that still holds the place keeps its character`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 530))
    keeper.userScrolled(to: ReaderAnchor(characterOffset: 510, fraction: 0.4), line: NSRange(location: 510, length: 60))
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 530, fraction: 0.4)))
  }

  @Test func `above the text the place is the top, and a jump works during an engine move`() {
    var keeper = AnchorKeeper()
    keeper.userScrolledAboveText()
    #expect(keeper.place == .top)
    keeper.beginEngineMove()
    keeper.jumped(to: ReaderAnchor(characterOffset: 42))
    keeper.endEngineMove()
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 42)))
  }

  @Test func `the top survives a rebuild as the top`() {
    var keeper = AnchorKeeper()
    let carried = keeper.carried(in: index)
    keeper.restore(carried, in: index, length: 1000)
    #expect(keeper.place == .top)
  }

  @Test func `a place survives a rebuild that moved every offset`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 540, fraction: 0.25))
    let carried = keeper.carried(in: index)
    let rebuilt = AnchorIndex([
      AnchorIndex.Entry(anchor: "section-1", offset: 0, heading: "One"),
      AnchorIndex.Entry(anchor: "section-2", offset: 800, heading: "Two"),
    ])
    keeper.restore(carried, in: rebuilt, length: 2000)
    #expect(keeper.place == .line(ReaderAnchor(characterOffset: 840, fraction: 0.25)))
  }

  /// A table re-shaped for a narrow column comes back shorter; the place stays
  /// inside the document rather than past its end.
  @Test func `a place in a block that came back shorter stays inside the document`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 990))
    let carried = keeper.carried(in: index)
    keeper.restore(carried, in: index, length: 600)
    guard case .line(let anchor) = keeper.place else {
      Issue.record("expected a line")
      return
    }
    #expect(anchor.characterOffset < 600)
  }

  @Test func `the reading place to save names the anchor and the distance past it`() {
    var keeper = AnchorKeeper()
    keeper.jumped(to: ReaderAnchor(characterOffset: 520))
    #expect(keeper.readingPlace(in: index) == ReadingPlace(anchor: "section-2", offset: 20))
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter AnchorKeeperTests`
Expected: FAIL, "cannot find 'AnchorKeeper' in scope".

- [ ] **Step 3: Implement**

```swift
// AnchorKeeper.swift
import CoreGraphics
import Foundation

/// The reader's place under viewport layout, which only the reader moves.
///
/// A scroll the reader makes records the line at the top. A move the engine makes —
/// a pin, a slice landing, a correction of the height — happens between
/// `beginEngineMove()` and `endEngineMove()`, and the scrolls it causes record
/// nothing. That one rule replaces `ReadingPlaceTracker`'s pausing around a
/// rebuild: the engine never records its own moves, so there is nothing to pause.
public struct AnchorKeeper: Sendable, Equatable {
  public enum Place: Sendable, Equatable {
    /// Above the text, where the header is.
    case top
    case line(ReaderAnchor)
  }

  /// The place as it crosses a rebuild, which moves every character offset.
  public enum Carried: Sendable, Equatable {
    case top
    case line(ReadingPlace, fraction: CGFloat)
  }

  public private(set) var place: Place = .top
  private var engineMoves = 0

  public init() {}

  public var isEngineMoving: Bool { engineMoves > 0 }

  public mutating func beginEngineMove() {
    engineMoves += 1
  }

  public mutating func endEngineMove() {
    engineMoves = max(0, engineMoves - 1)
  }

  /// The reader scrolled: `line` is at the top, `anchor` names it. While that line
  /// still holds the character the place names, the character is kept.
  public mutating func userScrolled(to anchor: ReaderAnchor, line: NSRange) {
    guard !isEngineMoving else { return }
    if case .line(let previous) = place,
      previous.characterOffset == line.location || NSLocationInRange(previous.characterOffset, line)
    {
      place = .line(ReaderAnchor(characterOffset: previous.characterOffset, fraction: anchor.fraction))
      return
    }
    place = .line(anchor)
  }

  public mutating func userScrolledAboveText() {
    guard !isEngineMoving else { return }
    place = .top
  }

  /// A jump names the place directly, even during an engine move.
  public mutating func jumped(to anchor: ReaderAnchor) {
    place = .line(anchor)
  }

  public func carried(in index: AnchorIndex) -> Carried {
    switch place {
    case .top: .top
    case .line(let anchor):
      .line(ReadingPlace(at: anchor.characterOffset, in: index), fraction: anchor.fraction)
    }
  }

  public mutating func restore(_ carried: Carried, in index: AnchorIndex, length: Int) {
    switch carried {
    case .top:
      place = .top
    case .line(let reading, let fraction):
      let offset = reading.documentOffset(in: index, length: length) ?? 0
      place = .line(ReaderAnchor(characterOffset: min(offset, max(0, length - 1)), fraction: fraction))
    }
  }

  /// The place to save as the reading position (#322); nil at the top.
  public func readingPlace(in index: AnchorIndex) -> ReadingPlace? {
    guard case .line(let anchor) = place else { return nil }
    return ReadingPlace(at: anchor.characterOffset, in: index)
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter AnchorKeeperTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Gate and commit**

```bash
make fmt && make check
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Layout/AnchorKeeper.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Layout/AnchorKeeperTests.swift
git commit -m "Only the reader moves their place: the engine's own scrolls record nothing

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The engine in the app, behind a flag — then stop for a hand check

**Files:**
- Create: `App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift` (the `textView` `didSet`, `install`, `layOut`, `scroll(toOffset:)`, `reportVisibleAnchor`)

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: `final class ReaderLayoutEngine: PinSurface { static var isEnabled: Bool; weak var textView: PlatformTextView?; keeper; model; installed(_:column:); columnChanged(to:); pin(); jump(toOffset:); userScrolled() -> NSRange? }`, and `RFCTextViewCoordinator.engine`.

- [ ] **Step 1: Create the engine**

```swift
// ReaderLayoutEngine.swift
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The reader's geometry under viewport layout: the text view is a `PinSurface`,
/// the reader's place is an `AnchorKeeper`, and every change of geometry ends in
/// one `PinRecipe.pin`. Only calls into the text view live here; the arithmetic is
/// RFCReaderKit's. See `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`.
final class ReaderLayoutEngine: PinSurface {
  /// On with the launch argument `-ReaderViewportLayout YES`, until the old path
  /// is removed.
  static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ReaderViewportLayout") }

  weak var textView: PlatformTextView?
  private(set) var keeper = AnchorKeeper()
  private(set) var model: HeightModel?
  private(set) var built: BuiltDocument?

  // MARK: - PinSurface

  var containerTop: CGFloat { textView?.viewportTop ?? 0 }

  func scroll(toContainerY target: CGFloat) {
    guard let textView else { return }
    textView.scroll(toY: target + textView.containerTop)
  }

  func layOutViewport() {
    guard let textView else { return }
    textView.syncLayout()
    textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
  }

  // MARK: - Changes of geometry

  /// A new storage is in, built for `column`: carries the place across and pins it.
  func installed(_ built: BuiltDocument, column: CGFloat?) {
    let carried = self.built.map { keeper.carried(in: $0.anchors) }
    self.built = built
    model = column.map { HeightModel(paragraphs: built.paragraphs, column: $0) }
    if let carried { keeper.restore(carried, in: built.anchors, length: built.text.length) }
    pin()
  }

  func columnChanged(to column: CGFloat) {
    model?.setColumn(column)
    pin()
  }

  /// Puts the place back at the top of the viewport. The engine's own move: the
  /// scrolls it causes record nothing.
  func pin() {
    guard let layout = textView?.textLayoutManager else { return }
    keeper.beginEngineMove()
    defer { keeper.endEngineMove() }
    switch keeper.place {
    case .top:
      textView?.scroll(toY: 0)
      layOutViewport()
    case .line(let anchor):
      PinRecipe.pin(anchor, in: layout, on: self)
    }
  }

  func jump(toOffset offset: Int) {
    keeper.jumped(to: ReaderAnchor(characterOffset: offset))
    pin()
  }

  /// A scroll happened; if the reader made it, it moves their place. Answers the line
  /// now at the top, or nil above the text.
  @discardableResult
  func userScrolled() -> NSRange? {
    guard let textView, let layout = textView.textLayoutManager else { return nil }
    let top = textView.viewportTop
    guard top >= 0 else {
      keeper.userScrolledAboveText()
      return nil
    }
    guard let start = layout.textViewportLayoutController.viewportRange?.location,
      let found = PinRecipe.anchor(atContainerTop: top, in: layout, from: start)
    else { return nil }
    keeper.userScrolled(to: found.anchor, line: found.line)
    return found.line
  }
}
```

- [ ] **Step 2: Wire the coordinator, every change behind `ReaderLayoutEngine.isEnabled`**

In `RFCTextViewCoordinator`:

1. Beside `tracker`, add:
   ```swift
   /// The reader's geometry under viewport layout; see `ReaderLayoutEngine`.
   let engine = ReaderLayoutEngine()
   ```
2. In `textView`'s `didSet`, first line: `engine.textView = textView`.
3. In `install(_:)`, replace
   ```swift
   beginLayout()
   if laidOutColumn != nil { restorePlace(fallback: fallback) }
   ```
   with
   ```swift
   if ReaderLayoutEngine.isEnabled {
     engine.installed(built, column: laidOutColumn)
     reportVisibleAnchor()
   } else {
     beginLayout()
     if laidOutColumn != nil { restorePlace(fallback: fallback) }
   }
   ```
4. In `layOut(width:measure:)`, inside `if columnChanged {`, after the container is resized, wrap the tracker branch:
   ```swift
   if ReaderLayoutEngine.isEnabled {
     engine.columnChanged(to: column)
   } else if tracker.columnChanged(to: column) {
     beginLayout()
     restorePlace()
   } else {
     layoutTask?.cancel()
     endLayoutInterval()
     laidOutEnd = nil
     laidOutThrough = 0
   }
   ```
   and after the `if columnChanged { … }` block add:
   ```swift
   // The gutter or the header moved the container in the view: the same line stays on top.
   if ReaderLayoutEngine.isEnabled, !columnChanged { engine.pin() }
   ```
5. At the top of `scroll(toOffset:animated:)`:
   ```swift
   if ReaderLayoutEngine.isEnabled {
     engine.jump(toOffset: offset)
     reportVisibleAnchor()
     return
   }
   ```
6. In `reportVisibleAnchor()`, after `guard let textView, let built, let layout … else { return }`, compute the offset from the engine when it is on:
   ```swift
   let offset: Int
   if ReaderLayoutEngine.isEnabled {
     offset = engine.userScrolled()?.location ?? 0
   } else {
     let top = max(0, textView.viewportTop)
     guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
     offset = layout.offset(of: fragment.rangeInElement.location)
     let line = FragmentGeometry.topLine(
       atViewportTop: top,
       fragmentTop: fragment.layoutFragmentFrame.minY,
       in: fragment.textLineFragments,
       fragmentStart: offset,
       fragmentEnd: layout.offset(of: fragment.rangeInElement.endLocation)
     )
     tracker.report(
       viewportTop: textView.viewportTop, line: line, in: built.anchors, length: built.text.length)
   }
   ```
   replacing the lines from `let top = max(0, textView.viewportTop)` through `tracker.report(…)`, and keep the section lookup that follows (`sectionIndex.anchor(at: offset)` …), which already reads `offset`.

- [ ] **Step 3: Build both platforms**

Run: `make fmt && make lint && make build-app && make ios-sim`
Expected: both succeed with no warnings from these files.

- [ ] **Step 4: Check it runs with the flag, in the background**

```bash
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/RFCReader-*/Build/Products/Debug/RFCReader.app | head -1)  # this worktree's: check its info.plist WorkspacePath
open -g -n -a "$APP" --args -ReaderViewportLayout YES
PID=$(pgrep -nf "$APP/Contents/MacOS/RFCReader")
osascript -l JavaScript -e "const a=Application($PID); a.openRfc('5661'); delay(3); a.jumpToSection('18.13.3',{in:a.windows[0]}); a.windows[0].currentSection()"
```
Expected: `18.13.3`, returned without the ~0.5 s stall a deep jump has today. Screenshot with `screencapture -l <windowID>` and confirm the section heading is at the top of the text.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift
git commit -m "The reader can lay out only its viewport and pin the reader's line, behind a launch flag

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: STOP — hand check with the maintainer**

Hand the maintainer the app launched with `-ReaderViewportLayout YES` on RFC 9197 §4.4.1 and RFC 5661, and on iOS (`ReaderViewportLayout` set in the scheme's arguments). They check:
- a live window resize, wide and narrow: the line at the top stays; prose re-wraps live, artwork and tables adapt when the rebuild lands;
- the very top of a document through a resize: the header stays in view;
- a deep jump from the contents panel lands exactly and at once;
- iOS rotation and split view keep the line.

Do not start Task 8 until they report back. A failure here is a finding about the probe's headless numbers (spec, "Risks") and goes back to the design, not into a workaround.

---

### Task 8: Background completion refines the model

**Files:**
- Modify: `App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift` (release the task in `releaseDocument()` / deinit)

**Interfaces:**
- Consumes: `SlicePlanner` (Task 5), `HeightModel.measure` (Task 3), `ScrollerHeight` (Task 4).
- Produces: `ReaderLayoutEngine.scrollerHeight: ScrollerHeight`, `ReaderLayoutEngine.onHeightChange: () -> Void`, `ReaderLayoutEngine.stop()`.

- [ ] **Step 1: Add completion to the engine**

```swift
  // MARK: - Background completion

  private var planner = SlicePlanner(length: 0)
  private var completion: Task<Void, Never>?
  /// When the reader last scrolled, for pausing completion while they do.
  private var lastUserScroll = ContinuousClock.now - .seconds(1)
  private(set) var scrollerHeight = ScrollerHeight(total: 0)
  /// Told whenever `scrollerHeight.shown` moved, so the scroller is redrawn.
  var onHeightChange: () -> Void = {}

  /// Lays the document out from its start in the background, a slice per idle turn.
  private func startCompletion() {
    completion?.cancel()
    planner = SlicePlanner(length: built?.text.length ?? 0)
    completion = Task { [weak self] in
      while let self, !self.planner.isComplete || self.scrollerHeight.isEasing {
        try? await Task.sleep(for: .milliseconds(self.isInteracting ? 50 : 4))
        guard !Task.isCancelled else { return }
        self.advanceScroller()
        guard !self.isInteracting, !self.planner.isComplete else { continue }
        self.layOutSlice()
      }
    }
  }

  func stop() {
    completion?.cancel()
    completion = nil
  }

  private var isInteracting: Bool {
    guard let textView else { return false }
    #if canImport(UIKit)
      return textView.isTracking || textView.isDecelerating
    #else
      return textView.inLiveResize || ContinuousClock.now - lastUserScroll < .milliseconds(150)
    #endif
  }

  private func layOutSlice() {
    guard let layout = textView?.textLayoutManager, let slice = planner.nextSlice(),
      let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { return }
    layout.ensureLayout(for: range)
    recordHeights(of: slice, in: layout)
    pin()
  }

  private func recordHeights(of slice: NSRange, in layout: NSTextLayoutManager) {
    guard var model, let location = layout.location(atOffset: slice.location) else { return }
    var measured: [(paragraph: Int, height: CGFloat)] = []
    layout.enumerateTextLayoutFragments(from: location, options: []) { fragment in
      let offset = layout.offset(of: fragment.rangeInElement.location)
      guard offset < NSMaxRange(slice) else { return false }
      measured.append((model.paragraph(containing: offset), fragment.layoutFragmentFrame.height))
      return true
    }
    model.measure(measured)
    self.model = model
    scrollerHeight.modelChanged(to: model.total, now: Date.timeIntervalSinceReferenceDate)
  }

  private func advanceScroller() {
    let before = scrollerHeight.shown
    if !isInteracting { scrollerHeight.interactionEnded(now: Date.timeIntervalSinceReferenceDate) }
    scrollerHeight.advance(to: Date.timeIntervalSinceReferenceDate)
    if scrollerHeight.shown != before { onHeightChange() }
  }
```

Then:
- in `installed(_:column:)`, after setting `model`, add `scrollerHeight.columnChanged(to: model?.total ?? 0)` and, after `pin()`, `startCompletion()`;
- in `columnChanged(to:)`, after `model?.setColumn(column)`, add `scrollerHeight.columnChanged(to: model?.total ?? 0)`, and after `pin()`, `startCompletion()`;
- in `userScrolled()`, after the `guard let textView …` line, add:
  ```swift
  if !keeper.isEngineMoving {
    lastUserScroll = .now
    scrollerHeight.interactionBegan()
  }
  ```

- [ ] **Step 2: Stop it with the document**

In `RFCTextViewCoordinator.releaseDocument()` add `engine.stop()` as its first line, and in `deinit` nothing more is needed: the task holds the engine weakly.

- [ ] **Step 3: Build and check in the background**

Run: `make fmt && make lint && make build-app && make ios-sim`
Then launch with the flag on RFC 5661 (as in Task 7, Step 4), wait 3 s, jump to `18.13.3`, and confirm with `currentSection()` that it reads `18.13.3` — completion ran under the jump without moving it.

- [ ] **Step 4: Commit**

```bash
git add App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift
git commit -m "Background completion lays the document out in slices and refines the height model

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The macOS scroller reads the model

**Files:**
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift` (`ReaderScrollView`, a new `ReaderScroller`, and the scroll view's assembly in `makeNSView`)
- Modify: `App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift` (`knob`, `jump(toFraction:)`)
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift` (wire the two)

**Interfaces:**
- Consumes: `HeightModel`, `ScrollerHeight`, `PinRecipe.anchor(atContainerTop:in:from:)`.
- Produces: `ReaderLayoutEngine.knob() -> (position: Double, proportion: CGFloat)?`, `ReaderLayoutEngine.jump(toFraction:)`, `ReaderScrollView.knob`, `ReaderScroller.knobMoved`, `ReaderScroller.knobTracking`.

- [ ] **Step 1: The scroller and the scroll view**

In `RFCTextView.swift`, inside `#if !canImport(UIKit)`, add beside `ReaderScrollView`:

```swift
  /// The reader's vertical scroller: drawn as the stock one, but its knob is placed
  /// from the reader's height model, and dragging it is a jump. See
  /// `ReaderLayoutEngine.knob()`.
  final class ReaderScroller: NSScroller {
    /// The knob dragged, or a click in the track that jumps there, to this share of
    /// the document.
    var knobMoved: ((Double) -> Void)?
    /// True as a knob drag begins, false as it ends.
    var knobTracking: ((Bool) -> Void)?

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
      if hitPart == .knob || hitPart == .knobSlot, let knobMoved {
        knobMoved(doubleValue)
        return true
      }
      return super.sendAction(action, to: target)
    }

    override func trackKnob(with event: NSEvent) {
      knobTracking?(true)
      super.trackKnob(with: event)
      knobTracking?(false)
    }
  }
```

In `ReaderScrollView` add:

```swift
    /// Where the knob goes and how big it is, from the reader's height model; nil
    /// leaves AppKit's own.
    var knob: (() -> (position: Double, proportion: CGFloat)?)?

    override func reflectScrolledClipView(_ clip: NSClipView) {
      super.reflectScrolledClipView(clip)
      guard let knob = knob?(), let scroller = verticalScroller else { return }
      scroller.knobProportion = knob.proportion
      scroller.doubleValue = knob.position
    }
```

In `makeNSView`, after `scroll.hasVerticalScroller = true`, when the engine is on:

```swift
      if ReaderLayoutEngine.isEnabled {
        let scroller = ReaderScroller()
        scroll.verticalScroller = scroller
        context.coordinator.attach(scroller: scroller, to: scroll)
      }
```

- [ ] **Step 2: The engine's knob**

In `ReaderLayoutEngine`:

```swift
  /// The knob's position, 0 at the top and 1 at the end, and its size, from the
  /// model: where the line at the top sits in it, plus how far into that line.
  func knob() -> (position: Double, proportion: CGFloat)? {
    guard let textView, let layout = textView.textLayoutManager, let model,
      model.count > 0, scrollerHeight.shown > 0
    else { return nil }
    let visible = textView.viewportHeight
    let range = max(1, scrollerHeight.shown - visible)
    let proportion = min(1, visible / scrollerHeight.shown)
    guard case .line(let anchor) = keeper.place,
      let location = layout.location(atOffset: anchor.characterOffset),
      let fragment = layout.textLayoutFragment(for: location)
    else { return (0, proportion) }
    let paragraph = model.paragraph(containing: anchor.characterOffset)
    let within = max(0, textView.viewportTop - fragment.layoutFragmentFrame.minY)
    let height = model.top(ofParagraph: paragraph) + within
    return (Double(min(1, max(0, height / range))), proportion)
  }

  /// The knob moved to `fraction`: the character at that height in the model, put
  /// at the top by the pin recipe. The ends are the document's first and last lines.
  func jump(toFraction fraction: Double) {
    guard let textView, let layout = textView.textLayoutManager, let model, model.count > 0 else { return }
    let range = max(0, scrollerHeight.shown - textView.viewportHeight)
    let height = CGFloat(fraction) * range
    let paragraph = model.paragraph(atHeight: height)
    keeper.jumped(to: ReaderAnchor(characterOffset: model.characterOffset(ofParagraph: paragraph)))
    pin()
    let within = height - model.top(ofParagraph: paragraph)
    guard within > 0 else { return }
    keeper.beginEngineMove()
    scroll(toContainerY: containerTop + within)
    layOutViewport()
    keeper.endEngineMove()
    if let start = layout.textViewportLayoutController.viewportRange?.location,
      let found = PinRecipe.anchor(atContainerTop: containerTop, in: layout, from: start)
    {
      keeper.jumped(to: found.anchor)
    }
  }
```

- [ ] **Step 3: Wire them in the coordinator**

In `RFCTextViewCoordinator` (macOS only):

```swift
  #if !canImport(UIKit)
    func attach(scroller: ReaderScroller, to scroll: ReaderScrollView) {
      scroll.knob = { [weak self] in self?.engine.knob() }
      scroller.knobMoved = { [weak self] fraction in
        self?.engine.jump(toFraction: fraction)
        self?.reportVisibleAnchor()
      }
      scroller.knobTracking = { [weak self] tracking in
        guard let self else { return }
        if tracking {
          self.engine.knobTrackingBegan()
        }
      }
      engine.onHeightChange = { [weak scroll] in
        guard let scroll else { return }
        scroll.reflectScrolledClipView(scroll.contentView)
      }
    }
  #endif
```

and in `ReaderLayoutEngine` add `func knobTrackingBegan() { scrollerHeight.interactionBegan(); lastUserScroll = .now }` — `lastUserScroll` keeps `isInteracting` true through the drag, since `trackKnob` sends actions throughout it.

- [ ] **Step 4: Build, check the ends in the background**

Run: `make fmt && make lint && make build-app && make ios-sim`
Launch with the flag on RFC 5661 and take a screenshot: the knob is drawn, small, near the top. Dragging it is the maintainer's check in Step 6; JXA cannot drag a knob.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader/Views/Rendering/RFCTextView.swift App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift \
  App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift
git commit -m "The Mac's scroller places its knob from the height model, and dragging it is a jump

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Hand check with the maintainer**

With the flag, on RFC 5661, beside a stock-scroller window of another app: overlay style and appearance; dragging the knob to the very bottom lands on the last line and to the very top on the first; click-in-track paging; the knob never jumps while scrolling with a trackpad; VoiceOver reads the scroll bar's value.

---

### Task 10: iOS holds its content height still while the reader scrolls

UIKit's indicator cannot be separated from the content offset, which is in TextKit's coordinates, so iOS takes the spec's fallback directly: the content height TextKit reports is applied only when the reader is not touching or flinging, and the pin that follows a change keeps the line.

**Files:**
- Modify: `App/RFCReader/Views/Rendering/ReaderTextView.swift` (the UIKit `ReaderTextView`)
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift` (`scrollViewDidEndDecelerating`, `scrollViewDidEndDragging`)

**Interfaces:**
- Produces: `ReaderTextView.holdsContentSize: Bool` (UIKit), `ReaderTextView.applyHeldContentSize()`.

- [ ] **Step 1: Hold the content size**

In the UIKit `ReaderTextView`:

```swift
    /// On while the viewport-layout engine runs: a content size TextKit reports while
    /// the reader touches or flings is held and applied when they stop, so the
    /// indicator does not jump under them.
    var holdsContentSize = false
    private var heldContentSize: CGSize?

    override var contentSize: CGSize {
      get { super.contentSize }
      set {
        guard holdsContentSize, isTracking || isDecelerating else {
          super.contentSize = newValue
          return
        }
        heldContentSize = newValue
      }
    }

    func applyHeldContentSize() {
      guard let held = heldContentSize else { return }
      heldContentSize = nil
      super.contentSize = held
    }
```

- [ ] **Step 2: Apply it when the reader stops, and pin**

In the coordinator's `UIScrollViewDelegate` conformance (beside `scrollViewDidScroll`):

```swift
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      settleHeldContentSize()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate { settleHeldContentSize() }
    }

    private func settleHeldContentSize() {
      guard ReaderLayoutEngine.isEnabled, let textView = textView as? ReaderTextView else { return }
      textView.applyHeldContentSize()
      engine.pin()
    }
```

and where the UIKit representable sets up the text view (`makeUIView`), after `context.coordinator.textView = textView`: `textView.holdsContentSize = ReaderLayoutEngine.isEnabled`.

- [ ] **Step 3: Build**

Run: `make fmt && make lint && make ios-sim && make build-app`

- [ ] **Step 4: Commit**

```bash
git add App/RFCReader/Views/Rendering/ReaderTextView.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift
git commit -m "On iOS the content height waits for the reader to stop scrolling, then the line is pinned

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand check on a device** (the maintainer): fling through RFC 5661 top to bottom; the indicator neither shrinks nor leaps mid-fling; the line stays put when it settles.

---

### Task 11: Find and VoiceOver scroll through the recipe

**Files:**
- Modify: `App/RFCReader/Views/Rendering/ReaderTextView.swift` (both platforms: `scrollRangeToVisible`)
- Modify: `App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift` (`reveal(_:)`)
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift` (wire the closure in both `make…View`)

**Interfaces:**
- Produces: `ReaderTextView.revealRange: ((NSRange) -> Bool)?`, `ReaderLayoutEngine.reveal(_ range: NSRange) -> Bool`.

- [ ] **Step 1: Route the scroll**

In both `ReaderTextView`s (AppKit and UIKit; the method has the same name and signature):

```swift
    /// A find match or a VoiceOver rotor stop far from the viewport lands on an
    /// estimate under viewport layout; the engine puts it there exactly instead.
    var revealRange: ((NSRange) -> Bool)?

    override func scrollRangeToVisible(_ range: NSRange) {
      if revealRange?(range) == true { return }
      super.scrollRangeToVisible(range)
    }
```

In `ReaderLayoutEngine`:

```swift
  /// Puts `range` a third of the way down the viewport when it is outside what is
  /// laid out around it; answers false when it is near enough for the text view's own
  /// scroll, whose geometry there is laid out.
  func reveal(_ range: NSRange) -> Bool {
    guard let textView, let layout = textView.textLayoutManager,
      let viewport = layout.textViewportLayoutController.viewportRange,
      let near = layout.range(of: viewport)
    else { return false }
    if NSLocationInRange(range.location, near) { return false }
    jump(toOffset: range.location)
    keeper.beginEngineMove()
    scroll(toContainerY: containerTop - textView.viewportHeight / 3)
    layOutViewport()
    keeper.endEngineMove()
    userScrolledAfterReveal()
    return true
  }

  /// A reveal is the reader's move: record where it left the top.
  private func userScrolledAfterReveal() {
    guard let layout = textView?.textLayoutManager,
      let start = layout.textViewportLayoutController.viewportRange?.location,
      let found = PinRecipe.anchor(atContainerTop: max(0, containerTop), in: layout, from: start)
    else { return }
    keeper.jumped(to: found.anchor)
  }
```

In both `make…View`, beside the other closures:

```swift
      textView.revealRange = { [weak coordinator = context.coordinator] range in
        guard ReaderLayoutEngine.isEnabled, let coordinator else { return false }
        let revealed = coordinator.engine.reveal(range)
        if revealed { coordinator.reportVisibleAnchor() }
        return revealed
      }
```

- [ ] **Step 2: Build**

Run: `make fmt && make lint && make build-app && make ios-sim`

- [ ] **Step 3: Commit**

```bash
git add App/RFCReader/Views/Rendering/ReaderTextView.swift App/RFCReader/Views/Rendering/ReaderLayoutEngine.swift \
  App/RFCReader/Views/Rendering/RFCTextView.swift
git commit -m "Find and VoiceOver reach a far match through the pin recipe, not an estimate

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Hand check** (the maintainer): with the flag, find a term that first occurs near the end of RFC 5661 from its top (⌘F, Return): the match is on screen, a third down. VoiceOver's headings rotor to the last heading: it is on screen.

---

### Task 12: The saved reading position is the reader's line (#322)

**Files:**
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift` (`VisibleAnchorBox`, `reportVisibleAnchor`, `scroll(to:animated:)`)
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift` (`ReaderScrollTarget`, its handling in `ReaderInputs.apply`)
- Modify: `App/RFCReader/Views/Document/DocumentView.swift` (`saveReadingPosition`, the restore in `.onAppear`)

**Interfaces:**
- Consumes: `AnchorKeeper.readingPlace(in:)` (Task 6), `ReadingPosition.place` (existing).
- Produces: `VisibleAnchorBox.place: ReadingPlace?`, `ReaderScrollTarget.offset: Int`, `RFCTextViewCoordinator.scroll(to:offset:animated:)`.

- [ ] **Step 1: Carry the place out**

- `VisibleAnchorBox`: add `var place: ReadingPlace?`.
- In `reportVisibleAnchor()`, when the engine is on, right after the offset is computed: `lastVisibleAnchor?.place = engine.keeper.readingPlace(in: built.anchors)`.
- `DocumentView.saveReadingPosition()`: save `lastVisibleAnchor.place ?? ReadingPlace(anchor: anchor, offset: 0)` instead of the offset-zero place, and delete the comment about the anchor alone.

- [ ] **Step 2: Restore the line**

- `ReaderScrollTarget`: add `var offset: Int = 0` (after `animated`, so every existing initializer call compiles).
- In `DocumentView`'s `.onAppear`, replace the stored-position branch with:
  ```swift
  } else if let saved = storedPosition()?.place, let anchor = saved.anchor,
    document.section(anchor: anchor) != nil
  {
    scrollTarget = ReaderScrollTarget(anchor: anchor, animated: false, offset: saved.offset)
  }
  ```
  The section check stays as it is: every position saved so far names a section anchor, and `ReadingPlace(at:in:)` records the nearest anchor of any kind only from now on, which `scroll(to:offset:animated:)` resolves whether it is a section's or not. Widening the check to any anchor is a follow-up if a saved place ever fails to restore.
- In `ReaderInputs.apply`, pass the offset: `coordinator.scroll(to: scrollTarget.anchor, offset: scrollTarget.offset, animated: scrollTarget.animated)`.
- In the coordinator, give `scroll(to:animated:)` an `offset: Int = 0` parameter and resolve through `ReadingPlace` so a stale offset stays inside its block:
  ```swift
  guard let built,
    let offset = ReadingPlace(anchor: anchor, offset: extra).documentOffset(in: built.anchors, length: built.text.length)
  else { return }
  ```
  (renaming the new parameter's internal name to `extra`), and `tracker.jumped(to: ReadingPlace(anchor: anchor, offset: extra))`.

- [ ] **Step 3: Build and check in the background**

Run: `make fmt && make lint && make build-app && make ios-sim`
Launch with the flag on RFC 5661; jump to `18.13.3`; scroll down a few screens with `a.windows[0]` … there is no scripted scroll, so instead: quit this instance with `kill`, relaunch, reopen RFC 5661 and read `currentSection()`: it is the section that was on screen. A line-exact check is the maintainer's in Task 12's hand check.

- [ ] **Step 4: Commit and hand check**

```bash
git add App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift App/RFCReader/Views/Rendering/RFCTextView.swift \
  App/RFCReader/Views/Document/DocumentView.swift
git commit -m "A saved reading position is the line the reader left, not its section's heading (#322)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

The maintainer: scroll halfway into a long section, go back to the list, reopen the document — the same line is at the top.

---

### Task 13: The old path goes, and the decision is recorded

Only after the hand checks in Tasks 7, 9, 10, 11 and 12 passed.

**Files:**
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`, `ReaderLayoutEngine.swift`, `RFCTextView.swift`, `ReaderTextView.swift`
- Delete: `Packages/RFCReaderKit/Sources/RFCReaderKit/Navigation/ReadingPlaceTracker.swift`, `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Navigation/ReadingPlaceTrackerTests.swift`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Remove the flag and the old branches**

- Delete `ReaderLayoutEngine.isEnabled` and every `if ReaderLayoutEngine.isEnabled` branch, keeping the engine's side of each.
- From the coordinator delete: `beginLayout()`, `ensureLayout(through:)`, `endLayoutInterval()`, `layoutTask`, `layoutInterval`, `layoutSlice`, `laidOutEnd`, `laidOutThrough`, `restorePlace(fallback:)`, `tracker` and every use, the hit-test branch in `reportVisibleAnchor()`, and the clamp in `scrollContainerTopTo` that reads `laidOutEnd` (delete `scrollContainerTopTo` if nothing else calls it). The `deinit` that ends the layout interval goes with them.
- `ReaderScroller` is always installed; `holdsContentSize` is always on.
- `grep -rn "ReadingPlaceTracker\|laidOutEnd\|laidOutThrough\|beginLayout\|ReaderViewportLayout" App Packages` finds nothing.

- [ ] **Step 2: Delete the tracker and its tests**

```bash
git rm Packages/RFCReaderKit/Sources/RFCReaderKit/Navigation/ReadingPlaceTracker.swift \
  Packages/RFCReaderKit/Tests/RFCReaderKitTests/Navigation/ReadingPlaceTrackerTests.swift
```

- [ ] **Step 3: Record the decision**

In `docs/ARCHITECTURE.md`:
- Add a section `## Decision: the reader lays out its viewport, and holds the reader's line` (dated 30 September 2026), summarizing the spec's "Why", the probe table, the engine's four parts, and that it replaces the whole-document layout recorded under #9. Link the spec.
- In the "Known gaps" list, replace the bullet that begins "The reader still lays out the whole document body" with one line pointing at the new decision.
- In "The TextKit 2 traps": in the paragraph beginning "A text container that tracks the text view's width", delete from "That one still does, until its rebuild lands" to the end of the paragraph, and add a paragraph: `relocateViewport(to:)` put its target at y = 0 or collapsed the viewport after a prior relocation (1/40 exact in the probe), and a point lookup after a relocation can return a stale fragment; the pin recipe lays out the target's paragraph and reads the viewport's own fragments instead.
- In `CLAUDE.md`'s standing constraints, nothing changes.

- [ ] **Step 4: Gate**

Run: `make fmt && make check && make build-app && make ios-sim`
Expected: all pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "The reader no longer lays out the whole document: the engine is the only path

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Benchmarks for a jump, a resize step and a slice

**Files:**
- Modify: `Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift`

- [ ] **Step 1: Add the benchmarks**

At the end of the `benchmarks` closure:

```swift
  // The reader's layout engine (see docs/ARCHITECTURE.md, the viewport-layout
  // decision): a jump to the last section, one resize step with the line held, and
  // one background slice, on the largest RFCs. The probe's baseline: a jump 2–6 ms,
  // a resize step 2.4–5.8 ms median, a 6,000-character slice about 3–5 ms.
  for number in [9000] {
    Benchmark("Layout: jump to the last section, RFC \(number)") { benchmark, input in
      for _ in benchmark.scaledIterations {
        let (layout, surface, target) = input.fresh()
        blackHole(PinRecipe.pin(ReaderAnchor(characterOffset: target), in: layout, on: surface))
      }
    } setup: {
      await LayoutInput(data: corpus.data("rfc\(number).xml"))
    }

    Benchmark("Layout: resize step, RFC \(number)") { benchmark, input in
      let (layout, surface, target) = input.fresh()
      PinRecipe.pin(ReaderAnchor(characterOffset: target / 2), in: layout, on: surface)
      var width: CGFloat = 712
      for _ in benchmark.scaledIterations {
        width = width > 320 ? width - 8 : 712
        layout.textContainer?.size = CGSize(width: width, height: 10_000_000)
        blackHole(PinRecipe.pin(ReaderAnchor(characterOffset: target / 2), in: layout, on: surface))
      }
    } setup: {
      await LayoutInput(data: corpus.data("rfc\(number).xml"))
    }

    Benchmark("Layout: one background slice, RFC \(number)") { benchmark, input in
      let (layout, _, _) = input.fresh()
      var planner = SlicePlanner(length: input.built.text.length)
      for _ in benchmark.scaledIterations {
        if planner.isComplete { planner.restart() }
        guard let slice = planner.nextSlice(),
          let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
        else { continue }
        layout.ensureLayout(for: range)
      }
    } setup: {
      await LayoutInput(data: corpus.data("rfc\(number).xml"))
    }
  }
```

and after the closure, the helpers:

```swift
/// A built RFC laid out headless, as the benchmarks' input. `fresh()` answers a new
/// layout each time, so a jump is measured from an un-laid-out document.
@MainActor
final class LayoutInput {
  let built: BuiltDocument
  private var keep: [AnyObject] = []

  init(data: Data) throws {
    built = DocumentTextBuilder.build(try RFCXMLParser.parse(data), style: ReadingStyle(measure: 712))
  }

  func fresh() -> (NSTextLayoutManager, BenchmarkSurface, Int) {
    let storage = NSTextContentStorage()
    storage.install(built.text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    layout.textContainer = NSTextContainer(size: CGSize(width: 712, height: 10_000_000))
    keep = [storage]
    return (layout, BenchmarkSurface(layout: layout), built.anchors.sections.entries.last?.offset ?? 0)
  }
}

/// The benchmarks' scroll view: a top, and a viewport that lays out what it covers.
@MainActor
final class BenchmarkSurface: PinSurface {
  let layout: NSTextLayoutManager
  var containerTop: CGFloat = 0

  init(layout: NSTextLayoutManager) { self.layout = layout }

  func scroll(toContainerY target: CGFloat) { containerTop = max(0, target) }

  func layOutViewport() {
    let top = containerTop
    guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
    layout.enumerateTextLayoutFragments(from: first.rangeInElement.location, options: [.ensuresLayout]) {
      $0.layoutFragmentFrame.minY < top + 900
    }
  }
}
```

Add `import AppKit` at the top of the file. If package-benchmark's closures are not main-actor, wrap each benchmark body in `MainActor.assumeIsolated { … }` — the benchmark runner runs on the main thread.

- [ ] **Step 2: Run them**

Run: `make benchmark BENCHMARK_ARGS='--filter "Layout.*"'`
Expected: the jump's and the resize step's medians within 2–10 ms, and a slice's within 2–8 ms, on this machine; record the numbers in the commit message.

- [ ] **Step 3: Commit**

```bash
git add Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift
git commit -m "Benchmarks pin the cost of a jump, a resize step and a slice under viewport layout

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Handover

Open a pull request against `main` from `fix/resize-reading-position` titled "The reader lays out its viewport and holds the reader's line", closing #546, #295 and #322, with the spec and this plan linked, the probe table, and the hand checks from Tasks 7, 9, 10, 11 and 12 as a checklist. Before pushing, check the PR is still open (if one exists) and push with `git push origin fix/resize-reading-position`.
