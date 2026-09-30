# Highlights and reading notes — design

*30 September 2026. Approved in brainstorming, section by section, then revised after an
adversarial review against the code. Slices 1, 2, 4, 5a and 5b are approved designs. Slice 3
is **probe-gated**: its design is approved only once the probe described below has been
measured. Each slice gets its own implementation plan. Precursor, not a blocker: #491, part
numbers on legacy paragraphs.*

## Why

A spec is read with a pencil. An implementer marks the sentences they will be held to, and
notes what a passage means for their code, what it contradicts elsewhere, and what they
asked the working group. `VISION.md` lists "Highlights and notes, synced, exportable as
Markdown with citations attached" as a later tier. This is that feature: highlights in color
over passages, the way Apple Books does them, and rich reading notes kept beside the text they
are about.

The notes are **personal reading notes, not collaboration**. There is one user, with no
sharing, no threads and no authorship. They are meant to be read **in context**, beside their
passage.

## Slices, and what each stands on

Each slice ships alone, as its own plan and pull request, and leans only on slices already
shipped. The order below is the order they ship in.

| # | Slice | Stands on | Value on its own |
|---|---|---|---|
| 1 | **Highlights**: the model text and position map, anchoring and relocation, the drawing, the color menu, and the Annotations inspector tab | nothing | Books-style highlighting on every platform |
| 2 | **Notes**: notes on a highlight, a block or a section; the editor in a popover or sheet; gutter markers | 1 | reading notes everywhere, iPhone included |
| 5a | **Markdown export** of a document's annotations, with citations | 1, and grows with 2 and 4 | take your notes elsewhere |
| 3 | **The notes column** (probe-gated): notes beside their passages, behind a rule | 2 | notes read in context on Mac and iPad |
| 4 | **Attachments**: images and files in a note | 2 | richer notes, with or without 3 |
| 5b | **PDF export with native annotations** | 1, and grows with 2 | an annotated RFC in any PDF viewer |

Four rules make independent release real:

- **The schema grows per slice.** Each slice adds its rows in the next `VersionedSchema` when
  it lands; V4 is current. The version numbers are not fixed here, because other data work
  (#155, #355, #358) may take a version first. Compatibility with older stores costs nothing
  here, but every version still gets its migration test against a store written on disk, as
  V1–V4 have.
- **This spec fixes what later slices depend on**, so no early slice is reworked:
  - the model text, the position and the target format;
  - a note's stored body, as Markdown, so it does not depend on which editor wins (slice 2);
  - a note's owner;
  - gutter placement, which slice 2 introduces and slice 3 reuses.
- **The exports cover whatever exists.** 5a ships exporting highlights with their quotes, and
  each later slice adds its part.
- **Nothing is pinned to slice 3.** Slices 1, 2, 4 and 5 are complete without it.

## What can be annotated

Everything in the text storage, except the parts listed below.

- **The title block and the author chips.** They are a hosted header view over the text, not
  part of the storage (`RFCTextView`'s header host).
- **The references section.** The builder skips it, and the bibliography lives in the
  inspector's References tab (`DocumentTextBuilder.appendSection`).
- **Original Text.** `OriginalTextBody` is the published text, one to one, and has no model
  positions. Annotations are not drawn there, and switching to it hides them. They are not
  lost.

A bibliography entry can take a note once the References tab offers it. That is not part of
this design.

## The model text

Positions count in the document **model's** text, never in the storage. The storage adds
things of its own and changes with the column:

- section numbers and the added "Abstract" heading;
- list markers followed by a tab;
- a chip's attachment character, and a reference restyled from `RFC9110` to `RFC 9110`;
- the header label a stacked table repeats in every cell, grid or stacked depending on the
  measure;
- verbatim blocks shown unfolded when every unfolded line fits the column, and as published
  otherwise.

None of these may move a highlight.

### Per element

The model text of an element is fixed as follows. It is **normative**, and slice 1 implements
it as a function in `RFCReaderKit` with tests over each case.

| Element | Its model text |
|---|---|
| Inlines (anywhere) | `[Inline].plainText`, the existing flattening: cross references as their derived text, and `lineBreak` as `\n` |
| Section heading | its `title` inlines. Never the number, which the builder composes around it |
| `paragraph` | its inlines |
| `list` | each item's blocks in order, items joined by `\n`, with no markers |
| `definitionList` | each item's term, `\n`, then its definition blocks. Items joined by `\n` |
| A list item, as an anchor | its blocks, joined by `\n` |
| A definition item, as an anchor (`<dt>`) | its term, `\n`, then its definition blocks |
| A definition, as an anchor (`<dd>`) | its definition blocks, joined by `\n` |
| `preformatted` | `content.text` **as published**, the folded form. The unfolded display maps back through `FoldedLines`, which gains an offset map |
| `figure` | its name or caption inlines, `\n`, then its artwork's text |
| `table` | row by row: cells joined by `\t`, rows by `\n`, header rows first. Never the stacked labels |
| A table row, as an anchor | its cells, joined by `\t` |
| `blockQuote`, `aside` | their blocks, joined by `\n` |
| A section, as an anchor | its heading, `\n`, then its blocks joined by `\n`, **including** blocks that carry anchors of their own. Subsections are **not** included: each is its own anchor |

An element's model text is the text of its **innermost anchor**. An anchor's text contains
the text of every anchored block inside it, so a block gaining an anchor, as legacy paragraphs
do with #491, leaves every offset into its section valid. A block without an anchor of its
own lies inside its section's text at the offset of that join.

### The position map

As `DocumentTextBuilder` appends, it records a **position map**: an interval list pairing
storage ranges with model ranges under an anchor. Every storage character either maps to a
model position or is declared storage-only (a marker, a number, a stacked label, a chip
character). A storage-only character snaps to the nearest model position in reading order:
forward at a range's start and backward at its end, so a selection that begins on a section
number does not reach into the block before it.

- The map lives in `BuiltDocument`, beside `AnchorIndex`, which today records only each
  anchor's start. It holds for every build: the reader's at any column, the print's and the
  export's.
- Selection to position, and position to storage range, are pure queries on it.
- The other direction has holes too: a model position may have no storage in a given build.
  An RFC 8792 folding header and the blank line after it are part of a folded block's model
  text, and the unfolded display drops both. The build declares such positions **hidden**, and
  a highlight is clipped to the positions that are mapped. A highlight with none is not drawn
  in that build, and is not detached for it.
- **The guard:** a `BuilderCompletenessTests`-style test over committed fixtures that every
  storage character is mapped or declared storage-only, that every model position is mapped
  or declared hidden in that build, and that model → storage → model round-trips for every
  mapped position. It runs at two column widths, so the fold/unfold and grid/stacked
  differences are both exercised.

## Positions, targets and relocation

### A position

A position is `(anchor, offset)`. `anchor` is the innermost element containing the point
that carries an anchor: a paragraph's `pn` where it has one, otherwise its section, and down to
a list item, a definition's term or definition, or a table row wherever the model keeps one
(`Block.anchors`). `offset` counts Unicode
scalars into that anchor's model text.

### A target

```
Target
  .section(anchor)                      a note on a whole section
  .range(start, end, quote)             any span, possibly across blocks
Quote
  exact                                 the text the range covered, at most 256 characters
  prefix, suffix                        up to 32 characters before the range's start and after its end
  length                                the length of the whole covered text, when exact was cut
  digest                                a SHA-256 of the whole covered text, when exact was cut
```

This follows the shape of the W3C Web Annotation selectors: a position selector, with a text
quote selector as its fallback. "Note on this figure / table / paragraph" is a `.range`
covering exactly that block. A quote over a large artwork keeps its first 256 characters plus
the length and digest, so the row stays small when it syncs. The suffix is always taken after
the range's real end, never after the cut. A cut quote is matched by its first 256 characters
and its prefix or suffix, as any quote is; its end is its start plus the length, and it
counts only if the digest of the text it then covers matches.

### Relocation

`relocate(target, in: document) → .exact | .moved(Target) | .ambiguous | .detached` is a pure
function. Everything it compares is **normalized** first: runs of whitespace collapse to one
space, soft hyphens and line-end hyphenation are removed, and the reference spellings
`[RFC2119]`, `RFC 2119` and `RFC2119` compare as one. Normalization keeps a map back to the
raw model text, and every offset `relocate` returns is a raw model offset, never a normalized
one.

1. If the normalized text at the stored position matches the quote, the result is `.exact`.
   When a finer anchor now contains the position, it is re-expressed under that innermost
   anchor, and written to the relocated fields as a `.moved` result would be.
2. Otherwise it searches for the quote under the same anchor, then in the anchor's section,
   then in the whole document. A candidate must match the exact text **and** its prefix or
   suffix. A quote of fewer than 12 characters must match both.
3. If exactly one candidate is found, the result is `.moved`. If several are found, the
   result is `.ambiguous`, as happens with repeated boilerplate or a repeated MUST sentence.
   An ambiguous highlight is **drawn nowhere and never exported**: the text at its stored
   position no longer matches, so drawing it there would mark an unrelated passage. It is
   listed, flagged, in the Annotations tab, where the reader can re-place or delete it. Its
   notes are the reader's own words and never silently vanish: the Markdown export keeps
   them, and only the PDF leaves them out (slices 5a and 5b). The
   code never guesses between candidates by nearness.
4. If nothing is found, the result is `.detached`. **A detached annotation is never deleted.**
   It is kept and shown apart, as "this passage no longer exists in this document".

A `.section` target relocates only by its anchor. It is detached when the anchor no longer
exists.

**The original is never overwritten.** A row keeps the position it was made at. A `.moved`
result is written to separate **relocated** fields, only for a unique match, and without
touching `modifiedAt`. How a relocation and an edit made on another device meet is the sync
work's conflict policy, not this design's. Once the relocated fields match, reads use them, and
relocation does not run again on every open. If a later pipeline change breaks the relocated
position, relocation starts over from the original. When a finer anchor exists, the relocated
fields take it, whether the result was `.exact` or `.moved`: a position under `section-4.2` is
re-expressed under `section-4.2-3` once #491 lands, with no migration.

RFCs never change once published. Text only moves when this project's own pipeline changes:
a heuristic fix, #491, or a document moving from converted legacy text to authored XML. The
relocation rules are written for exactly those cases.

## The rows

The rows follow the collections precedent (`ARCHITECTURE.md`, "collections are rows linked by
identifier"): rows linked by identifier, never SwiftData relationships, and in CloudKit's
shape, with nothing `@Attribute(.unique)` and every attribute optional or defaulted.
Uniqueness is the store's job. Every row is keyed on the document's `fileStem` as
`documentKey`.

- **`Highlight`** (slice 1):
  - `id` (UUID) and `documentKey`;
  - `startAnchor`, `startOffset`, `endAnchor`, `endOffset`;
  - the relocated copies of those four, optional;
  - `quoteExact`, `quotePrefix`, `quoteSuffix`, `quoteLength`, `quoteDigest`;
  - `color`: a name from the palette. `underline` is one of the names, and draws a rule
    rather than a fill;
  - `createdAt`, `modifiedAt`.
- **`Note`** (slice 2):
  - `id` and `documentKey`;
  - *either* `highlightID` *or* a target of its own: `sectionAnchor`, or the same range, quote
    and relocated fields as a highlight;
  - `body`: **restricted CommonMark**, as a string (below);
  - `createdAt`, `modifiedAt`.

  Several notes may share one highlight.
- **`NoteAttachment`** (slice 4):
  - `id` and `noteID`;
  - `contentType`, `fileName`, `byteCount`;
  - `data`, in `@Attribute(.externalStorage)`.

**Orphans are kept, never deleted.** Under sync, a note can arrive before its highlight and an
attachment before its note. A note whose highlight is missing is re-pointed to the surviving
highlight that covers its quote, as happens when a merge on another device deleted its
highlight; with none, it shows as detached. The sweep with a grace period that collections are
waiting on (`ARCHITECTURE.md`) covers these rows too, and it belongs to the sync work.

**Deleting.** Deleting a highlight that has notes asks first, then deletes the highlight and
its notes. Deleting a note deletes its attachments.

**Pinning.** A document with annotations is **pinned against eviction**, as a bookmarked
document is (`CacheEviction`). The Annotations tab needs the document to relocate against, and
an annotated spec is one the reader means to come back to.

**Where the code lives**

- **`RFCReaderKit/Annotations`**, tested there:
  - the model text and the position map's queries;
  - `Position`, `Target`, `Quote`, normalization and `relocate`;
  - merging, document ordering, gutter placement;
  - the Markdown body's scope, its parser and its serializer;
  - both exports' pure halves.
- **`RFCReaderKit/UserData`**: the schema versions, `AnnotationStore` for every change and
  `AnnotationSnapshot` for every read, mirroring `CollectionStore` and `CollectionSnapshot`.
  `LibraryModel` publishes the snapshot.
- **The app**: the text view wiring, the menus, hosting for the popover, sheet and markers, and
  the PDFKit calls.

## Slice 1: highlights

### Drawing: never in the storage

A highlight is **not** an attribute in the built text. A build is handed over and never
written to, and a kept build is installed into more than one text view (`CLAUDE.md`,
`BuilderHandoverTests`). Writing highlights into it would also mean a rebuild on every change.

Each text view marks its highlights as **rendering attributes** on its own
`NSTextLayoutManager`, under a custom `.rfcHighlight` key holding the color name. Rendering
attributes change how the text is drawn, never how it is laid out, so a highlight never
re-wraps or rebuilds anything. The rules:

- **Add and remove only.** Highlights go through `addRenderingAttribute` and
  `removeRenderingAttribute`. The text view keeps its own rendering validator, which it may
  use for links, and a validator of ours is never installed over it.
- **Re-apply after every install.** A rebuild installs a new storage
  (`NSTextContentStorage.install(_:)`), and the rendering attributes go with the old one. After
  every install, the coordinator applies the highlights again, from the new build's position
  map.
- **Never in the fragment's cache.** `RFCTextLayoutFragment` caches its decoration and chip
  data until `invalidateLayout`, and a rendering attribute changes nothing that clears the
  cache. The fragment reads highlights **at draw time**, never into that cache.
- **Translucent fills, drawn beneath the text.** The fill is translucent, so a selection inside
  a highlight stays visible. Where the fill lies over a card (a table or artwork background),
  the two blend. Contrast is checked with `SRGBColor` over **both** backgrounds, the page's and
  the card's, in light and in dark: text over a highlight keeps 4.5:1, the rule the author
  monograms are held to.
- **Inside the drawing bounds.** The fill has rounded ends and runs continuously across the
  lines of one highlight, so it can reach past the glyphs. `renderingSurfaceBounds` is widened
  to cover it, or the ends are clipped, which has happened to a rule before. Where the rects go
  is a `FragmentGeometry` function.
- **Underline.** It draws a thick rule under the baseline, from the same geometry.
- **Beneath find.** The system find interaction draws its matches over the text, and so
  over the fills.

**The probe comes first.** Slice 1's first task is a throwaway probe of all of this:

- a fragment reading rendering attributes while drawing off the main thread;
- the selection staying visible inside a fill;
- the attributes after `install`;
- the fragment cache;
- the widened drawing bounds.

If reading off-main fails, the fallback draws the fills in a layer of the text view's own,
beneath the text, from the same geometry.

### The palette

The palette is fixed and named, the way `CollectionColor` is: yellow, green, blue, pink,
purple, and `underline`. It is stored by name, so an older build reads a name it does not know
as the default. The fills are fixed sRGB with alpha, per appearance.

### Making one

Select text, then choose Highlight:

- **Mac:** the context menu (a color row, with the last-used color first), Edit ▸ Highlight,
  or ⌃⌘H, Books' shortcut.
- **iOS:** an item in the edit menu, with the same row.

The selection snaps to word boundaries.

### Merging

A new highlight that overlaps existing ones **merges** with every one it overlaps: one
highlight covering all their ranges, in the new color. The **oldest** row survives, keeping its
`id` and `createdAt`; the others are deleted. Notes are **not** joined. Every note of an
absorbed highlight is re-pointed to the survivor, as several notes may share a highlight.
Undo restores every highlight and the notes' owners.

### Changing one

A **single click** (Mac) or **tap** (iOS) inside a highlight, with no drag, opens a popover:
the color row, Delete and Copy as Quote, plus, from slice 2 on, Add Note and the highlight's
notes. The popover waits out the double-click interval before it opens, so it is never
shown on the way to a double-click. It does not open when a click only clears an existing
selection. Everything else behaves as it does now:

- a double-click still selects a word;
- a drag still selects;
- a force-click still previews;
- a link inside a highlight still opens.

### The Annotations inspector tab

The tab lists every highlight in document order, with its quote and section. Clicking one
scrolls to its passage. Ambiguous and detached highlights are listed last, marked as such. The
reader can re-place or delete an ambiguous one there. It follows the `RequirementsView`
pattern. From slice 2 on, it lists notes too.

If the document fails to load, the tab lists the stored quotes without positions and says the
document is unavailable. Nothing is detached for that reason.

### Accessibility

Rendering attributes are invisible to VoiceOver. The coordinator adds a **Highlights rotor**
and a "highlighted, yellow" hint to the ranges, beside its existing accessibility work.

### Where highlights do not appear

- **Print** makes a build of its own, and draws none. Exporting them to PDF is slice 5b.
- **Original Text** (see above).

## Slice 2: notes

### Starting one

- **From a selection:** Add Note makes a highlight in the last-used color and opens a note on
  it, the way Books does.
- **From a highlight's popover:** Add Note, which adds another note if the highlight already
  has one, or a note listed there, to edit it.
- **On a block:** Add Note to Figure / Table / Paragraph, from that block's context menu. It
  targets a `.range` covering exactly the block, with no highlight.
- **On a section:** Add Note to Section, from the heading's context menu and from the
  section's row in the contents panel.

### Gutter markers

A small note glyph sits in the **trailing** gutter, level with the first line of its target.
The leading gutter is kept for #433's hanging section numbers. Markers show on every platform.

- **Placement** is a pure `FragmentGeometry` function: target → storage range (position map) →
  first line fragment → y. Markers that would overlap stack.
- **Only where layout is real.** The reader lays out in slices, and a TextKit 2 frame outside
  the laid-out range is an estimate. Markers are placed only over the laid-out range, plus a
  margin, and are placed again as layout proceeds. A marker never shows at an estimated
  position.
- **Hosting** follows the header's precedent, not the reference hover's (which is an
  `NSPopover`). Markers are views added to the text view the way `RFCTextView`'s header
  host is. Like every hosted root on macOS, a SwiftUI marker is handed `LibraryModel`,
  `NavigationModel`, `ReaderState` and the model container explicitly. An `@Environment`
  lookup there is a runtime trap.
- Clicking or tapping a marker opens its note, or a short list when several notes share a line.

### Where the editor opens

- **Mac:** a popover anchored to the marker or the highlight, sized for a few paragraphs, with
  a button to continue in the Annotations tab. The popover's hosted root is handed its models
  explicitly, like any other.
- **iOS:** a sheet at the medium detent, so the passage stays visible above it.

While the editor has focus, the text view is not first responder:

- ⌃⌘H does not apply;
- ⌘K belongs to the editor. On iOS and iPadOS, ⌘K is already Go to RFC (`ContentView`'s
  hidden button), so the editor's claim on it has to win there while it has focus;
- Edit ▸ Find searches the note, not the document.

Menu validation follows focus as it does anywhere in AppKit, and the plan checks each of those
commands by hand.

### The body: restricted CommonMark

A note is **stored as a Markdown string**. What the editor edits is a projection of it, parsed
on open and serialized on save. Storing the editor's own format was rejected for two reasons:

- A TextKit list lives in `NSParagraphStyle` and not in an `AttributedString` scope, so the
  stored format would have depended on which editor won the probe.
- A custom scope's Codable silently drops attributes it does not know, so renaming a key would
  lose formatting without an error.

Markdown depends on neither editor, diffs sensibly under sync, makes 5a close to an identity,
and is what 5b puts into a PDF annotation anyway.

- **The scope** is CommonMark restricted to:
  - emphasis, strong and strikethrough;
  - inline code;
  - links;
  - bulleted and numbered lists, nested;
  - paragraphs.

  Anything else on paste, whether fonts, sizes, colors, headings or tables, is reduced to that
  scope.
- **Attachments** (slice 4) are links in the text, `attachment:<uuid>`.
- **Parsing and serializing** are pure, in `RFCReaderKit`, with a round-trip test over the whole
  scope: parse ∘ serialize is the identity on everything in scope.
- **The editor** is SwiftUI `TextEditor` over `AttributedString` if it handles nested lists.
  Otherwise it is a TextKit 2 `NSTextView`/`UITextView` with `NSTextList`. Slice 2's first task
  is that probe. Either way, what is stored does not change.
- **Links.** ⌘K opens a field that takes a URL or anything that names an RFC, such as
  `RFC 9110 Section 4.2`, `9110#section-4.2` or an rfc-editor.org URL, parsed through the
  existing `RFCLink` code. A pasted rfc-editor.org or `rfc://` URL becomes a link by itself. A
  link to a passage of the same document scrolls there, rather than opening a tab.
- **Saving.** The note autosaves, debounced by about a second, and again when the editor
  closes. A note left empty is deleted when it closes. Undo is the editor's own.

In the Annotations tab, each note's first line shows under its quote or block, and clicking one
scrolls to the passage and opens the editor.

## Slice 3: the notes column (probe-gated)

The goal is unchanged: notes beside their passages, level with the text they belong to,
behind a hairline rule, never over the text. They stack when they crowd, and the column is
toggled with View ▸ Show Notes (⌥⌘N) and a toolbar button, kept per window and off by default.

The review found that the first design broke documented invariants. The **design is decided
by a probe**, and this section fixes what the probe must answer.

### Why it is gated

The first design laid cards into the text view's own trailing area, and let the contents panel's
covered width narrow the text. That:

- **reverses a rule, not qualifies it.** `DocumentView.column` is derived "from the pane's
  width and the measure preference, and nothing else", and "the panel does not appear here and
  must not". Making the panel's width an input means AppKit reports it into the hosted root.
  Opening the panel then rebuilds the document, re-measures tables and artwork, and restores
  the reading position, which is the loss that rule exists to prevent;
- **needs asymmetric insets on the Mac.** `textContainerInset` is symmetric, and there is no
  asymmetric form. Moving the text off center means overriding `textContainerOrigin` or
  widening the text view, which is new, load-bearing geometry;
- **re-wraps on every toggle under `.fullWidth`,** which leaves no slack for a column;
- **grows the text view for cards stacked past the last line,** which reports the notes'
  height back into the text view's frame.

### The two candidates

The probe builds both on RFC 9110, and measures them.

- **A. In-scroll-view.** Cards are subviews of the text view, beside a text container moved off
  center by `textContainerOrigin`.
- **B. Sibling view.** A notes view beside the reader's scroll view, *inside the reader pane*,
  not a split item. The reader's scroll offset drives it, and it places cards with the same y
  function. The text view's geometry is untouched.

Under either, the text column's width is `ReaderLayout`'s from the reader pane's width and
the notes toggle. This **amends** the rule on `DocumentView.column`, "the pane's width and the
measure preference, and nothing else": the toggle becomes its third input. Slice 3 updates
that comment and `ARCHITECTURE.md` along with its decision. **The contents panel stays out of
it:**

- with notes on, the panel covers the notes, exactly as it covers the slack today;
- the notes are not pushed aside;
- opening the panel re-wraps nothing, and rebuilds nothing, with notes on or off.

If covered notes turn out to be unusable in practice, the fallback is to make the two
exclusive (opening one closes the other), never to feed the panel's width in. Below a
readable minimum, and always on iPhone, there is no column, and slice 2's gutter markers stand
in for it. On iPad the panel is SwiftUI's and does reserve width, so the arithmetic there is
simply "the pane's width after the panel".

**What the probe measures**, on both candidates:

- toggling the column re-wraps at most once, and never under scrolling;
- the panel with notes on and off re-wraps zero times;
- cards do not visibly move while scrolling through a long document;
- reading-position restore and back/forward land where they did before;
- scrolling cost with 200 notes.

### The card solver, either way

`stack(desired: [y], heights: [h], focused: index?) → [y]` is pure:

- cards keep document order and never overlap;
- a focused card, one being edited or whose highlight was just clicked, sits exactly at its
  desired y, and the others move around it.

The rules below keep it from reporting into the text's layout:

- **It solves only over the laid-out range plus a margin,** as the markers are placed. Cards
  outside that range are not placed, so nothing is placed from an estimate.
- **Card heights are measured by the card views** and change only the notes' layout. Editing in
  place re-runs the solver on the notes alone.
- **Overflow never grows the text.** Cards that would stack past the end of the document are
  collapsed into a final "+N more" card that opens the Annotations tab. The notes' height never
  reaches the text view's frame.

Cards are collapsed to a few lines with a "more" control, and clicking one edits it in place in
slice 2's editor. A section note sits at its heading. A detached note sits at its old section's
heading if that exists, otherwise at the top. A highlight without notes has no card. While the
column shows, the gutter markers are hidden.

Hover cross-highlighting (a card brightens its highlight, and a highlight outlines its card)
is deferred until the column exists and has been used.

## Slice 4: attachments

- **Adding:** drop, paste, or an Attach… button in the editor. Images show inline at the note's
  width. Other files show as a chip with an icon, name and size, and open with Quick Look.
- **Storage:** an attachment is a `NoteAttachment` row with its data in external storage. In
  the body it is an `attachment:<uuid>` link, so the text stays small and a sync of the text
  never carries a file.
- **Size:** a file over 25 MB is refused, with a message.
- **Orphans:** an attachment whose note is missing is kept, and left to the sweep.

## Slice 5a: Markdown export

- One file per document: a front matter block with the RFC number, the title and the date
  exported, then the annotations in document order, grouped under their section headings.
- Each highlight is a block quote with a citation link, such as
  `[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)`, with its notes
  under it. Section and block notes sit under their heading. Detached annotations come last,
  with their quotes. An ambiguous highlight is left out, but its notes are not: they come last
  with the detached annotations, marked as not placed. Like a detached annotation, each
  carries the highlight's quote text, but no citation to a position.
- A note body is already Markdown. The export only rewrites its links: `rfc://` becomes an
  rfc-editor.org URL, since the file leaves the app, and `attachment:<uuid>` becomes a relative
  path into a folder written beside the file. Without attachments, the export is a single
  `.md` file.
- The export is a pure function from snapshot and document, in `RFCReaderKit`. It is a case in
  `ExportFormat` and in `DocumentExport`, the one switch every export goes through.

## Slice 5b: PDF export with annotations

- Export as PDF gets a toggle, Include Highlights and Notes. With it on:
  - each highlight becomes a `.highlight` or `.underline` markup annotation in its color, and
    its notes' Markdown becomes the annotation's contents;
  - a section note becomes a text annotation at its heading;
  - an ambiguous highlight is left out, and its notes with it.
- **Annotations do not print.** `shouldPrint = false` is set explicitly on every annotation. This
  is decided: the annotations are for reading on screen in a PDF app, and a printout of the
  export is a clean copy. Print itself never adds annotations.
- The mechanism follows the link annotations of #376. The export build's position map gives
  each target's storage range, and the layout manager gives its line rects. Target → rects →
  annotation spec is a pure function in `RFCReaderKit`, beside `PDFExport.target(of:references:)`.
  The PDFKit calls stay in `DocumentPDF+Export`.
- **Known limits.** Formatting is reduced to the Markdown text, since PDFKit exposes no API for
  PDF rich text (`/RC`) and Preview ignores it. The export is one way: edits made in another
  PDF app do not come back.
- **Probes before promising:** how markup looks in Preview, and whether file attachments are
  feasible through PDFKit. Until the second is proven, attachments are left out of the PDF.

## Neighbors this design has to live with

- **Reading modes (#188).** Outline hides body text, and a hidden highlight is simply not drawn.
  Focus puts cited references beside the section, possibly in the same trailing area as slice
  3's column. Whichever lands second decides how they share it.
- **Side by side (#187).** Each pane is its own text view, with its own rendering attributes
  from the same snapshot. Nothing more is needed.
- **Spotlight and the AppleScript dictionary.** Neither indexes or exposes annotations in these
  slices. Each is an issue of its own once slice 2 exists.
- **Search.** Full-text search does not search notes in these slices.

## Testing

- **Pure logic in `RFCReaderKit`,** with Swift Testing and raw-identifier names:
  - the model text for every element, and the position map's completeness and round trip, at
    two column widths;
  - normalization and relocation, including `.ambiguous`, a cut quote, and an `.exact` result
    re-expressed under a finer anchor;
  - merging across several highlights, the oldest surviving, and note re-pointing;
  - gutter placement, and the card solver;
  - the Markdown body's parse and serialize round trip;
  - both exports.
- **Relocation against real documents only,** through committed fixtures and `Corpus-backed:`
  suites:
  - a position made in the legacy parse of an RFC relocates into the authored XML of the same
    RFC, where both exist;
  - positions survive a rebuild at another column width, and in the print and export styles.

  No RFC text is committed. A test finds its passage at run time by a short locator.
- **Schema:** each version gets a migration test against a store written on disk.
- **Guards:**
  - `BuilderHandoverTests` gains a check that highlighting leaves the build untouched.
  - ``BuilderCompletenessTests.`nothing becomes an attachment` `` stays as it is, since
    nothing new enters the storage.
- **By hand on the Mac,** on RFC 9110, through AppleScript and AX reads, never synthetic
  keystrokes:
  - slice 1: highlighting leaves layout identical, with zero differing pixels outside the fills,
    and the selection is visible inside a fill;
  - slice 2: ⌃⌘H, ⌘K and Find each do the right thing while a note is being edited, and ⌘K
    again on an iPad with a keyboard, where it is also Go to RFC;
  - slice 3: the probe's measurements, above.
- **Docs:** each slice adds its dated decision to `ARCHITECTURE.md`:
  - slice 1: the model text and position map, relocation, and highlights as rendering
    attributes;
  - slice 2: the Markdown body;
  - slice 3: whichever candidate the probe chose, and why.

  `VISION.md`'s tier line is updated as the slices land.

## Out of scope

- Sync. The model is CloudKit-shaped, and turning sync on is the separate iCloud work.
- Pencil markup (`VISION.md`'s separate item).
- Reading annotations back out of a PDF.
- Checklists, headings, fonts and colors in notes.
- Notes on bibliography entries.
- Sharing, threads, or any second author.
