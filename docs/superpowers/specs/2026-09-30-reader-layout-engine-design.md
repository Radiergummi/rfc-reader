# The reader's layout engine — design

*30 September 2026. Approved in brainstorming, section by section, after a measured probe;
implementation plan to follow. Replaces the "whole document laid out" decision recorded with
#9. Fixes #546, #295 and #322.*

## Why

Resizing a window is the most ordinary thing a reader does, and today it is the worst thing
this one does. During a live drag the text does not reflow; the title in the header does. When
the width settles for 650 ms the document is rebuilt and reflows at once. In between, the old
storage is re-wrapped at the new width under a scroll offset that has not moved, so text from
elsewhere in the document slides under the viewport, and the rebuild then scrolls back to the
reader's line (#546). The place is never actually lost — a log of a real drag showed eight
rebuilds restoring `section-4.4-8`, 186 characters in, each exactly — but a reader cannot tell
the difference, and cannot test anything that sits in the text while it jumps.

The cause is a decision, not a TextKit limit. The reader lays out every fragment of the
document (`RFCTextViewCoordinator.install`), so that an anchor's y is exact and the scroller
steady. Every change of width throws that layout away, and redoing it costs about 0.6 s on
RFC 5661 (#9's probe B), which is where the 650 ms debounce and everything above come from.
TextKit 2 is built for the other way: lay out the viewport, estimate the rest. Notes reflows a
very large document live because it pays for a screenful per change, not for the document.

The same decision costs elsewhere: a deep jump lays out everything above its target first, about
540 ms on RFC 5661 (#295), and a restored reading position lands on its section's heading rather
than its line (#322).

The bar, as the maintainer set it: reflow on resize is core functionality, and it has to be
natural, real time and snappy on any RFC, the largest included.

## Scope

This is the first of four projects:

1. **The layout engine** — this spec. Viewport layout, the reader's line held through every
   change of geometry, background completion, and a scroll height of our own.
2. **Column-dependent blocks at layout time** — artwork scale and RFC 8792 unfolding, table
   shape and tab stops, list marker widths, and on the artwork branch the centering indent, all
   decided from the live column instead of at build time. Its own spec.
3. **Live restyle** — a change of text size applied to the storage in place rather than through
   a rebuild. Its own spec.
4. **Side panels** — stop refusing the inspector's and the contents panel's width once
   re-wrapping is cheap and holds the line. A bounded change after project 2, no spec.

Project 1 ships alone and is worth having alone. Until project 2 lands, a change of column still
rebuilds the storage, because artwork and tables are shaped by the column at build time; the
engine pins the reader's line through that rebuild as through anything else, so nothing jumps.
Prose re-wraps live from project 1 on; artwork and tables adapt when the rebuild lands, which is
now a viewport's worth of layout rather than a document's.

Standing constraints kept throughout: one text storage per document; nothing in the body
becomes an attachment or a hosted view; selection, find and VoiceOver run through the whole
document; anchors are stable strings; print keeps its own off-screen build and full layout.

## The probe

Measured before anything was designed, with a throwaway program (not committed) that installs
the real `DocumentTextBuilder` output in an `NSTextView` with viewport-only layout. Apple M3 Pro,
macOS 27, release build, load average under 4; two runs each.

| | RFC 9000 (348 K characters) | RFC 5661 (1.3 M characters) |
|---|---|---|
| Open: install and lay out the first viewport | 5–15 ms | 7–16 ms |
| Jump to a random section, 40 in a row | 40/40 exact; median 2.2–2.4 ms, max 6 ms | 40/40 exact; median 2.5–2.6 ms, max 6 ms |
| One resize step, 712 → 300 → 712 pt in 3 pt steps: layout | median 2.8–5.8 ms, p95 5.2–8.6, max 8–15 | median 2.4 ms, p95 5.0–5.8, max 10 |
| One resize step: draw the visible rect | median 2.0–2.3 ms, p95 3.0 | median 1.4 ms, p95 1.9 |
| Line at the top held through the resize | 276/276 steps | 276/276 steps |
| Background layout at a new column, per 20 K characters | median 10–16 ms, p95 12–33 | median 10 ms, p95 14–16 |
| The same, whole document, line held after every slice | 183–311 ms | 707–720 ms |
| Document height: TextKit's first estimate | −14.7% | −8.5% |
| Document height: a crude per-paragraph character model | +5.3% | +5.8% |
| While scrolling top to bottom, TextKit's height changed by up to | 20.5% in one screen | 98–122% in one screen |

What it established:

- **Viewport layout is fast enough.** A resize step is 4–8 ms of layout and drawing typically,
  7–11 ms at p95: inside a 60 Hz frame with room, and mostly inside 120 Hz.
- **Holding the line works, with the right recipe.** Lay out only the target's paragraph
  (`NSTextLayoutManager.ensureLayout(for:)` over its range), scroll so the target's own
  fragment frame meets the viewport's top, lay out the viewport, and settle once more if the
  estimates above moved. One or two passes, exact every time.
- **`relocateViewport(to:)` does not work for this.** From a prior relocation it put the target
  at y = 0 or collapsed the viewport range (1/40 exact); its suggested anchor point was off by
  300 to 25,000 characters; `adjustViewport(byVerticalOffset:)` after it reached 28–38/40. The
  engine does not use it.
- **TextKit's height estimate cannot drive a scroller.** It is off by 8–15% at first and swings
  by up to the whole document's height in one screen of scrolling, which is #9's fear, measured.
  A per-paragraph model of our own starts within 6% even in its crudest form.
- **A point lookup is not a way to ask what is at the top.** `textLayoutFragment(for: CGPoint)`
  returned a stale fragment after a relocation; the viewport's own fragments, enumerated from
  `viewportRange`, are the truth.
- **Slices must be smaller than today's.** 20 K characters is 10–16 ms, a frame at 60 Hz; the
  engine's slices are 5–8 K, about 3–5 ms.

## Design

### The engine

One owner for the reader's geometry, `ReaderLayoutEngine`, driven by `RFCTextViewCoordinator`,
with every piece of arithmetic in `RFCReaderKit` where a test can reach it. It has four
responsibilities:

1. **Viewport layout.** Nothing is laid out up front beyond what is visible. `install` puts the
   storage in and lays out the first viewport; the whole-document layout, its first 20 K slice
   and `laidOutEnd` go.
2. **The anchor** — the reader's place, held through every change of geometry by one mechanism.
3. **Background completion** — idle-time slices that make the geometry exact after a change.
4. **The scroll height** — a model of our own that drives the scroller.

### The anchor

**What it is.** The character that starts the line at the top of the viewport, and how far into
that line the viewport's top is, as a fraction of the line's height. A line, not a paragraph:
after a re-wrap, the character that was at the top is at the top, not the first line of its
paragraph. Carried across a new storage — a rebuild for a new column or text size, until
projects 2 and 3 remove them — as a `ReadingPlace` (the nearest anchor of any kind, plus a
character distance), which already survives a rebuild. Scrolled above the text, where the header
is, it is `.top`, as today, and a document read from the very top stays there through any
resize.

**Only the reader moves it.**

- A scroll the reader makes re-reads the anchor from the viewport's own fragments.
- A move the engine makes — a pin, a slice, a correction of the height — runs inside an engine
  transaction, and the scroll notifications it causes do not touch the anchor. This replaces
  `ReadingPlaceTracker`'s pausing and resuming with one rule: the engine never records its own
  moves.
- A jump sets the anchor to its target, as `scroll(to:)` sets the place today.

**How it is pinned.** Every change of geometry ends in exactly one pin: a resize step, a
rotation, a split view, the measure preference, a side panel, a rebuild installing, a slice
landing, a correction of the height. The recipe, from the probe:

1. Lay out the anchor's paragraph: `ensureLayout(for:)` over its range.
2. Find the line fragment holding the anchor's character, and its top within the paragraph.
3. Scroll so that the line's top, plus the fraction of its height, meets the viewport's top.
4. Lay out the viewport. If the target's frame moved — estimates above it were replaced — scroll
   by the difference and lay out again. At most a handful of passes; the probe needed two.

**Where it lives.** The line lookup, the fraction and the settle rule are pure functions in
`RFCReaderKit`, beside `FragmentGeometry.topLine`: given a paragraph's line fragments and a
character, where does the viewport's top go. The recipe itself is an `RFCReaderKit` function
over two small protocols — a layout side, which a real `NSTextLayoutManager` satisfies, and a
scroll side — so it is tested against real TextKit layout with a fake scroll view. The App
target keeps the adapters: the calls into the text view and the scroll itself, on AppKit and
UIKit.

**What reads it.** Section tracking, the running heading and the toolbar title read the anchor
instead of hit-testing the top themselves. The saved reading position becomes the anchor, so a
restored position lands on its line (#322).

### The scroll height

**The scroller is ours; the content position stays TextKit's.** The clip view (and on iOS the
scroll view's content offset) scrolls in TextKit's own coordinates, so layout, hit-testing and
pinning are untouched. Only the scroller reads the model:

- **macOS:** a custom `NSScroller` subclass on the reader's `NSScrollView` whose knob position
  and proportion come from the model, not from the document view's frame. Overlay style,
  click-in-track paging and the scroll bar's accessibility value behave as the stock scroller's.
- **iOS:** the scroll view's content height and indicator follow the model; the content offset is
  corrected in the same transaction whenever the height above the viewport changes, so the
  change is invisible.

Dragging the knob is a jump: the knob's fraction → the height in the model → the character at
that height → the pin recipe. A drag to the bottom lands exactly at the end.

**The model**, pure and tested in `RFCReaderKit`:

- At build time, `DocumentTextBuilder` records each paragraph's natural width on one line, its
  line height and its spacing — measurements it already makes.
- At any column, a paragraph's estimated height is a few arithmetic operations, and the
  document's is one pass over the paragraph list: about 30 K paragraphs on RFC 5661, well under a
  millisecond.
- A paragraph TextKit has laid out replaces its estimate with its real height, so the model
  starts close and converges to exact as layout completes.

**Smoothing, so the knob never jumps under the reader.** While the reader drags the knob or a
scroll is tracking or decelerating, the model's total is frozen. When it settles, a changed
total eases the knob to its new place over about 150 ms. A change of column recomputes the total
at once: everything is moving then, and the reader is watching it move.

### Background completion

After any change of geometry, and after opening a document, idle-time slices lay the document out
at the current column, from its start: TextKit's positions are exact only once everything above
them is laid out. Slices are 5–8 K characters, about 3–5 ms. They pause while a live resize, a
scroll or a knob drag is in progress, and each ends in one pin. When the last lands, the
geometry is exact and the model equals the truth: about 0.7 s of spare time on RFC 5661, spread
over frames. A document read without a change of width is laid out once, as today; a resize
lays it out once more, after the drag ends.

### What depends on the whole document being laid out today

| Consumer | Today | Under the engine |
|---|---|---|
| Jumps, deep links, the contents panel, links within the document | `ensureLayout` of everything above the target (#295) | The pin recipe: one paragraph, 2–6 ms |
| The restored reading position | A section, restored to its heading (#322) | The anchor, restored to its line |
| Section tracking, the running heading, the toolbar title | Hit-test the top of the viewport; paused around a rebuild | Read the anchor |
| Find (the macOS find bar, iOS's find interaction) | AppKit and UIKit scroll a match into view on laid-out geometry | `ReaderTextView` overrides `scrollRangeToVisible` and routes it through the pin recipe |
| VoiceOver's rotors (headings, links, diagrams) | Frames from the full layout | A frame asked for when the item is, after the recipe lays out its paragraph |
| Selection, drag-select, Select All, copy | — | Unchanged: copy reads the storage; TextKit scrolls a drag |
| Hover and force-click previews, backlinks, figure controls | Fragments on screen | Unchanged |
| The iPhone's bars following a scroll | The content height from the frame | The content height from the model |
| Print and export | Their own layout manager, laid out in full | Unchanged: paper needs exact pagination |

### What goes away

- Laying out the whole document on install and on every change of column.
- `laidOutEnd`, `laidOutThrough` and the clamping that reads them in `scrollContainerTopTo`.
- `ReadingPlaceTracker`'s pause-and-resume logic; the value types it records stay.
- The 650 ms debounce for a change of width, once project 2 means a width no longer rebuilds.
  Until then it stays for the rebuild, and the pin makes it invisible.

## Testing

Nothing testable lives in the App target; the design is shaped by that.

- **Pure tests in `RFCReaderKit`:** the height model (estimate, refinement, convergence, the total
  at a column, the character at a height), the anchor's line arithmetic, the slice planner and
  the smoothing rule.
- **The pin recipe against real TextKit.** The recipe runs over its two protocols in a test, with a
  real `NSTextLayoutManager` laying out a committed fixture and a fake scroll side. The probe's two
  headline results become regression tests: a jump lands exactly from any prior state, and a
  resize from 712 to 300 pt and back holds the line in every step.
- **A benchmark in `Tools/benchmarks`** for a jump, a resize step and a slice on the largest RFCs,
  with the probe's numbers as the baseline, so `make benchmark` catches a regression.
- **By hand, with the maintainer:** a live drag on macOS, wide and narrow; rotation and split view
  on iOS; opening each side panel; find far down a long RFC; the VoiceOver rotors; the custom
  scroller beside a stock one.

## Risks

- **The probe ran headless, on macOS.** A real `NSTextView` in a window, and `UITextView` on iOS,
  may schedule viewport layout differently. The first implementation step is the pin recipe
  behind a flag, checked on both platforms in the running app before anything is removed.
- **A custom scroller has to feel native.** Overlay style, the knob's appearance, click-in-track
  paging and the accessibility value are checked by hand against a stock scroller in the first
  build that has it.
- **iOS has no scroller to replace.** Keeping the content height on the model and correcting the
  offset in the same transaction is the plan; if the indicator still visibly jumps on a device,
  the fallback is to keep the content height fixed until background completion ends.
- **This reverses a recorded decision.** `docs/ARCHITECTURE.md` gets a dated decision replacing
  #9's, with the probe's numbers. "The TextKit 2 traps" loses its paragraph about the tracker
  pausing for a rebuild once that no longer happens, and gains one about `relocateViewport(to:)`
  and point lookups after a relocation.
