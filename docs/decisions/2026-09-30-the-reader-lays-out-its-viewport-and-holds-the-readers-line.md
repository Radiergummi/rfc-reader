# The reader lays out its viewport, and holds the reader's line

*Decided 30 September 2026, revised 1 October 2026 after the first builds ran on an iPhone 15 Pro and a Mac (issues #546 and #322). Replaces the whole-document layout recorded under #9. The design, the probe and the device measurements in full: `docs/superpowers/specs/2026-09-30-reader-layout-engine-design.md`.*

Resizing a window was the worst thing the reader did. It laid out every fragment of the document so that an anchor's y was exact, every change of width threw that layout away, and redoing it cost about 0.6 s on RFC 5661 — hence a 650 ms debounce, text that did not reflow during a drag, and text from elsewhere sliding under an unmoved scroll offset until the rebuild scrolled back (#546). The same decision restored a reading position to its section's heading rather than its line (#322). TextKit 2 is built for the other way: lay out the viewport, estimate the rest.

A throwaway probe (not committed) installed the real `DocumentTextBuilder` output in an `NSTextView` with viewport-only layout; Apple M3 Pro, macOS 27, release build:

| | RFC 9000 (348 K characters) | RFC 5661 (1.3 M characters) |
|---|---|---|
| Open: install and lay out the first viewport | 5–15 ms | 7–16 ms |
| One resize step, 712 → 300 → 712 pt: layout | median 2.8–5.8 ms, p95 5.2–8.6 | median 2.4 ms, p95 5.0–5.8 |
| One resize step: draw the visible rect | median 2.0–2.3 ms | median 1.4 ms |
| Line at the top held through the resize | 276/276 steps | 276/276 steps |
| Background layout, per 20 K characters | median 10–16 ms | median 10 ms |
| Document height: TextKit's first estimate | −14.7% | −8.5% |
| While scrolling, TextKit's height changed by up to | 20.5% in one screen | 98–122% in one screen |

The devices then showed what the probe could not. **TextKit drops the layout of the whole document on its own**: scrolling back up RFC 5661 on an iPhone, at the same place every run, every fragment went back to estimated heights and the document's height fell from 836,956 to 739,555 pt, with nothing asking for it — on the old path too. **A jump that lays out only its target leaves two sets of coordinates**: the viewport where TextKit estimated it (around y = 393,000 for a line in the middle of RFC 5661) and the layout from the document's start, which puts the same line at 441,201; neither gives way, and every way of reconciling them as background layout reached the viewport left the reader up to 83,000 characters off. **Laying out from the start costs** 352 ms to the middle of RFC 5661 on the iPhone and 258 ms on the Mac, 705 and 545 ms to the end; a typical RFC is a tenth of that or less. And **a scroll height of our own could not follow TextKit's coordinates**: a held-back content size on iOS put an invisible bottom in the middle of the text, a modeled height fought UIKit's correction of the offset by about 68,000 pt, and the maintainer wants the platforms' own scrollers anyway.

So the engine, `ReaderLayoutEngine` in the app over pure types in `RFCReaderKit/Layout`, has three parts:

1. **Viewport layout.** `install` puts the storage in and lays out only what the reader's place needs.
2. **The reader's line** (`ReaderAnchor`, kept by `AnchorKeeper`): the character that starts the line at the top of the viewport and how far into that line the top is. Only the reader moves it — a scroll the engine causes records nothing — and a jump sets it. A jump, a document installing (a rebuild included) and a change of column **settle** it (`PinRecipe.settle`): put the viewport at the document's start, lay out from there through the line's paragraph, then pin the line to the top. The line is then where the whole document's layout puts it, one set of coordinates, and the scroll view keeps it in place while the rest arrives. Only a live resize on the Mac pins on estimates, without forcing a viewport layout; the rebuild for the new column that follows settles. A change of gutter or header that re-wraps nothing also only pins.
3. **Background completion**: 6,000-character slices from the document's start in idle time (`SlicePlanner`), which move nothing and pin nothing. When TextKit later drops its layout, nothing is done: what is above the reader is laid out, so nothing they are looking at moves.

The scrollers are the platforms' own. What it costs: a deep jump before completion has passed its target freezes for as long as the layout above it takes, as on the old path (#295 stays open), and the rebuild after a resize on the Mac settles in about 0.35–0.6 s on RFC 5661. Print and export keep their own full layout. Each of these was measured to fail on a device and is not to come back: pins after completion slices; a scroll height or knob of our own, or holding back iOS's content size; jumping without laying out what is above the target; forcing a viewport layout during a live resize; settling at the end of a live resize; restarting completion when TextKit drops its layout.
