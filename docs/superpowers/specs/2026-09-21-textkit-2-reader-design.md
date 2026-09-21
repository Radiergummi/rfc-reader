# TextKit 2 reader body — design

*21 September 2026. Approved in brainstorming; implementation plan to follow.*

## Why

The reader currently renders a `LazyVStack` of `SectionView`s, each mapping the document's
blocks through `BlockView`, with `InlineText` producing one `AttributedString` per paragraph.
It works, and three things it cannot do are things the reader needs:

- **Selection stops at every block.** Each paragraph is its own `Text`. Selecting from one
  paragraph, through a diagram, into the next is impossible.
- **Links carry no context menu or preview.** SwiftUI `Text` handles a link tap and nothing
  else — no long-press preview on iOS, no hover popover on Mac.
- **Cross references cannot be styled as objects.** `AttributedString` offers a hard square
  `backgroundColor` with no padding or corner radius, so a reference cannot become a chip.

`ARCHITECTURE.md` recorded the decision to move the reader body to TextKit 2 in September 2026
and called it the first app task after the Xcode project builds. The project now builds. This
document settles *how*.

## Requirements

Must work when this lands:

1. Selection flows continuously through the document, including across artwork, tables and
   figures, and copying such a selection produces the artwork's text.
2. Cross references offer a preview: long-press on iOS, hover on macOS.
3. Cross references render as chips — a leading `doc.text` symbol and a tinted rounded
   background — with the square brackets dropped.

Explicitly **not** in scope:

- **Find in document.** Considered and deliberately excluded from this milestone. The chosen
  architecture makes it cheap later — one text storage, `UIFindInteraction` on iOS and
  `NSTextFinder` on macOS (they are separate APIs; there is no shared one) — which is a
  consequence, not a goal.
- Pagination, Pencil annotation, SVG artwork, syntax highlighting.
- Snapshot tests of rendered output. Deferred until the rendering settles, consistent with
  what `ARCHITECTURE.md` already says about `BlockView`.

## Decision: one text storage, and nothing but text in it

A single `NSTextContentStorage` holds the whole document body. **Every block kind becomes
attributed text — prose, headings, lists, definition lists, references, figures, tables and
artwork alike. There are no `NSTextAttachment`s.**

The rule that produces this:

> Content is text when selection matters. A hosted view is used only where interaction matters
> *more* than selection — and in the reader body, nothing qualifies.

That rule is what the first draft of this document got wrong. It argued that container blocks
must stay text because putting their prose in an attachment would push it outside the storage,
and then put artwork in an attachment two paragraphs later. The argument was right; the
exception was not. An `NSTextAttachmentViewProvider`'s view is a *subview* of the text view, so
a drag crossing it is delivered to that subview and never reaches the selection machinery —
requirement 1 fails exactly the way the hybrid fails, only less visibly. The repair is
disabling hit-testing on the hosted view, which costs the horizontal scroll, the copy button
and the in-artwork selection that `PreformattedView` has today. There is no version of the
attachment approach in which artwork is both interactive and selectable-through.

Once artwork is text, the entire attachment apparatus goes with it: no view-provider lifecycle,
no `attachmentBounds` override, no hosting-controller retention problem, no VoiceOver hole, and
no copy substitution — a selection that crosses a diagram copies the diagram because the
diagram *is* characters in the same storage.

### Alternatives rejected

**Hybrid — TextKit for runs of prose, SwiftUI views between them.** This is what
`ARCHITECTURE.md` sketched, and it is the cheapest option: `PreformattedView` and
`TableBlockView` stay exactly where they are, and link previews and chips both still work. It
fails requirement 1. You cannot select through a SwiftUI view sitting between two text views.
**This design supersedes that paragraph of `ARCHITECTURE.md`**, which must be updated when the
work lands.

**One text storage per section.** Selection crosses blocks within a section but still stops at
artwork and at section boundaries. Fails requirement 1 for more work than the hybrid.

**One storage with attachments for artwork and tables.** The first draft of this document.
Rejected above: attachments are holes in the storage for selection, find and accessibility
alike, and the interactivity that would justify one is precisely what has to be switched off to
make selection work.

### What is outside the storage

One thing: the **document header** — title, status badge, stream, date, working group, authors
and the status banner. It is a single SwiftUI view laid into the text view's top content inset,
so it scrolls with the body but is not part of it. The banner carries buttons and links to
newer RFCs; nobody selects through it. `VISION.md` requires it to sit "between title and
abstract, not in a toolbar", and this satisfies that: the header view ends with the banner, and
the abstract is the first prose in the storage. (Today the banner renders *below* the abstract,
because `DocumentHeaderView` owns the abstract; this move fixes that in passing.)

Also outside, as before: the toolbar and the table-of-contents inspector.

## Architecture

### The builder

The new unit is pure: no view, no state, no I/O.

```
DocumentTextBuilder
  build(document: RFCDocument, style: ReadingStyle) -> BuiltDocument

BuiltDocument
  text:    NSAttributedString                  the whole body, one storage
  anchors: [(anchor: String, offset: Int)]     sorted by offset, every anchor
```

It lives in the **app target, not RFCKit**. RFCKit builds on Linux and knows nothing about
SwiftUI; fonts and metrics belong on the app side. The existing `InlineText.attributedString(_:)`
is the seed of this function — it moves into the builder, and the `InlineText` view is deleted.

### `ReadingStyle` carries no colours

`ReadingStyle` is the presentation input the builder needs: body font size and family, heading
scale, line height and the measure. **Colours are not in it.** The attributed string stores
dynamic `UIColor`/`NSColor` values (`.label`, `.secondaryLabel`, `tintColor`), which resolve at
draw time.

This matters for a reason the first draft missed: a rebuild loses the reader's place, and if
the resolved colour set were part of the style, a rebuild would be triggered by switching to
dark mode or changing the accent colour, not just by the font-size slider. With dynamic
colours, appearance changes cost a redraw and nothing else.

### Custom attributes

| Attribute | Payload | Used by |
|---|---|---|
| `.rfcReference` | `CrossReference` | hit testing, preview, chip drawing |
| `.rfcAnchor` | `String` | anchor index, section tracking |
| `.rfcDecoration` | `.blockQuote` / `.aside` / `.artwork` / `.table` | card and rule drawing by the layout fragment |
| `.rfcVerbatim` | `Preformatted` | "Copy Figure" menu item, accessibility element |

Cross references keep their existing private-scheme `.link` values (`rfc://…`,
`rfc-anchor:…`) so the system draws them and macOS gives a hover cursor. `.rfcReference`
carries the payload the preview and the chip need.

### Artwork as text

`Preformatted.text` goes into the storage verbatim, in a monospaced font, under a paragraph
style with `lineBreakMode = .byClipping` so it never wraps. The card background is drawn by the
same `NSTextLayoutFragment` subclass that draws chips and quote rules.

The one thing text loses against today's `PreformattedView` is the horizontal scroll view, so
the builder **scales the monospace font per block** to fit the widest line into the measure:
`scale = min(1, measure / (widestColumnCount × advanceWidth))`. That this is viable rather than
a fudge is a measured fact, not a guess — over the 8,457-document converted legacy corpus:

| Widest line in the block | Blocks | Cumulative |
|---|---|---|
| ≤ 69 columns | 395,944 | 97.8% |
| ≤ 79 columns | 8,709 | 100.0% |
| ≤ 89 columns | 7 | 100.0% |
| ≤ 129 columns | 3 | 100.0% |

404,663 artwork and sourcecode blocks; the widest line in the entire corpus is 129 columns, in
`rfc2124.xml`. At the current 760 pt measure, 72 columns of 17 pt monospace needs a scale just under 1.0,
and the 129-column outlier lands near 0.55 — small, but it is one block in four hundred thousand. Modern RFCXML
(> 8650) is not in this corpus, but is authored to the same 72-column convention.

Per-block scaling means two adjacent diagrams can render at slightly different sizes. Whether
to quantise the scale to a few steps so neighbours usually match is a design-pass question, not
an architectural one; start unquantised.

What the user loses, and what replaces it:

- the dedicated copy button → a "Copy Figure" context-menu item, driven by `.rfcVerbatim` under
  the cursor, plus ordinary selection-and-copy, which now works *through* the diagram
- horizontal scrolling → fit-to-measure scaling, per the table above
- `.textSelection(.enabled)` on the block → inherent

`PreformattedView.swift` is therefore **deleted**, not reused.

### Tables as text

One paragraph per row, column positions as `NSParagraphStyle.tabStops` measured by the builder,
`.byClipping`, and the same fit-to-measure scaling as artwork. Cells keep their inlines, so a
cross reference inside a cell is still a link, still a chip, and still reachable by a later
find — which an attachment would cost.

This is the least certain part of the design, and it is honestly less certain than artwork.
Table cells are `[[Inline]]`: they can be long, and tab stops do not wrap. Two facts bound the
risk:

- **`LegacyTextParser` never emits a `table`.** There are zero `<table>` elements across the
  8,457-document corpus; tables exist only in real RFCXML, roughly one library document in
  seven. A regression here cannot touch the legacy path.
- The fallback is known and cheap to reach: if tab stops prove unusable, tables become the one
  hosted view in the body, non-interactive, with their plain text substituted on copy — the
  attachment machinery this design otherwise avoids, built for exactly one block kind.

Step 0 probes this against real modern RFCs with wide tables before step 1 commits to it.

### The chip

An `NSTextLayoutFragment` subclass overrides `draw(at:in:)`: for runs carrying `.rfcReference`
it fills a rounded rect in the accent tint, then calls `super.draw`. It also overrides
**`renderingSurfaceBounds`** to include the chip's padding — without that the rounded rect is
clipped to the glyph bounds. It is supplied through
`NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`. The leading
`doc.text` symbol is an image attachment carrying the same `.rfcReference` attribute, so it
falls inside both the drawn background and the hit region. (This is the one attachment in the
design, and it is an inline image glyph, not a hosted view — it has no subview and intercepts
nothing.)

A chip that wraps across a line break is laid out as two fragments and would otherwise draw as
two half-rounded rects. Each fragment therefore rounds only the ends of the run that actually
fall inside it: leading corners on the first, trailing on the last, square in between.

### Dropping the brackets — a flag, not a layering change

Issue #6 proposes moving label presentation out of the parsers entirely, so the renderer derives
`Section 4.2 of [RFC 9110]` from `target` plus a `sectionFormat`. That is the right long-term
shape, and it is more than this milestone needs.

`RFCXMLParser.parseCrossReference` already computes the only bit the chip is missing:

```swift
let raw = derived ?? targetAnchor
let label = "[\(raw == id.description ? CrossReference.nonBreakingLabel(id.displayName) : raw)]"
```

`raw == id.description` distinguishes a canonical series id (`RFC9110`, which may be restyled)
from an author's own tag (RFC 8999's `QUIC-TRANSPORT`, which must survive verbatim) — and it is
thrown away. So:

- Add **one field** to `CrossReference`: `isCanonicalLabel: Bool`, defaulting to `false`, set
  from that comparison. `derivedContent` handling, the `sectionFormat` wording and the U+00A0
  joining all stay where they are.
- The **builder** — not the parser — drops the bracket characters when the flag is set, and
  draws the chip over the run they enclosed. In `Section 4.2 of [RFC 9110]` the chip covers
  `RFC 9110`; the rest stays plain link text.
- `LegacyTextParser.link(_:)` sets the same flag where a bracketed match is exactly the
  canonical id, so `[RFC2119]` in a legacy document chips too. Without this, 85% of the library
  would show no chips at all. Everything else stays verbatim from the source, as today.

What this buys over the issue-#6 version: `Array<Inline>.plainText` is untouched, so copied
text still reads `[RFC 9110]` and the brackets keep doing the delimiter work that
`ARCHITECTURE.md` records as their reason for existing; `RFCXMLSerializer` is untouched, so
`RFCXMLSerializerTests.roundTripsRFCXML` still passes;
`RFCXMLParserTests.canonicalDocumentLabelsUseANonBreakingSpace` still guards the rule.

**Issue #6 stays open.** This milestone does not subsume it — it takes the one bit it needs and
leaves the layering change to be done on its own terms. The issue should be amended to say so.

### Anchors, scrolling and section tracking

The builder emits a sorted `anchor -> offset` index covering **every anchor in the document**,
not only sections: `Section.anchor`, `Figure.anchor`, `Table.anchor`, `Preformatted.anchor`
(a live `ScrollViewReader` target today) and `ref-<anchor>` for each reference row. `handleLink`
scrolls to whatever anchor a `rfc-anchor:` URL names, and a missing entry is a dead link.

Jumping converts the offset to an `NSTextLocation`, calls `ensureLayout(for:)`, and scrolls to
the fragment's frame.

Section tracking **hit-tests the top of the visible rect** — `textLayoutManager.textLayoutFragment(for:)`
at `CGPoint(x: 0, y: visibleRect.minY)` — takes that fragment's start location, and
binary-searches the index for the nearest preceding anchor. It does *not* use
`textViewportLayoutController.viewportRange`: that range is deliberately larger than the visible
rect, so its start names a section the reader has already scrolled past.

`visibleAnchor` has four consumers today — the table-of-contents highlight, "Copy Link to
Current Section", the section in a copied citation, and `saveReadingPosition` — and all four
switch to this at once. Reading positions continue to store a section anchor, so nothing about
persistence changes.

### Platform split and type size

One `Coordinator` shared by two thin representables behind `#if os(macOS)`: `UITextView` and
`NSTextView`, both constructed with `usingTextLayoutManager: true`, non-editable and
selectable.

A change to the font-size slider rebuilds the attributed string and swaps the storage,
debounced, then restores the reading position from the anchor index. A two-pass
semantic-then-presentation restyle would avoid the rebuild; it is the obvious optimisation if
the rebuild proves slow, and speculative until it does. Appearance and accent changes cost
nothing, per *`ReadingStyle` carries no colours* above.

macOS hover is not free: the reference popover needs an `NSTrackingArea` over the text view, a
dwell timer, and an `NSPopover` positioned at the chip's frame. iOS uses
`textView(_:menuConfigurationFor:defaultMenu:)`.

### Accessibility

Collapsing the body into one text element collapses VoiceOver navigation with it — today each
`Text` is its own element. The replacement:

- `accessibilityCustomRotors` for headings, links and figures, built from the same index the
  anchor table comes from
- an accessibility element per artwork block, labelled from `Preformatted.name` or the figure
  caption, so a diagram is announced rather than read out character by character

This is step 5 and is part of the milestone, not a follow-up.

### Fate of existing code

| File / type | Fate |
|---|---|
| `Views/Rendering/InlineText.swift` | deleted; `attributedString(_:)` and `anchorScheme` move into the builder |
| `Views/Rendering/PreformattedView.swift` | deleted; artwork is text |
| `Views/Rendering/BlockView.swift` — `BlockView` | deleted |
| `Views/Rendering/BlockView.swift` — `ListBlockView` | deleted; marker derivation moves into the builder, tests move with it |
| `Views/Rendering/BlockView.swift` — `TableBlockView` | deleted; tables are text |
| `Views/Rendering/BlockView.swift` — `ReferenceRow` | deleted; reference rows are text, and the `@Environment(LibraryModel.self)` "Open …" button becomes an `rfc://` link handled by the coordinator |
| `Views/DocumentView.swift` — `SectionView` | deleted |
| `Views/DocumentView.swift` — `DocumentHeaderView` | kept, minus the abstract, which moves into the storage; hosted in the text view's top inset |
| `Views/DocumentView.swift` — `StatusBanner` | unchanged; moves inside `DocumentHeaderView`, after the author line |
| `Views/DocumentView.swift` — body | `ScrollView`/`LazyVStack` replaced by `RFCTextView` |
| `Views/DocumentView.swift` — `TableOfContentsView` | unchanged |
| `Views/DocumentView.swift` — `OriginalTextView` | unchanged; the "Original Text" toggle keeps its own plain path |
| `Views/DocumentView.swift` — `Clipboard` | unchanged |

## Testing

This work brings the **first unit tests to the app target**. There are none today. A new
`RFCReaderTests` target in `project.yml`, Swift Testing to match RFCKit.

The builder is pure, so the valuable assertions need no view:

- every anchor in the document — sections, figures, tables, preformatted blocks and reference
  rows — appears in the index, with offsets increasing monotonically
- **no `U+FFFC` appears anywhere in the built string except for chip symbols.** This is the
  regression guard on the central decision: a block kind that quietly becomes an attachment
  fails here.
- artwork survives byte-for-byte: every line of a `Preformatted.text` appears as its own line in
  the built string
- a figure's caption, a block quote's prose and a table's cells appear as text
- `.rfcReference` attributes sit at the expected ranges carrying the expected targets
- no text is lost: every paragraph's `plainText` appears in the built string
- label derivation: a canonical id loses its brackets and gains a chip run, an author tag
  (`QUIC-TRANSPORT`) keeps its brackets and gains none, a legacy `[RFC2119]` chips, and
  `plainText` is unchanged in all three cases
- list markers: the cases that `ListBlockView.marker(at:)` covers today, moved over intact

Chip drawing, hover, scroll and accessibility behaviour are view-level and are not covered by
this milestone.

CI gains a `make test-app` step in the existing macOS job.

## Sequencing

| # | Step | State afterwards |
|---|---|---|
| 0 | **Probes, throwaway.** Deep-jump layout cost, restyle cost, tables-as-tab-stops. | app untouched |
| 1 | Test target; `DocumentTextBuilder` for every block kind; anchor index. No UI change. | app unchanged, working |
| 2 | `RFCTextView` representables and coordinator; `DocumentView` body swapped; anchor jumping and viewport tracking; header into the top inset; the old render path deleted | working, complete except chips and previews |
| 3 | `isCanonicalLabel` flag; chip drawing and symbol; brackets dropped | working |
| 4 | Link previews: hover on macOS, long-press on iOS | working |
| 5 | VoiceOver rotors and artwork accessibility elements | working, complete |

The old render path survives untouched until step 2 replaces it whole, so `visibleAnchor` is
never nil and no reading position is ever overwritten with one. Every step leaves the app in a
working state.

### Step 0 in detail

Three measurements, all throwaway code, all before anything is committed to.

**Probe A — deep jump.** TextKit 2 lays out sequentially; there is no random access to a
fragment's y-origin, so `ensureLayout` to section 250 of RFC 9110 lays out all 1,376 paragraphs
before it synchronously. This is not an edge case for this reader — it is reading-position
restore on *every* open, every `rfc://…/section/…` deep link and every table-of-contents tap,
and `VISION.md` puts exactly that audience first. Build RFC 9110's storage, jump to the last
section, measure time to first paint on the oldest supported device class. This probe can kill
the approach, which is why it is first: if it is slow, the mitigations (chunked or asynchronous
layout, or one storage per section) range from awkward to a requirement-1 failure.

**Probe B — restyle.** Rebuild RFC 9110 on a font-size change and measure. Sets the debounce,
and decides whether the two-pass restyle is speculative or necessary.

**Probe C — tables.** Tab stops against real modern RFCs with wide tables and long cells. Gates
the tables-as-text decision against the fallback named above.

Note that the first draft's step-0 gate — "does `tracksTextAttachmentViewBounds` size
SwiftUI-hosted content correctly" — tested a property the API does not have. It only makes the
default `attachmentBounds` return the hosted view's `bounds`; the host still has to be sized by
hand, and these views are width-dependent, so `attachmentBounds` needs overriding regardless.
With no hosted views left in the body, the question no longer arises.

## Risks

| Risk | Mitigation |
|---|---|
| Deep jumps force full-document layout | probe A, first thing, before any commitment |
| Wide artwork clips or shrinks too far | fit-to-measure scaling; the corpus says 99.998% of blocks are ≤ 79 columns |
| Tables as tab stops break on long cells | probe C; fallback to a single non-interactive hosted view, affecting no legacy document |
| Whole-document rebuild on every slider tick | debounce, restore position from the anchor index; two-pass restyle if probe B says so |
| A rebuild on every appearance change | dynamic colours in the storage, not resolved ones in `ReadingStyle` |
| VoiceOver collapses to a single element | custom rotors and per-artwork elements, step 5, inside this milestone |
| The two platform paths diverge | one shared `Coordinator`; representables kept thin; hover and long-press are the only genuinely split code |
| Regression in scroll-to-anchor | hit-test the visible top rather than `viewportRange`, and index every anchor, not only sections |

## Documents this changes

- `docs/ARCHITECTURE.md` — the "Decision: TextKit 2 for the reader body" section sketches the
  hybrid rejected above, and its reference-label paragraph describes the bracket handling this
  changes; update both when the work lands.
- Issue #6 — **not** closed by this work. Amend it to record that the chip takes only
  `isCanonicalLabel`, and that the `sectionFormat` layering change remains outstanding.
