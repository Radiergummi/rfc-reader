# The reader's layout engine — design

*30 September 2026. Approved in brainstorming, section by section, after a measured probe;
implementation plan to follow. Replaces the "whole document laid out" decision recorded with
#9. Fixes #546 and #322.*

*Revised 1 October 2026, after the first builds ran on an iPhone and a Mac: the scroll height of
our own and jumping without laying out what is above the target are gone, for the reasons in
"What the devices showed". A deep jump before the document is laid out costs what it does on
the old path, so #295 is not fixed here. "Design" and everything after it describe the engine
as it now is.*

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
   change of geometry, and background completion. (As first written, also a scroll height of
   our own; see "What the devices showed".)
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

## What the devices showed

*1 October 2026. Measured in the running app on an iPhone 15 Pro and on the MacBook Pro (M3 Pro)
of the probe, debug builds unless said otherwise, RFC 5661 throughout. A probe build stepped the
reader through the document by itself and logged TextKit's geometry against the engine's; none
of it is committed. The first design was built through the plan's Task 12 before this was
known.*

**TextKit drops the layout of the whole document on its own.** Scrolling back up RFC 5661, at
the same place every run, one fragment came back 100 pt taller and every fragment in the
document went back to estimated heights: the document's height fell from 836,956 to 739,555 pt.
Nothing asked for it — no `invalidateLayout(for:)` over a large range was called — the container's
width, the insets and the text size were unchanged, and it happened the same with TextKit's
plain `NSTextLayoutFragment` in place of ours, and on the old path without the engine.
TextKit's positions are therefore never reliably exact for long, even after the whole document
was laid out.

**After a far jump there are two sets of coordinates.** A jump that lays out only its target's
paragraph leaves the viewport where TextKit estimated it — around y = 393,000 for a line in the
middle of RFC 5661 — while the layout from the document's start puts the same line at 441,201.
Neither gives way to the other:

| What completion did when it reached the viewport | What the iPhone showed |
|---|---|
| Nothing | The text 73,000 characters earlier, at the same scroll offset: the offset never moved |
| Pinned the line after every slice | The line wandered by about 300 characters a slice; each pin took about 0.4 s, and completion ran ten times slower |
| Pinned once, when it reached the viewport | Right for 0.4 s, then 73,000 characters off again |
| Scrolled by the distance the line moved | 83,000 characters off: the viewport laid out its own coordinates again |

The old path never had this, because its jumps lay out everything above the target first; then
there is one set of coordinates, and the scroll view keeps the text in place by itself as the rest
is laid out. With that settle in place, the same jump took 264 ms and the line did not move by a
character while completion laid out the rest.

**Laying out from the start costs this much.** After the layout was thrown away, laying out from
the document's start to a point:

| To | iPhone 15 Pro | Mac |
|---|---|---|
| 10% (130 K characters) | 73 ms | 49 ms |
| 25% | 199 ms | 148 ms |
| 50% | 352 ms | 258 ms |
| 75% | 516 ms | 395 ms |
| 100% (1.3 M characters) | 705 ms | 545 ms |

A release build on the iPhone measured the same to the millisecond: the time is TextKit's. A
typical RFC is a tenth of RFC 5661's length or less.

**A scroll height of our own cannot follow those coordinates.** It was built as specified — a
height model from the builder's per-paragraph measurements, a macOS `NSScroller` subclass placing
its knob from it, and on iOS a content size TextKit reported while the reader touched or flung
held back and applied when they stopped. On the device:

- The held content size was the cause of most of the iPhone's failures: an invisible bottom in
  the middle of the text wherever TextKit's estimate was short, and a stale height of 0, held
  through a change of document, applied later and throwing the reader to the top.
- A content height from the model instead (TextKit's place for the top, plus the model's height
  below it) put the end where the text ends going down, but fought UIKit's own correction of the
  offset going back up, by about 68,000 pt each way.
- The model's estimates before measurement overshot by about a third at the iPhone's 345 pt
  column (a paragraph estimated at 240 pt laid out at 177 pt), against the probe's 6% at 712 pt.
- The maintainer wants the platforms' own scrollers, including hiding them as the system setting
  says, not a knob placed by us. With TextKit's own height, the iPhone's indicator still moves
  while it estimates during a fast fling or a drag of the indicator; it did the same on the old
  path.

**The pin had two more ways to send the reader to the top.** After TextKit dropped its layout,
the anchor's fragment could come back with a zero frame, and the pin scrolled to its y of 0; and
the viewport range could start past the top for one pass, so that reading the place from it
took a line 150,000 characters away. Both are guarded in `PinRecipe` now, with a test for the
second.

**A forced viewport layout during a live resize is what made it slow.** Pinning on estimates in
every step of a drag is cheap, but laying the viewport out after the pin made `NSTextView` lay out
a large range of the document itself, from `textViewportLayoutControllerDidLayout:` through
`ensureLayoutForRange:` (sampled): 500–630 ms per step. Without it a step took under 1 ms, and the
line held through the drag and after it. Settling when the resize ended was also wasted: the
rebuild for the new column, which follows every change of column, settles again a moment later,
and doing both cost about 450 ms twice.

**A fling's corrections looked like the reader turning.** As TextKit corrects its estimates during
a fast fling, UIKit moves the offset against the fling to keep the text in place, and a
correction of 44 pt or more hid the iPhone's bars, which the next frames showed again.

## Design

### The engine

One owner for the reader's geometry, `ReaderLayoutEngine`, driven by `RFCTextViewCoordinator`,
with every piece of arithmetic in `RFCReaderKit` where a test can reach it. It has three
responsibilities:

1. **Viewport layout.** `install` puts the storage in and lays out no more than it has to; the
   whole-document layout of the old path, its first 20 K slice and `laidOutEnd` go.
2. **The anchor** — the reader's place, held through every change of geometry.
3. **Background completion** — idle-time slices that lay the rest of the document out, so the
   scroller's height is exact.

The scrollers are the platforms' own: the text view's frame, and on iOS its content size, are
TextKit's, and nothing places a knob.

### The anchor

**What it is.** The character that starts the line at the top of the viewport, and how far into
that line the viewport's top is, as a fraction of the line's height. A line, not a paragraph:
after a re-wrap, the character that was at the top is at the top, not the first line of its
paragraph. Carried across a new storage — a rebuild for a new column or text size, until
projects 2 and 3 remove them — as a `ReadingPlace` (the nearest anchor of any kind, plus a
character distance), which already survives a rebuild. Scrolled above the text, where the header
is, it is `.top`, and a document read from the very top stays there through any resize.

**Only the reader moves it.**

- A scroll the reader makes re-reads the anchor from the viewport's own fragments.
- A move the engine makes runs inside an engine transaction, and the scroll notifications it
  causes do not touch the anchor. This replaces `ReadingPlaceTracker`'s pausing and resuming
  with one rule: the engine never records its own moves.
- A jump sets the anchor to its target.

**How it is put back: settled.** A jump, a document installing (a rebuild included) and a change
of column settle the anchor (`PinRecipe.settle`):

1. Lay out the document from its start through the anchor's paragraph.
2. Pin: find the line fragment holding the anchor's character, scroll so that the line's top, plus
   the fraction of its height, meets the viewport's top, lay out the viewport, and settle once
   more if the line moved. At most a handful of passes.

The line is then where the layout of the whole document puts it, so there is one set of
coordinates, and the scroll view keeps the line in place by itself while completion lays out the
rest: nothing in completion moves what the reader is looking at. Laying out from the start costs
what is measured above — up to 0.35 s for the middle of RFC 5661 on an iPhone — but once
completion has passed the place it costs nothing, because what is above is laid out already.

**During a live resize on the Mac: pinned on estimates.** A live resize cannot afford the layout
from the start on every step, so each change of column only pins, on TextKit's estimates, and the
viewport is left to AppKit's own display pass. The rebuild for the new column, which follows the
resize, settles. A change of gutter or header that moves the container without re-wrapping
anything also only pins.

**Where it lives.** The line lookup, the fraction and the settle rule are pure functions in
`RFCReaderKit` (`LinePin`). The recipe is an `RFCReaderKit` function over a small protocol for
the scroll side (`PinSurface`), tested against real TextKit layout with a fake scroll view. The
App target keeps the adapters: the calls into the text view and the scroll itself.

**What reads it.** Section tracking, the running heading and the toolbar title read the anchor
instead of hit-testing the top themselves. The saved reading position is the anchor, so a
restored position lands on its line (#322).

### Background completion

After opening a document and after any change of geometry, idle-time slices lay the document out
at the current column from its start, 6,000 characters at a time, a few milliseconds each. They
move nothing on screen, pin nothing, and do not pause for the reader's scrolling, as the old
path's background layout did not; they pause only through a live resize, whose every step
re-wraps them. When the last lands, TextKit's height is exact. When TextKit later drops the
layout, nothing is done: what is above the reader is laid out, so the drop moves nothing they are
looking at, and the scroller's height is an estimate again until the reader causes a settle.

### What depends on the whole document being laid out today

| Consumer | The old path | Under the engine |
|---|---|---|
| Jumps, deep links, the contents panel, links within the document | `ensureLayout` of everything above the target (#295) | The same, through `PinRecipe.settle`: free once completion has passed the target |
| The restored reading position | A section, restored to its heading (#322) | The anchor, restored to its line |
| Section tracking, the running heading, the toolbar title | Hit-test the top of the viewport; paused around a rebuild | Read the anchor |
| Find (the macOS find bar, iOS's find interaction) | AppKit and UIKit scroll a match into view on laid-out geometry | `ReaderTextView` overrides `scrollRangeToVisible`; a match outside the viewport is a jump |
| VoiceOver's rotors (headings, links, diagrams) | Frames from the full layout | A stop is handed to the system as a range, which it scrolls into view; the last heading of RFC 5661 landed on screen, checked by hand |
| Selection, drag-select, Select All, copy | — | Unchanged: copy reads the storage; TextKit scrolls a drag |
| Hover and force-click previews, backlinks, figure controls | Fragments on screen | Unchanged |
| The iPhone's bars following a scroll | The content height from the frame | Unchanged, and a fling's own corrections are ignored |
| The scrollers | The platforms' own | The platforms' own |
| Print and export | Their own layout manager, laid out in full | Unchanged: paper needs exact pagination |

### What goes away

- Laying out the whole document on install and on every change of column.
- `laidOutEnd`, `laidOutThrough` and the clamping that reads them in `scrollContainerTopTo`.
- `ReadingPlaceTracker`'s pause-and-resume logic; the value types it records stay.
- The 650 ms debounce for a change of width, once project 2 means a width no longer rebuilds.
  Until then it stays for the rebuild, and the pins in between hold the line.

## Testing

Nothing testable lives in the App target; the design is shaped by that.

- **Pure tests in `RFCReaderKit`:** the anchor's line arithmetic (`LinePin`), the place keeper
  (`AnchorKeeper`), the slice planner, and the bars ignoring a fling's corrections
  (`ReaderChrome`).
- **The pin recipe against real TextKit.** The recipe runs over its protocol in a test, with a real
  `NSTextLayoutManager` laying out a committed fixture and a fake scroll side: a jump lands
  exactly from any prior state, a resize from 712 to 120 pt and back holds the line in every
  step, a settled line is where the whole document's layout puts it (a plain pin fails this), and
  a lookup that starts past the top finds nothing.
- **A benchmark in `Tools/benchmarks`** for a settled jump, a resize step and a slice on the largest
  RFCs, so `make benchmark` catches a regression.
- **By hand, with the maintainer:** a live drag on macOS, wide and narrow; rotation and split view
  on iOS; flinging and dragging the indicator on an iPhone; opening each side panel; find far down
  a long RFC; the VoiceOver rotors.

## Risks

- **A deep jump before completion freezes for as long as the layout above it takes:** up to 0.7 s
  at the end of RFC 5661 on an iPhone, as on the old path. A rotation in the middle of it, about
  0.35 s, was hardly noticeable to the maintainer.
- **The rebuild after a resize settles, about 0.35–0.6 s on RFC 5661 on a Mac,** felt as a short
  freeze when the drag ends; a typical RFC is a tenth of that.
- **TextKit drops its layout when it chooses.** The engine relies on it not moving what is above
  the reader when it does, which the iPhone showed; the scroller's height is an estimate again
  afterwards, as on the old path.
- **This reverses a recorded decision.** `docs/ARCHITECTURE.md` gets a dated decision replacing
  #9's, with the probe's numbers and these. "The TextKit 2 traps" loses its paragraph about the
  tracker pausing for a rebuild once that no longer happens, and gains ones about
  `relocateViewport(to:)` and point lookups after a relocation, about TextKit dropping its
  layout, about the two sets of coordinates after a jump that did not lay out what is above it,
  and about a forced viewport layout during a live resize.
