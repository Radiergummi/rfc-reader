# Artwork renderers — design

*30 September 2026. Approved in brainstorming, section by section. Covers the architecture for
rendering artwork and source code as native figures and styled text, slice 1 (the foundation and
packet diagrams) in detail, and slices 2–7 as a roadmap. Each slice gets its own implementation
plan. Grows out of #31, whose remaining items stay bug fixes on today's verbatim path; relates to
#47 (packet recognizer, landed as #441), #48 and #49 (traced diagrams), #45/#393 (ABNF), #46
(offline classification), #361, and #12/#308 (VoiceOver).*

## Why

Every verbatim block is set the same way today: monospaced, never wrapped, scaled to fit the
column, on a card (`DocumentTextBuilder.appendVerbatim`). That works for every block and helps
with none. A packet header is a grid of fields with names and widths. A grammar is rules that
refer to each other and to other RFCs. A YANG tree is an outline. Drawn as ASCII, none of that
structure is available to link, to announce, or to read at a glance.

The goal is renderers for the kinds of artwork RFCs actually contain, starting with the rigid
formats, and an architecture where adding a new format is cheap: a recognizer or a declared type,
a layout, a registration, and tests. There is no time pressure; the architecture matters more than
the first renderer.

## What the artwork is

A census over the 9,835 local XML documents (8,457 converted legacy, 1,378 authored): 409,000
verbatim blocks in 8,692 documents. The classifier was a throwaway signature script, so these are
orders of magnitude, not measurements to cite.

| Family | Kinds | Blocks | Docs |
|---|---|---:|---:|
| Formal languages | MIB/SMI, ASN.1, ABNF (and RBNF, CDDL, TLS presentation, XDR), YANG modules and tree diagrams | ~45k | ~2.3k |
| Data and messages | XML, JSON, CBOR diagnostic, HTTP and SIP messages, header-style messages, DNS zone data, hex dumps and test vectors | ~18k | ~2.2k |
| Code | code, pseudocode, shell sessions | ~45k | ~3.5k |
| Structured drawings | packet diagrams (9.4k with a bit ruler, 1.2k without), trees and hierarchies, tables | ~37k | ~5k |
| Free drawings | box-and-arrow, sequence and message flow, arrows without boxes, state diagrams | ~10k | ~2.5k |
| Math | formulas | 2.1k | 754 |
| Authored vector art | SVG | 429 | 72 |

The remaining ~240k blocks, in the converted documents, are not artwork: prose, definition lists,
fragments of MIB modules, set verbatim by the legacy parser. That is the conversion pipeline's
concern (#496), not the renderers'.

The authored series declares its own block types: 43 `<sourcecode type>` values, led by
test-vectors, json, pseudocode, http-message, asn.1, yangtree and abnf. Drawings are the
exception. They are nearly all `<artwork type="ascii-art">` or untyped; authors have used
`call-flow`, `hex-dump` and `drawing` only a handful of times.

## Decisions

- **Renderers assume valid, well-annotated RFCXML.** Legacy structure is the conversion pipeline's
  concern. When a converted document renders badly, the fix belongs in `LegacyTextParser` or an
  override (#197), not in a renderer.
- **Rendering is stateless.** A rendering is a pure function of the block, the reading style and
  the column. Nothing derived from an RFC's text is stored or shipped, so the renderers raise no
  licensing question (docs/DATA_PIPELINE.md, #215).
- **Renderers dispatch on `type` only.** A renderer declares the `type` values it handles. It never
  guesses whether a block is its kind. All guessing happens in one place, the classify stage, which
  can be measured against the corpus.
- **A drawn figure takes its own size, and the source is one toggle away** ("Show Source"). The
  figure is not forced into the ASCII's proportions, and a figure that renders wrong has an escape
  hatch.
- **The contract carries links and accessibility from the first renderer**, and leaves room for
  stateful interaction (collapsing, stepping) later.
- **Failure is always the ASCII.** A renderer may decline a block, and a declined block is set
  exactly as today.

## Architecture

```
parsed document
   │  1. classify   RFCKit, pure: decides each verbatim block's type
   ▼
Preformatted (type + text)
   │  2. render     RFCReaderKit, pure: registry → renderer(block, context) → Rendition?
   ▼
Rendition (styled text, or a figure)
   │  3. present    App target, generic: draws any figure; knows no format
   ▼
screen, print, PDF
```

Adding a format touches stages 1 and 2 only. The App target draws a small, fixed vocabulary of
primitives and never changes per format. That also keeps the standing rule intact: everything
testable lives in RFCReaderKit, and the App target keeps only drawing.

### 1. Classify

`ArtworkClassifier` in RFCKit, pure and Linux-clean. It runs on the parsed document before the
build, inside the same `@concurrent` build function, so it stays off the main actor. For each
verbatim block, the first of these that applies sets `type`:

1. **An entry in the hint pack.** Hints are reviewed, so they win.
2. **A specific type from the author or the pipeline.** Anything other than empty or `ascii-art`.
3. **An exact recognizer.** `PacketDiagram.recognize` assigns `packet`. A recognizer either
   proves the block is its kind or claims nothing.
4. **Otherwise the type is left as it is**, and the block is set as verbatim.

The **hint pack** is a table from `(RFC number, text hash)` to a type, and optionally a few small
parameters that the ASCII leaves ambiguous (a state machine's initial state, which way time runs).
It holds no text from any figure. It ships through the existing pack channel (`DataPack`) and
starts empty.

The hash is 64-bit FNV-1a over the block's text with newlines normalized and trailing whitespace
trimmed from each line. A plain hash keeps RFCKit free of CryptoKit, and scoping it by RFC number
makes collisions irrelevant. Keying by content rather than position is deliberate:

- Converted documents have no stable IDs for their artwork; any ID would move as the conversion
  pipeline improves. Authored artwork has a `pn`, but a key that works for one series and not
  the other would split the mechanism.
- **A content key fails safe.** When the pipeline changes a block, its entry stops matching and the
  block falls back to recognition or verbatim. It can never land on the wrong figure.

The converter may also write a type into its output directly, which is valid RFCXML: `type` is free
text with preferred values. The hint pack is then mainly for the authored series, whose XML is not
changed.

### 2. Render

A registry in RFCReaderKit maps `type` values to renderers. A renderer is a set of types and a
function:

```swift
protocol ArtworkRenderer: Sendable {
  static var types: Set<String> { get }   // e.g. ["abnf", "abnf9110", "rbnf"]
  func render(_ block: Preformatted, context: RenderContext) -> Rendition?
}
```

`RenderContext` carries the reading style, the column after indentation, and the lookups a
renderer needs to make links (the document's anchors and cross-reference targets). A renderer
returns nil to decline: a packet grid that cannot fit the column at a readable label size declines.

`appendVerbatim` asks the registry first and falls back to today's path when no renderer claims
the block, when it declines, or when the reader has asked for the block's source.

### The Rendition contract

```swift
enum Rendition {
  case text(StyledText)   // attributed runs, set into the storage
  case figure(Figure)     // drawn, at its own size, into space reserved in the storage
}

struct Figure {
  var size: CGSize              // measured against the column at build time
  var primitives: [Primitive]   // box, line, path with arrowheads, text run
  var regions: [Region]         // hit areas
  var source: Preformatted      // for Show Source, Copy Figure and a selection's copy
}

struct Region {
  var frame: CGRect
  var link: LinkTarget?              // the same targets a text link carries
  var accessibilityLabel: String?    // "Source Port, 16 bits, bits 0 to 15"
  var identity: String?              // stable within the figure; keys later interaction state
}
```

- **Styled text** is for formats whose rendering is still text: syntax highlighting, grammar rules
  as links, a tree as an outline, message headers as a table. It stays selectable and findable.
- **Figures** are for formats that have to be drawn: packet grids, railroad diagrams, and later
  state machines and sequence diagrams.
- **Colors and fonts are roles** ("field label", "rule", "accent"), resolved at draw time. Dark mode
  and accent changes stay a redraw, not a rebuild, as they are for the rest of the storage.
- **Links are regions.** A field name or a rule name links to what it names, so "everything is a
  link" holds inside figures, and hover previews and force-click reuse the existing machinery.
- **Accessibility comes from regions.** Each region can be an accessibility element with its own
  label. That is the structural fix for #12 and #308 on both platforms, rather than saying
  "Diagram" in place of the drawing.
- **`identity` is the room for stateful interaction.** A later renderer that collapses a subtree or
  steps through a sequence keys its state by region identity, as Show Source keys by block hash.
  v1 carries the field and uses it for nothing.

### 3. Present

A figure occupies one paragraph in the storage, carrying `.rfcFigure` (the figure, boxed, as
`.rfcVerbatim` boxes a `Preformatted` today). The paragraph's line height reserves the figure's
height, and `RFCTextLayoutFragment` draws the primitives into it. There is no attachment, so
``BuilderCompletenessTests.`nothing becomes an attachment` `` keeps guarding the rule unchanged.

The reserved paragraph is laid out from one placeholder character, not U+FFFC. A selection across
it copies the figure's source, through the same path Copy Figure uses (`FigureCopy`).

**Show Source.** The reader keeps, per document and for the session, the hashes of blocks shown as
source. It is offered in a figure's context menu and as a menu command. Toggling rebuilds the
document with those blocks set as verbatim and keeps the reader's place through `ReadingPlace`, as
a change of column does. Two identical blocks in one document toggle together; that is accepted.
The state is not persisted in v1.

**Print and PDF** lay out with the same `RFCTextLayoutFragment`, so figures print as the reader
shows them.

## Testing

- **RFCKit:** guard-level tests of the classifier's precedence, over hand-written blocks in the
  shape of RFC artwork and never quoted from one. The hash's normalization is pinned the same way.
  A corpus-backed suite runs classification over authored XML.
- **RFCReaderKit:** each renderer's layout as a pure function: figure size, primitive placement,
  region frames and hit-testing, following `FragmentGeometry`'s tests. Builder tests that a figure
  reserves exactly its height and carries its source, that Show Source yields today's verbatim
  output byte for byte, and that a declining renderer does too. `nothing becomes an attachment`
  stays the guard.
- **App target:** drawing only, verified by hand against the #16 checklist.

## Slice 1: the foundation and packet diagrams

The heaviest slice on purpose: it builds all the shared machinery against the case that already
has a model (`PacketDiagram`, #441), so the risky part is met first.

1. **Probe the reserved paragraph.** Before anything else, measure that TextKit 2 lays out one
   placeholder line at an arbitrary height without disturbing fragments around it, on macOS and
   iOS, and that selection, section tracking and `ReadingPlace` behave across it. The rest of the
   slice depends on this; if it fails, the design returns to brainstorming.
2. **Classify stage** with the precedence above, the hash, an empty hint pack read from the pack
   channel, and `PacketDiagram.recognize` as the first recognizer.
3. **Registry and contract**: `ArtworkRenderer`, `RenderContext`, `Rendition`, `Figure`,
   `Primitive`, `Region`.
4. **Presentation**: `.rfcFigure`, the reserved paragraph, generic drawing in
   `RFCTextLayoutFragment`, region hit-testing and hover in the coordinator, accessibility elements
   for regions on macOS and iOS.
5. **Show Source and Copy Figure** for figures.
6. **The packet renderer**: a grid of fields over a bit ruler, variable-length fields drawn as such,
   declining when the column cannot hold readable labels. Regions for every field, with
   accessibility labels.
7. **Fields linked to their definitions**, last and the first thing to cut: matching a field to the
   `<dt>` that defines it needs anchors on definition terms, which RFCXML does not always give.

## Roadmap

Each is its own plan, and should be "a recognizer or type, a layout, a registration, tests".

2. **ABNF as styled text.** The text path of the contract, on the existing `ABNF` parser: rule
   definitions become anchors, references become links, core rules link to RFC 5234.
3. **Data formats as styled text.** JSON, XML, HTTP and SIP messages, CBOR diagnostic, highlighted
   from their declared `sourcecode` types.
4. **YANG tree diagrams** as an outline, collapsible once stateful interaction exists.
5. **Hex dumps and test vectors** as a byte-grid figure, with copy as bytes.
6. **Railroad diagrams** for grammars, the second figure renderer, on slice 2's parse.
7. **Each its own spec, later:** sequence diagrams (a lifeline layout), state machines (where the
   layout engine is chosen: ELK in JavaScriptCore, Graphviz's C library, or a layered layout in
   Swift; never a web view), traced free-form drawings (#48, #49), SVG, the classification pipeline
   below, and the review mode.

## Classification in the corpus stages

Not needed for slices 1–6, whose blocks are claimed by an exact recognizer or a declared type. It
becomes necessary with the free-form renderers, which need untyped drawings labeled. Recorded now
so the classify stage and the hint pack are built to receive it.

- **It runs in the corpus stages, never on end-user devices.** A `corpus-build classify` stage
  produces the hint pack. The app only reads it.
- **Candidates** are blocks with no specific type that no exact recognizer claims.
- **Producers are pluggable** and each returns a type with a confidence: a prompted model (Jev's
  Choice primitive, a Claude-class API, Apple Foundation Models on the build Mac), or a classifier
  trained on the corpus. Training labels for rigid kinds come free from recognizers and declared
  types; labels for free-form kinds come from model labels a person has checked on a sample.
- **Acceptance:** a label for a rigid type is kept only if that type's renderer accepts the block.
  A label for a free-form type is kept only above a confidence threshold calibrated on the test
  set, and after a spot-check. Anything below the bar stays unlabeled and renders as ASCII.
- **Train and test are split by document, after deduplication by hash**, because figures are
  copied between RFCs, and a slice of each era is held out, because legacy and authored art differ.
- **The provider is chosen by benchmark** against a hand-labeled sample of drawings, when the
  pipeline's own spec is written.

## Review mode, later

A debug build of the app in which the maintainer reviews renderings in place and records a verdict
per figure: accept, reassign to another renderer, or decline. A verdict is exactly a hint-pack
entry (hash to type, or to "none"), so the review mode writes the same artifact the corpus stage
does, and it is where a model's suggestion for a free-form drawing gets confirmed. It gets its own
spec.

## Rejected

- **Pre-generated graphs (dot or similar) shipped in packs.** A graph carries the figure's labels
  and structure, which makes it an adaptation of the artwork and puts it with the synthetic RFCXML
  awaiting the IETF Trust (#215). It would be a second source of truth that can disagree with the
  ASCII undetected, and it saves nothing where it counts, since layout still has to run at runtime
  for the column, text size and appearance.
- **Keying hints by position.** Converted documents have no stable artwork IDs, and a positional
  key lands on the wrong block when the pipeline changes.
- **Renderers that recognize their own kind.** Dispatch would depend on registration order, and
  guessing would be spread over every renderer instead of measured in one place.
- **The figure drawn over the source at the source's size.** Keeps find and selection inside the
  figure, but forces every figure into the ASCII's proportions, which suits packet grids and
  nothing else.
- **The figure out of the flow with no way back to the source.** A figure that renders wrong would
  have no escape hatch.
- **A model at runtime.** Rendering must give the same result for the same block on every device.

## Open questions

- **Hint labels and the licensing question.** #46 decided that even labels wait for the IETF
  Trust's answer before anything is committed. Hash-keyed labels carry no RFC text; whether they
  may ship before #215 is answered is the maintainer's call, recorded on #46. Slice 1 ships an
  empty pack, so it does not wait on this.
- **Jev's terms.** Pricing, data handling and the calibration of its confidences are not in its
  introduction. They matter only when the classification pipeline is specified.
