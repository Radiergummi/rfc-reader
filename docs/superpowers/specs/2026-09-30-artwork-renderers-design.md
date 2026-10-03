# Artwork renderers — design

*30 September 2026. Approved in brainstorming, section by section, then revised after four
adversarial reviews (strategy, TextKit feasibility against the code, extensibility of the contract,
data and licensing). Covers the architecture for rendering artwork and source code natively, slice 1
(the foundation and packet diagrams) in detail, and later slices as a roadmap. Each slice gets its
own implementation plan. Grows out of #31, whose remaining items stay bug fixes on today's verbatim
path; relates to #47 (packet recognizer, landed as #441), #48 and #49 (traced diagrams), #45/#393
(ABNF), #46 (offline classification), #197 (overrides), #361, #496, and #12/#308 (VoiceOver).*

*Amended 2 October 2026 by the syntax highlighting design (`2026-10-02-syntax-highlighting-design.md`):
the styled-text rendition is `Rendition.styled`, not `.text`; colors are stored in the text as dynamic
colors at build time, as every other color the builder sets is, rather than as roles resolved at draw
time; and highlighted code is outside the presentation choices — "Draw diagrams" and "Show as Text"
are about drawings.*

## Why

Every verbatim block is set the same way today: monospaced, never wrapped, scaled to fit the
column, on a card (`DocumentTextBuilder.appendVerbatim`). That works for every block and helps with
none. A packet header is a grid of fields with names and widths. A grammar is rules that refer to
each other and to other RFCs. A YANG tree is an outline. Drawn as ASCII, none of that structure can
be linked, announced, or read at a glance.

The goal is renderers for the kinds of artwork RFCs contain, starting with the rigid formats, and an
architecture where adding a format is cheap: a type or a recognizer, a layout, a registration, and
tests. There is no time pressure; the architecture matters more than the first renderer. The
maintainer, as a reader, wants rendered figures over ASCII; that is the premise, not a hypothesis to
test first.

## What the artwork is

Measured over the 9,835 local XML documents: 8,457 converted from legacy text by `corpus-build`, and
1,378 authored. Packet counts are the real `PacketDiagram.recognize`; the other kinds come from a
throwaway signature script and are orders of magnitude.

**Authored series** (what the renderers are designed against):

| Kind | Blocks | Source of its type |
|---|---:|---|
| Declared source code and data (43 `sourcecode type` values: test-vectors, json, pseudocode, http-message, asn.1, xml, yangtree, abnf, …) | ~7,200 | the author |
| Packet diagrams the recognizer claims | 972 in 236 docs | recognizer |
| Packet-shaped diagrams it declines (`~` fields closed by `|`, short first rows, `+--+` cells, notes beside the grid, 3-column spacing) | ~450 | none yet |
| Trees and hierarchies | ~890 | none |
| Box-and-arrow | ~550 | none |
| Sequence and message flow | ~390 | none |
| SVG (in `<artset>`) | 429 in 72 docs | the author |

All 1,580 free-form drawing candidates are untyped `ascii-art`. Only 200 block texts recur in more
than one document.

**Converted series:** the recognizer claims 4,728 packet diagrams in 1,026 documents. The "formal
language" blocks there are mostly MIB modules cut into fragments (31,814 blocks in 449 documents);
about 240,000 blocks are not artwork at all but prose and lists the legacy parser set verbatim. Both
are the conversion pipeline's concern (#496), not the renderers'.

## Decisions

- **Renderers assume valid, well-annotated RFCXML.** A converted document that renders badly is fixed
  in `LegacyTextParser` or by an override (#197), not in a renderer.
- **Renderers store nothing.** A rendering is a pure function of the block, the classification, the
  reading style and the column.
- **Renderers dispatch on a canonical type only.** They never guess whether a block is their kind.
  All guessing happens in the classify stage, where it can be measured.
- **Text first.** A rendering stays text in the storage wherever the format allows. Find, selection,
  copy, links, hover, VoiceOver and print pagination then keep working through the reader's
  existing machinery. An opaque drawing is used only for formats that cannot be text.
- **Every block has a presentation choice**, one of which is always the source ("Show Source").
- **Failure is always the ASCII.** A renderer may decline a block, and a declined block is set
  exactly as today. A renderer also never drops a line: what it does not render is set as verbatim.

## Architecture

```
parsed document  +  hint table (bundled)
   │  1. classify   RFCKit, pure: a classification per verbatim block, beside the model
   ▼
blocks + classifications
   │  2. prepare    RFCReaderKit, pure: each renderer reads all blocks of its types once per build
   │  3. render     RFCReaderKit, pure: registry → presentation → Rendition?
   ▼
Rendition: styled text, decorated text, or (later) a drawing
   │  4. present    App target, generic: draws strokes and drawings; knows no format
   ▼
screen, print, PDF
```

Adding a format touches RFCKit and RFCReaderKit only. The App target draws a small, fixed vocabulary
and never changes per format, which also keeps the standing rule: everything testable lives in
RFCReaderKit.

### 1. Classify

`ArtworkClassifier` in RFCKit, pure and Linux-clean. It **annotates rather than rewrites**: it returns
a side table from each verbatim block's position in document order to a classification, and the
model's `type` is left as parsed. Rewriting `type` would change the source-code label the reader
prints and leak into the converter's output.

```swift
struct ArtworkClassification {
  var canonicalType: String?      // nil: set as verbatim
  var parameters: [String: String]
}
```

**Canonical types.** RFCKit owns the normalization: lowercased, media-type parameters split off
(`message/http; msgtype="request"` → `message/http` with a parameter), and an alias table (`CDDL` →
`cddl`). A set of generic types means "no type": `ascii-art`, `drawing`, `ascii`, `text`, `plain`,
`none`, and empty.

**Precedence**, first that applies:

1. A hint that says `none`: the block is set verbatim.
2. A specific type from the author, or written by the conversion pipeline.
3. A hint's type, where the block's own type is generic.
4. An exact recognizer: `PacketDiagram.recognize` gives `packet`. A recognizer proves the block is its
   kind or claims nothing.
5. Otherwise no type.

**Hints are for the authored series only, keyed by `(RFC number, pn)`.** Every authored artwork carries
a `pn`, which the parser already puts into `Preformatted.anchor`, and a published RFC never changes,
so the key is permanent. This is the key #46 chose. The hint table ships **bundled with the app** and
versioned with it, since authored RFCs are fetched one at a time and never arrive through a pack. At
full coverage it is well under 100 KB. It starts empty.

**Converted documents take no hints.** Their blocks will keep changing as #496 improves the parser,
and a position- or content-keyed table would go stale silently. Instead the converter writes a type
into its output, which is valid RFCXML since `type` is free text, and one-off corrections are #197
patches, which fail loudly when they stop matching.

**Every build classifies the same way.** The classification and the hint table are inputs to
`DocumentTextBuilder`, so the reader, force-click previews, print and export agree.

### 2. Prepare and 3. render

A registry in RFCReaderKit maps canonical types to an **ordered list of presentations**. ABNF will have
styled text and later a railroad diagram; YANG an outline and later a diagram.

```swift
struct RendererEntry: Sendable {
  var types: Set<String>
  var presentations: [Presentation]           // in order of preference
  var prepare: (@Sendable ([Preformatted], RFCDocument) -> RenderFacts)?
}

struct Presentation: Sendable {
  var id: String                              // "packet-grid", "abnf-links", "railroad"
  var render: @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition?
}
```

- **Registration is one array literal.** Swift has no static self-registration. A test fails when two
  entries claim a type.
- **Prepare runs once per build** over every block of the entry's types, before anything is emitted.
  Grammars define rules in one block and use them in others; knowing that a name is a rule, and its
  anchor, needs all of them first. The builder already works this way for references
  (`referenceAnchors`, collected before emitting).
- **`RenderContext`** carries: the reading style with fonts resolved, the column after indentation, a
  maximum height (a page's content height in paper builds, unbounded on screen), a text measurer backed
  by CoreText (available off the main actor), the prepared facts, and link targets. Cross-document
  links reach a section (`Target.document(id, section:)`), not an anchor inside another document; that
  is accepted.
- **A presentation may decline** by returning nil, and the next one is tried, down to the source.
- **Wide and tall blocks:** each presentation states its policy: reflow, scale down to a minimum readable
  size that the context gives, or decline.

`appendVerbatim` consults the registry and falls back to today's path.

### The Rendition contract

```swift
enum Rendition {
  case text(StyledText)          // attributed runs
  case decorated(DecoratedText)  // styled text on its monospace grid, with strokes drawn over it
  case drawing(Drawing)          // designed here, built with the first format that needs it
}
```

Common to all of them:

- **Every rendition carries the block's `VerbatimBox`**, as verbatim text does today. Copy Figure, the
  captions `appendFigure` tags, quote grouping, the card, and the Diagrams rotor keep working.
- **Anchors a renderer creates are declared** in the rendition (a rule definition's anchor at its
  offset), and the builder `mark`s them, so they enter the anchor index like any other.
- **Fonts are resolved at build time**, because layout measures them. **Colors are roles** ("rule",
  "field label", "accent"), resolved at draw time through the reader's color set, so dark mode and
  print's light appearance are a redraw, not a rebuild.
- **Nothing is lost.** A rendition accounts for every source line: a renderer that reads only part of
  a block (`PacketDiagram` stops at the first blank line) returns the rest to be set verbatim. A
  builder test checks it.

**Styled text** is for formats whose rendering is text: highlighting, grammar rules as links, headers
as a table. Links are ordinary `.link` runs.

**Decorated text** is the workhorse for the rigid drawings: packets, and later YANG trees, hex dumps,
ASCII tables. The block is set as text on its monospace grid, exactly as today and scaled the same
way. The characters that draw borders are hidden (a clear foreground), and the fragment draws real
strokes in their place:

```swift
struct DecoratedText {
  var text: StyledText
  var hidden: [NSRange]           // border characters
  var strokes: [Stroke]           // in grid coordinates: (column, line)
}

struct Stroke {
  var from: GridPoint, to: GridPoint
  var style: Style                // solid, dashed (a variable-length field's edge), rule
}
```

Grid coordinates are independent of font and scale, so strokes are pure data a test can assert on.
Where they land in points is a pure function in RFCReaderKit, next to `FragmentGeometry`, from the
monospace advance and each line's position. Every line of a verbatim block is its own paragraph, so
each fragment draws the part of each stroke in its own line. Field names stay characters: find matches
them, selection and copy take the ASCII, a field can be a link, VoiceOver reads the text, and a long
block splits across printed pages line by line.

**Drawing** is for formats that cannot be text: railroad diagrams, state machines, SVG. It is an opaque
figure with its own size, reserved in the storage by one placeholder paragraph, with regions for links
and accessibility. It is designed here so the contract does not have to change, and **built in the
slice of the first renderer that needs it**, behind the probe described there. What a drawing gives up
is recorded now: find does not reach text inside it, a selection across it copies its source, and on
iOS it can be only one accessibility element. Named `Drawing` because `RFCKit.Figure` is already the
`<figure>` block.

### 4. Present

For decorated text, `RFCTextLayoutFragment` draws the strokes of the lines it holds, inside the card,
with the stroke color resolved at draw time. Strokes crossing from one line fragment to the next meet
at shared edges, which is where #31's seams came from; strokes are opaque lines, not translucent fills,
so they compose.

### Presentation choice and Show Source

The reader keeps, per document and for the app's session, the presentation chosen for each block that
is not on its default. It lives in `LibraryModel`, keyed by `DocumentID` and block position, because a
`DocumentSession` is dropped when the reader goes back. It is part of the build inputs and not of
`ReadingStyle`, which keys the preview cache. A change rebuilds the document and keeps the reader's
place through `ReadingPlace`. A decorated block and its source have the same text length, so the place
does not drift. Print and export honor the choice; force-click previews use the defaults.

It is offered in the block's context menu and as a menu command. The state is not persisted in v1.

### Accessibility

Decorated and styled text are read as text. For a classified block, `AccessibleReading` reads the
classification instead of guessing with `looksLikeDrawing`, and a packet diagram gets a spoken summary
from its model (its fields, their widths). That is macOS, through the per-range accessors
`ReaderTextView` already overrides. iOS has no per-range hook, and a `UITextView` cannot host child
elements without losing text reading, so iOS stays with #308 and its own design.

## Testing

- **RFCKit:** guard-level tests of normalization and precedence, over hand-written blocks shaped like
  RFC artwork, never quoted from one. A corpus-backed suite over authored XML pins how many blocks each
  path classifies.
- **RFCReaderKit:** every presentation as a pure function: its text, hidden ranges and strokes in grid
  coordinates; stroke placement in points; declining. Builder tests: a rendition carries its box;
  declared anchors reach the anchor index; no source line is lost; the source presentation equals
  today's output byte for byte; a declining presentation falls through. `nothing becomes an attachment`
  and `BuilderHandoverTests` stay the guards.
- **App target:** drawing only, verified by hand against the #16 checklist.

## Slice 1: the foundation and packet diagrams

1. **Classify stage:** canonical types, aliases and generic types, precedence, the side table, an empty
   bundled hint table, and `PacketDiagram.recognize` as the first recognizer.
2. **Registry, prepare and render:** `RendererEntry`, `Presentation`, `RenderContext`, `Rendition`
   with `text` and `decorated`.
3. **Decorated text in the fragment:** hidden border characters, stroke geometry in RFCReaderKit,
   drawing in `RFCTextLayoutFragment`.
4. **Presentation choice and Show Source**, in `LibraryModel`, through the build inputs.
5. **The packet presentation:** field borders and row separators as strokes, variable-length fields
   dashed, the bit ruler in a secondary color. Whatever follows the diagram in the block is set
   verbatim.
6. **Accessibility on macOS:** `AccessibleReading` reads the classification; packets get a spoken
   summary.
7. **Fields linked to their definitions**, last and the first thing to cut: it needs anchors on the
   `<dt>` terms that define fields, which RFCXML does not always give.

**Slice 1b: broaden the packet recognizer** to the ~450 authored diagrams it declines, one shape at a
time, each pinned by a corpus-backed test. More recognizer shapes, not the pipeline, are what reach
them.

## Roadmap

Each is its own plan: a type or recognizer, a presentation, a registration, tests.

2. **ABNF as styled text.** On the `ABNF` parser, made public and reporting token spans. Prepare
   collects each document's rules; definitions become anchors and uses become links; core rules link
   to RFC 5234.
3. **Data formats as styled text.** JSON, XML, HTTP and SIP messages, CBOR diagnostic, from their
   declared types.
4. **YANG tree diagrams** as decorated text, collapsible once stateful interaction exists.
5. **Hex dumps and test vectors** as decorated text, with copy as bytes.
6. **Drawings, and railroad diagrams as the first.** Builds the `drawing` rendition, after a probe on
   macOS and iOS, over RFC 793 and RFC 9000 with 200, 600 and 3,000 pt drawings, measuring:
   1. exact line and fragment heights, with the neighbors' frames unchanged;
   2. drawing with the placeholder glyph scrolled out, a widened `renderingSurfaceBounds`, and after a
      change of appearance;
   3. stable `laidOutEnd` and anchor positions across install's 20,000-character layout slices;
   4. selection through a drawing (drag, double-click, select all, the iOS handles);
   5. plain, rich and quote copies across one;
   6. region hit-testing (a pure `DrawingHitTest`) and the hover popover's anchor;
   7. VoiceOver, and whether an `NSTextView` can expose child elements;
   8. section tracking and `ReadingPlace` across a resize and a presentation change;
   9. print, with a drawing just under a page and one over;
   10. the cost of a presentation change on RFC 5661 and RFC 9000.

   A presentation declines a drawing taller than the context's maximum height, so paper never clips
   one. Region links become PDF link annotations.
7. **Each its own spec, later:** sequence diagrams, state machines (where the layout engine is chosen:
   ELK in JavaScriptCore, Graphviz's C library, or a layered layout in Swift; never a web view),
   traced free-form drawings (#48, #49), SVG, the classification pipeline, and the review mode. SVG
   needs a model change first: `<artset>` keeps only the ASCII today, and `parseArtwork` flattens an
   inline `<svg>` to text, so `Preformatted` has to carry its alternatives.

## Classifying free-form drawings

Not needed for slices 1–6, whose blocks are typed by their authors or claimed by a recognizer. It
becomes necessary with the free-form renderers, which need the ~1,580 untyped authored drawings
labeled.

- **Every label that ships is a human verdict.** At that size, review is hours, not weeks. A model
  may suggest a label to the reviewer; it never decides one.
- **Nothing ships from a model directly, and pack builds never call one**, so builds stay reproducible
  when a hosted model changes underneath.
- **No model for the rigid kinds.** A label for a rigid type is only accepted if the renderer's own
  recognizer agrees, so a model adds nothing there. Recognizer coverage is the lever.
- **Providers are compared by benchmark** (Jev's Choice primitive, a Claude-class API, Apple Foundation
  Models on the build Mac, a classifier trained on the corpus), against a hand-labeled sample split by
  document after removing duplicate texts, with each era held out. That matters only for choosing
  which model makes suggestions.
- **Where verdicts go:** authored documents, the hint table; converted documents, the converter or a
  #197 patch.

## Review mode, later

A debug build in which the maintainer reviews renderings in place and records a verdict per block:
accept, reassign to another type, or decline. For an authored document a verdict is a hint-table entry;
for a converted one it is a candidate #197 patch. It is where a model's suggestion is confirmed. Its
own spec.

## Licensing

- Renderers store nothing and ship nothing derived from an RFC.
- **The hint table ships with the app and is not gated on #215.** An entry is an RFC number, a `pn`
  and a type of our own: no text from the document at all. *Maintainer's decision, 30 September 2026*,
  narrowing #46's "nothing is committed until #215", which remains for anything that carries text.
- Types the converter writes ship inside the converted XML, which is already gated on #215; they add
  nothing to that question.

## Rejected

- **Content-hash-keyed hints.** Authored artwork already has a permanent key in its `pn`, and for
  converted documents a content key goes stale silently as the parser improves, where a #197 patch
  fails loudly.
- **Hints shipped through the pack channel.** Authored RFCs never arrive through a pack.
- **A packet diagram as an opaque drawing.** It would give up find, selection, link hit-testing,
  VoiceOver on iOS and page splitting, for a format that is already a monospace grid.
- **Pre-generated graphs (dot or similar) in packs.** A graph carries the figure's labels and structure,
  so it is an adaptation of the artwork and waits with the converted XML on #215. It would be a second
  source of truth that can disagree with the ASCII undetected, and layout would still run at runtime.
- **Renderers that recognize their own kind**, or one renderer per type. Dispatch would depend on
  registration order, and a type could not have more than one presentation.
- **Rewriting the model's `type` in the classify stage.** It would change the printed source-code label
  and leak into the converter's output.
- **A drawing forced into the ASCII's size.** Suits packet grids, which are decorated text instead,
  and nothing else.
- **A model at runtime, or in pack builds.**

## Open questions

- **Jev's terms:** pricing, data handling, and how well its confidences are calibrated. They matter
  only when suggestions for the review mode are specified.
