# Highlights and reading notes — design

*30 September 2026. Approved in brainstorming, section by section; each slice gets its own
implementation plan. Precursor, not a blocker: #491 (part numbers on legacy paragraphs).*

## Why

A spec is read with a pencil. An implementer marks the sentences they will be held to and
notes what a passage means for their code, what it contradicts elsewhere, and what they
asked the working group. `VISION.md` lists "Highlights and notes, synced, exportable as
Markdown with citations attached" as a later tier. This is that feature: highlights in color
over passages, the way Apple Books does them, and rich reading notes kept beside the text they
are about.

The notes are **personal reading notes, not collaboration**. There is one user, no
sharing, no threads, no authorship. They are meant to be read **in context**, beside their
passage, which is why the notes column sits next to the text behind a rule and never over it.

## Slices, and what each stands on

Each slice ships alone, as its own plan and pull request, and leans only on slices already
shipped.

| # | Slice | Stands on | Value on its own |
|---|---|---|---|
| 1 | **Highlights**: the model, anchoring and relocation, the decoration, the color menu, the Annotations inspector tab | nothing | Books-style highlighting on every platform |
| 2 | **Notes**: notes on a highlight, a block or a section; the `AttributedString` editor in a popover or sheet; gutter markers | 1 | reading notes everywhere, iPhone included |
| 3 | **The notes column**: `ReaderLayout` with the column as an input, aligned cards, editing in place | 2 | notes read beside the text on Mac and iPad |
| 4 | **Attachments**: images and files in a note | 2 | richer notes, with or without 3 |
| 5a | **Markdown export** of a document's annotations, with citations | 1 (grows with 2 and 4) | take your notes elsewhere |
| 5b | **PDF export with native annotations** | 1 (grows with 2) | hand someone an annotated RFC |

What makes independent release real:

- **The schema grows per slice**: `SchemaV5` adds highlights, `V6` notes, `V7` attachments.
  Compatibility with older stores costs nothing here, but each version still gets its
  migration test against a store written on disk, as V1–V4 have.
- **This spec fixes what later slices depend on**, so no early slice is reworked: the
  position and target format (below), a note's owner, and the placement and stacking function
  that slice 2's gutter markers introduce and slice 3's cards reuse.
- **Both exports cover whatever exists.** 5a ships exporting highlights with their quotes, and
  each later slice adds its part.

## The model and the anchoring

### A position

A position in a document's text is `(anchor, offset)`.

- **`anchor`** is the innermost element carrying an anchor that contains the point. That is a
  paragraph's `pn` where it has one, otherwise its section, and down to a table row or a
  `<dd>` wherever the model keeps one (`Block.anchors`). Not every block has an anchor.
  Authored XML gives paragraphs the RFC Editor's `pn`, but converted legacy documents build
  every paragraph without one (#491). The anchoring must not depend on paragraph anchors
  existing.
- **`offset`** counts Unicode scalars into that element's *model* text: the plain text of its
  inlines as RFCKit flattens them. It never counts in the text storage. The builder adds section
  numbers, list markers, chips and spacing, and a reading mode (#188) may hide things, and
  none of that may move a highlight.

`DocumentTextBuilder` already knows which storage range each block occupies. It also emits a
**position map** between storage offsets and model positions. That makes selection →
position and position → storage range pure functions of a `BuiltDocument`, which hold for
any build: the reader's at any column width, the print's, the export's.

### A target

```
Target
  .section(anchor)                      a note on a whole section
  .range(start, end, quote)             any span, possibly across blocks
Quote
  exact                                 the text the range covered
  prefix, suffix                        up to 32 characters either side
```

This follows the shape of the W3C Web Annotation selectors (a position selector with a text
quote selector as its fallback). "Note on this figure / table / paragraph" is a `.range` that
covers exactly that block.

### Relocation

`relocate(target, in: document) → .exact | .moved(Target) | .detached` is a pure function.

1. If the text at the stored position still matches `quote.exact`, it is `.exact`.
2. Otherwise it searches for the quote under the same anchor, then in the anchor's section,
   then in the whole document. It breaks ties with the prefix and suffix, and after that by
   nearness to the stored position.
3. When it finds the quote, the result is `.moved`. The corrected position is written back
   **once**, so relocation does not run again on every open. It also writes back a *finer*
   anchor when one now exists: a position stored under `section-4.2` becomes one under
   `section-4.2-3` once #491 gives legacy paragraphs part numbers. That needs no migration.
4. When nothing is found, the result is `.detached`. **A detached annotation is never
   deleted.** It is kept and shown apart, as "this passage no longer exists in this document".

A `.section` target relocates only by its anchor. It is detached when that anchor no longer
exists.

### The rows

The rows follow the collections precedent (`ARCHITECTURE.md`, "collections are rows linked by
identifier"). They are rows linked by identifier, never SwiftData relationships, and in
CloudKit's shape: nothing `@Attribute(.unique)`, every attribute optional or defaulted.
Uniqueness is the store's job. Every row is keyed on the document's `fileStem` as
`documentKey`.

- **`SchemaV5` `Highlight`**: `id` (UUID), `documentKey`, `startAnchor`, `startOffset`,
  `endAnchor`, `endOffset`, `quoteExact`, `quotePrefix`, `quoteSuffix`, `color` (a
  name from the palette, where `underline` is one of the names and draws a rule rather than a
  fill), `createdAt`, `modifiedAt`.
- **`SchemaV6` `Note`**: `id`, `documentKey`, *either* `highlightID` *or* its own target
  (`sectionAnchor`, or the same range and quote fields as a highlight), `body` (the archived
  `AttributedString`), `createdAt`, `modifiedAt`.
- **`SchemaV7` `NoteAttachment`**: `id`, `noteID`, `contentType`, `fileName`, `byteCount`,
  and `data` in `@Attribute(.externalStorage)`.

Orphans are kept, never deleted. Under sync, a note can arrive before its highlight and an
attachment before its note. A note whose highlight is missing shows as detached. The sweep with
a grace period that collections are waiting on (`ARCHITECTURE.md`) covers these rows too, and
belongs to the sync work.

Deleting a highlight that has a note asks first, then deletes both. Deleting a note deletes its
attachments.

### Where the code lives

- **`RFCReaderKit/Annotations`**: `Position`, `Target`, `Quote`, the position map's
  queries, `relocate`, merging, document ordering, gutter placement and card stacking, and
  both exports' pure halves. All of it is tested there.
- **`RFCReaderKit/UserData`**: the schema versions, `AnnotationStore` (every change)
  and `AnnotationSnapshot` (every read), mirroring `CollectionStore` and `CollectionSnapshot`.
  `LibraryModel` publishes the snapshot.
- **The app**: the text view wiring, the menus, the popover, sheet and column hosting, and the
  PDFKit calls.

## Slice 1: highlights

### Drawing: never in the storage

A highlight is **not** an attribute in the built text. A build is handed over and never
written to, and a kept build is installed into more than one text view (`CLAUDE.md`,
`BuilderHandoverTests`). Writing highlights into it would also mean a rebuild on every change.

- Each text view marks its highlights as **rendering attributes** on its own
  `NSTextLayoutManager`: a custom `.rfcHighlight` key whose value is the color name. Rendering
  attributes belong to the view, and they change how text is drawn, never its layout. Adding,
  recoloring or removing a highlight never re-wraps or rebuilds anything.
- `RFCTextLayoutFragment` reads them and draws a Books-style fill behind the line fragments,
  with gently rounded ends, continuous across the lines of one highlight. The underline style
  draws a thick rule under the baseline. Where the rects go is a `FragmentGeometry` function.
- **Risk to retire first:** it is unproven that a layout fragment can read its layout
  manager's rendering attributes while drawing off the main thread. The first task of slice
  1's plan is a throwaway probe. If it fails, the fallback is to draw the fills in a layer of
  the text view's own, beneath the text, from the same geometry.

### The palette

The palette is fixed and named, the way `CollectionColor` is: yellow, green, blue, pink,
purple, and an underline style. It is stored by name, so an older build reads a name it does
not know as the default. The fills are fixed sRGB per appearance, and each is checked with
`SRGBColor` so that text over it keeps a contrast of 4.5:1 in light and dark, the rule the
author monograms are held to.

### Making and changing one

- **Making:** select text, then choose Highlight. On the Mac it is in the context menu as a
  color row with the last-used color first, in Edit ▸ Highlight, and on ⌃⌘H (Books'
  shortcut). On iOS it is an item in the edit menu, with the same row. The selection snaps to
  word boundaries.
- **Merging:** a new highlight that overlaps an existing one merges with it into one highlight
  in the new color. If both have notes (slice 2), their bodies are joined in document order with
  a divider. Undo restores both.
- **Changing:** a click or tap inside a highlight without dragging opens a popover with the
  color row, Delete and Copy as Quote, and from slice 2 on, Add Note or Edit Note. Dragging
  still selects, and a link inside a highlight still opens.

### The Annotations inspector tab

It lists every highlight in document order, with its quote and its section. Clicking one scrolls
to its passage. Detached highlights are listed last. It follows the `RequirementsView`
pattern. From slice 2 on it lists notes too. Once the column exists, the column is the
in-context view and this tab is the overview, like Books' Notes panel.

### Accessibility

Rendering attributes are invisible to VoiceOver. The coordinator adds a **Highlights rotor**
and a "highlighted, yellow" hint to the ranges, beside its existing accessibility work.

### Not drawn

Print and PDF never draw highlights: print makes a build of its own, and the export
annotations are slice 5b.

## Slice 2: notes

### Starting one

- **From a selection:** Add Note makes a highlight in the last-used color and opens its note,
  the way Books does it.
- **From a highlight's popover:** Add Note, or Edit Note.
- **On a block:** Add Note to Figure / Table / Paragraph, from the context menu on that block.
  It targets a `.range` covering exactly the block, with no highlight.
- **On a section:** Add Note to Section, from the heading's context menu and from the
  section's row in the contents panel.

### Gutter markers

A small note glyph sits in the **trailing** gutter, level with the first line of its target.
The leading gutter is left for the hanging section numbers of #433. It shows on every
platform, and whenever the notes column is not showing.

- Where it goes is a pure `FragmentGeometry` function: target → storage range (position map)
  → first line fragment → y. Markers that would overlap stack. Slice 3's card solver reuses
  this placement for each card's desired y.
- Markers are views laid over the text view, not part of the storage, as the reference hover
  already is. The one-storage rule concerns the text. Being views makes markers clickable and
  visible to VoiceOver.
- Clicking or tapping a marker opens its note, or a short list first when several notes share a
  line.

### Where the editor opens

- **Mac:** a popover anchored to the marker or the highlight, sized for a few paragraphs, with a
  button to continue in the Annotations tab.
- **iOS:** a sheet at the medium detent, so the passage stays visible above it.
- **Slice 3:** the same editor view, in the column's card.

It is one editor view with three hosts.

### The editor

- SwiftUI `TextEditor` over `AttributedString`, with a **fixed attribute scope of the app's
  own**: bold, italic, underline, strikethrough, inline code, links, and bulleted and
  numbered lists. Anything else that is pasted in, such as fonts, sizes or colors, is stripped
  to that scope. The stored body stays small and every attribute has a Markdown export.
  Checklists wait until someone asks for them.
- **Risk to retire first:** it is not certain that `TextEditor` handles lists well. The first
  task of slice 2's plan is a probe. The fallback is a TextKit 2 `NSTextView`/`UITextView`
  with `NSTextList`, behind the same view.
- **Links:** ⌘K opens a field that takes a URL or anything that names an RFC —
  `RFC 9110 Section 4.2`, `9110#section-4.2`, an rfc-editor.org URL — parsed through the
  existing `RFCLink` code. A pasted rfc-editor.org or `rfc://` URL becomes a link by itself. A
  link to a passage of the same document scrolls there rather than opening a tab.
- **Saving:** it autosaves, debounced by about a second, and again when the editor closes. A
  note left empty is deleted when it closes. Undo is the text view's own.

The Annotations tab lists notes beside highlights, each showing its first line under its quote
or block. Clicking one scrolls to the passage and opens the editor.

## Slice 3: the notes column

### Where it lives: inside the reader's scroll view

The column is **not** a fifth split item. Its cards are laid into the text view's own trailing
area, beside the text container, with a hairline rule between them. They scroll with the text
because they are part of the scrolled content, so there is no scroll syncing, and none of the
window-width arithmetic of the split controller is touched.

### The width: `ReaderLayout` shares it

`ReaderLayout` takes three inputs: the reader's width, whether notes are shown, and the width
the contents panel covers. It returns the text measure, the column's x and the column's width
(about 280 pt).

- The text narrows only when the slack beside the capped measure does not already cover the
  column. When it narrows, it re-wraps once, on the toggle, and never while scrolling. This is
  one deliberate build. It is not the build-twice bug of a column reported back by the text
  view: the column is still derived from the reader's own width.
- **The panel pushes the notes.** With both open, text and notes fit into the width the panel
  leaves. With the notes column off, the panel is exactly as today: it covers slack, and the
  document re-wraps zero times when it opens. The rule in `ARCHITECTURE.md` gets that
  qualifier, "unless the notes column is showing". Nothing about `safeAreaRegions = []` or
  `ReaderScrollView`'s refused trailing inset changes.
- **No room:** below a threshold, where text plus column would push the measure under a
  readable minimum, `ReaderLayout` answers "no column", and the reader shows slice 2's gutter
  markers instead. A narrow window and iPad Split View fall back by themselves. On iPhone that is
  always the answer.

### Placing the cards: a pure solver

`stack(desired: [y], heights: [h], focused: index?) → [y]`:

- Cards keep document order and never overlap.
- A focused card, one being edited or whose highlight was just clicked, sits exactly at its
  desired y. The others are pushed above and below it, as comments are in Pages and Word.
- The desired y comes from slice 2's placement. The heights are measured by the card views and
  fed in. That is a callback into the *notes'* layout only, never into the text column's.
- Only cards near the visible range are realized as views. The solver runs over all of them.

### Cards

- Each card is collapsed to a few lines, with a "more" control. Clicking a card edits it in place.
- Hovering a card brightens its highlight. Hovering a highlight outlines its card.
- A section note sits at its heading. A detached note sits at its old section's heading if that
  still exists, otherwise at the top, and is marked detached.
- A highlight without a note gets no card.

### The toggle

View ▸ Show Notes (⌥⌘N) and a toolbar button. It is kept per window like the panel, and off
by default. While the column shows, the gutter markers are hidden.

## Slice 4: attachments

- **Adding:** drop, paste, or an Attach… button in the editor. Images show inline at the
  width of the note. Other files show as a chip with icon, name and size, and open in Quick Look.
- **Storage:** each attachment is a `NoteAttachment` row with its data in external storage. In
  the body it is an attachment character whose attribute carries only the row's id, so the text
  stays small and a sync of the text never carries a file.
- **Size:** a file over 25 MB is refused with a message.
- **Orphans:** an attachment whose note is missing is kept, and left to the sweep.

## Slice 5a: Markdown export

- One file per document. A front matter block gives the RFC number, the title and the date
  exported. The annotations follow in document order, grouped under their section headings.
- Each highlight is a block quote with a citation link, such as
  `[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)`, with its
  note under it. Section and block notes sit under their heading. Detached annotations come last,
  with their quotes.
- `rfc://` links in notes are rewritten to rfc-editor.org URLs, since the file leaves the app.
  Attachments go into a folder beside the file and are linked relatively. Without attachments
  the export is a single `.md` file.
- The text is a pure function from snapshot and document, in `RFCReaderKit`. It is a case in
  `ExportFormat` and in `DocumentExport`, the one switch every export goes through.

## Slice 5b: PDF export with annotations

- Export as PDF gets a toggle, Include Highlights and Notes. With it on:
  - each highlight becomes a `.highlight` or `.underline` markup annotation in its color, with
    its note's Markdown as the annotation's contents;
  - a section note becomes a text annotation at its heading.
- `shouldPrint = false` is set on every annotation, explicitly. Printing never adds annotations.
- It follows the link annotations of #376. The export build's position map gives each
  target's storage range, and the layout manager gives its line rects. Target → rects →
  annotation spec is a pure function in `RFCReaderKit`, beside `PDFExport.target(of:references:)`,
  and the PDFKit calls stay in `DocumentPDF+Export`.
- **Known limits:** a note's formatting is lost, because PDFKit exposes no API for PDF rich text
  (`/RC`) and Preview ignores it. Its links survive as text. The export is one way: edits made
  in another PDF app do not come back.
- **Probes before promising:** how the markup appears in Preview, and whether file
  attachments are feasible through PDFKit. Until the second is proven, attachments are left out
  of the PDF.

## Testing

- **Pure logic in `RFCReaderKit`**, with Swift Testing and raw-identifier test names: the
  position map, relocation, merging, gutter placement and stacking, the card solver,
  `ReaderLayout` with the column and the covered width, and both exports.
- **Relocation against real documents only**, through committed fixtures and
  `Corpus-backed:` suites:
  - a position made in the legacy parse of an RFC relocates into the authored XML of the same
    RFC;
  - positions survive a rebuild at another column width and in the print and export styles.

  No RFC text is committed. A test finds its passage at run time by a short locator.
- **Schema:** each version gets a migration test against a store written on disk.
- **Guards:**
  - `BuilderHandoverTests` gains a check that highlighting leaves the build untouched.
  - ``BuilderCompletenessTests.`nothing becomes an attachment` `` stays as it is, since
    nothing new enters the storage.
- **By hand on the Mac,** through AppleScript and AX reads, never synthetic keystrokes, on
  RFC 9110:
  - slice 1: highlighting leaves the layout identical, with zero differing pixels outside the
    fills;
  - slice 3: the column toggle re-wraps at most once, and with the column off, the panel still
    re-wraps zero times.
- **Docs:** each slice adds its dated decision to `ARCHITECTURE.md`:
  - slice 1: anchoring and relocation, and highlights as rendering attributes;
  - slice 3: the column inside the scroll view, and the qualifier on the panel's rule.

  `VISION.md`'s tier line is updated as the slices land.

## Out of scope

- Sync. The model is CloudKit-shaped, and turning sync on is the separate iCloud work.
- Pencil markup (`VISION.md`'s separate item).
- Reading annotations back out of a PDF.
- Checklists, fonts and colors in notes.
- Sharing, threads, or any second author.
