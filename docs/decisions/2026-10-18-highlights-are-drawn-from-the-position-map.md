# Highlights are anchored to the model text and drawn from the position map

*18 October 2026, #522, slice 1 of the highlights and notes design (`docs/superpowers/specs/2026-09-30-highlights-and-notes-design.md`, #528).*

## Positions count in the model text

A highlight stores where it starts and ends as `(anchor, offset)`, the offset counting Unicode scalars into the anchor's **model text**, never the storage's. The storage adds section numbers, list markers, a chip's attachment character and word joiner, a stacked table's labels, an aside's caption, and it changes with the column: a table is a grid or stacked, a folded block unfolded or as published. None of that may move a highlight. `ModelText` defines the model text element by element as the design's table does, as one string for the whole document in which every anchor is a range, the anchors nested; a section's text holds its heading and its own blocks, not its subsections, which follow it.

`DocumentTextBuilder` records a `PositionMap` as it appends: runs of storage characters that are runs of model characters, and the model text a build hides (a join the storage set as something else, a stacked table's header row, a folded block's header, the label an aside's caption replaced). Two traversals have to agree, the builder's and `ModelText`'s, and `PositionMapTests` is the guard: over four fixtures, at a phone's column, a wide one and paper's, every model character is mapped once or hidden, a mapped character is the model's character, and model → storage → model comes back. Every section start puts the builder's cursor back on its section's span, so a drift the guard missed costs one section, not the rest of the document.

The design asked for `FoldedLines` to gain an offset map for the unfolded display. A verbatim block's displayed text differs from its published text by more than its folds: tabs expanded, trailing white space trimmed, source code's shared indent removed. So the builder aligns the two by the shortest edit instead (`PositionMap.alignment`), line by line where neither changes the number of lines, the whole block where an unfolding did. It covers all three with one rule.

A storage range maps to the hull of the model characters it holds, so a selection that starts on a section number starts at the heading's first word. A model range is drawn as one shape where only the storage's own characters lie between its pieces (`drawnRanges`), so a highlight across a heading and its paragraph is one fill.

## Relocation

`Relocator` finds a target again: exact where it was, and then re-expressed under the innermost anchor holding it now (a block that gained an anchor); otherwise its quote with its prefix or suffix (both, for fewer than 12 characters), under the same anchor, in its section, then in the whole document. One match is `moved`, several `ambiguous`, none `detached`. Everything is compared normalized (white space, soft hyphens, line-end hyphenation, `[RFC2119]`/`RFC 2119`/`RFC2119`), with a map back to raw offsets. A cut quote's length and digest are of the normalized covered text, as every other comparison is, so a change of white space does not detach it. A relocation is written to the relocated fields only, never to where the highlight was made, and without touching `modifiedAt`. A corpus-backed suite relocates passages of RFC 9110's legacy parse into its authored XML: 39 of 40 found, none elsewhere than the same words.

## Drawn per text view, never in the build, and not as rendering attributes

A build is handed over and may be installed into more than one text view (`BuiltDocument`, `BuilderHandoverTests`), so a highlight is never written into it. The design chose rendering attributes on each text view's `NSTextLayoutManager`, read by the fragment at draw time, behind a probe. The probe, run as a test against an `NSTextView`, found two things:

- `enumerateRenderingAttributes(from:reverse:)` clips the first run it returns at `from`, so a fragment cannot learn where a highlight that began before it started; the value had to carry the extent.
- `invalidateRenderingAttributes(for:)` **drops every rendering attribute added** in the range. `ReaderLayoutEngine.redraw()` calls it over the whole document whenever Implementer's bands arrive or the palette changes, and `NSTextView` may call it itself, so highlights held there would vanish without a sound.

So the marks are held where Implementer's requirement bands already are: in the text view's `FoldingDelegate`, behind its lock, and the fragment reads them at draw time, never into its cache. Every other rule of the design holds: nothing in the storage, one set per text view, placed again after every install from the new build's position map, drawn translucent beneath the text, and inside widened drawing bounds. A fill is a requirement band's shape (`FragmentGeometry.bandRects`): one rect a line, joined, with rounded outer corners; an underline is a rule under each line's piece of the glyphs. The fill is translucent so a selection shows through it, and blends with a card under it; text over it keeps 4.5:1 on the page and every card in both appearances. A link over it keeps 3.5:1, not 4.5:1: the most opaque fill that held a link to 4.5:1 contrasted 1.05:1 with white, too faint to find a highlight by.

Placement (relocation and the drawn ranges) runs off the main actor, once per build and set of highlights, as finding Implementer's bands does. A translation's build draws none, its sentences not being the original's.

## Rows

`Highlight` is `SchemaV6`'s, in CloudKit's shape, keyed on the document's `fileStem`, identified by `identifier` (not `id`, which `PersistentModel` has). A new highlight merges with every one it overlaps; the oldest survives in the new color. Every change is undoable through `AnnotationStore`, which puts back every row as it was. A document with a highlight is pinned against eviction as a bookmarked one is.
