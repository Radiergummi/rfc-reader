# A document's index, and a searchable Contents tab

Design, 2026-10-05. Four parts that ship separately, in the order 1 → 2 → 3 → 4.

## Why

RFC 9110 ends in a long Index appendix: letter groups of terms, each with the sections that mention it, the defining one in bold. Read as body text it is a wall of links. This makes it read and work as an index: typeset as one, with a sticky letter, an A–Z rail and type-select. It also gives the legacy RFCs that have an index working links, which today they lack, since their entries point at page numbers and the reader has no pages.

The Contents tab is the other half of the same need, finding a place in a long document, and gets a filter and an A–Z order.

## How many documents (measured 2026-10-05, over `corpus/`)

- **RFCXML, 6 of 1,378:** 9051, 9110, 9111, 9112, 9114, 9499. They are the only RFCXML documents that use `<iref>` at all; prep generates the index from them (anchored `rfc.index.index`), with 58 to 460 terms each.
- **Legacy text, about 27 of 8,457**, with a heading line reading `Index`: 1034, 1035, 1045, 2629, 3536, 3648, 3744, 3986, 4601, 5015, 5323, 5585, 5598, 5842, 5854, 5995, 6365, 7230–7235, 7749, 8499. Not indexes, though their heading matches: 2616 and 1506 (a pointer to the PostScript version), 3159 (a grammar), and 6241, 8526, 8527 (lists of capability URNs, with no locators). A heading spelled otherwise ("Index of Terms") is missed, so 27 is a floor.

Few documents, but among the most read: HTTP, URI, DNS, IMAP.

## Constraints this design keeps

- The reader body is one text storage. Nothing interactive goes inside it: the index is text that `DocumentTextBuilder` sets, and everything interactive is an overlay drawn over the scroll view, or lives in the inspector.
- RFCKit knows nothing of SwiftUI, and the app nothing of XML: the index is a model block, which the builder sets from the model.
- Anchors are stable strings.
- Pure functions live in RFCReaderKit, under test; the App target keeps wiring and drawing.
- No RFC text is committed. No new fixtures; the XML side is tested at guard level and over the corpus.
- Legacy indexes are a class of documents, so they are recovered by a heuristic, not by overrides. An override restructuring an index would also have to carry its terms, which is RFC text the overrides may not hold.

---

## Part 1: The Contents tab

**What changes.** `TableOfContentsView` gains a filter field and an order, as the Requirements tab has a filter.

- **Filter:** a `TextField` above the list. It matches a section's title or its number (`4.2`), case- and diacritic-insensitive. In document order a match keeps its ancestors, shown dimmed, so the hierarchy still reads. No match shows `ContentUnavailableView.search`.
- **Order:** Document Order or A–Z, in a picker beside the field. A–Z flattens every level, sorts by title with the number set aside (shown as a trailing caption), and groups by first letter under pinned letter headers, as Contacts does (`LazyVStack(pinnedViews: .sectionHeaders)`, the same on both platforms). The order is remembered app-wide. Z–A is left out: nobody looks a section up backwards.
- The current section stays marked, by weight and by `.isSelected`, in either order.

**Where.** `ContentsOutline` in RFCReaderKit, after `RequirementList.Filter`: the filter, the A–Z sort and the grouping, as functions of the sections, the text and the order. The view only shows what it returns.

**Tests.** `ContentsOutline` over hand-built `Section` values: number and title matching, folding, ancestors kept and marked as context, A–Z ordering with numbers ignored, grouping under digits and letters.

**Out of scope.** Index terms in the Contents tab: the index is part 3's, and merging the two would blur them.

---

## Part 2: The index in the model, from RFCXML

**Model.** A new case `Block.index(IndexBlock)`, after `Block.references(ReferenceList)`:

```swift
public struct IndexBlock: Sendable, Hashable, Codable {
  public var groups: [Group]

  public struct Group: Sendable, Hashable, Codable {
    public var label: String     // "A", "1"
    public var anchor: String    // "rfc.index.u65"
    public var entries: [Entry]
  }

  public struct Entry: Sendable, Hashable, Codable {
    public var term: [Inline]
    public var locators: [Locator]
    public var subentries: [Entry]
  }

  public struct Locator: Sendable, Hashable, Codable {
    public var reference: CrossReference
    public var isPrimary: Bool
  }
}
```

- A locator is a `CrossReference`, so it resolves, previews and links as every other one does. Its label is the xref's `derivedContent` ("Section 9.3.1"); the builder shortens it.
- An entry without locators heads its subentries (`Grammar` → `ALPHA`, `Accept`).
- Group anchors are prep's own (`rfc.index.u65`). Entry-level `pn` anchors are dropped; nothing links to them. The section keeps its anchor and its place in the table of contents.
- Groups and entries keep the source's order, which is sorted.

**XML parser.** A `<back>` section whose first `<t>` is anchored `rfc.index.index` is read as one `IndexBlock` in place of its generic blocks:

- the `<t>` of letter buttons is dropped (the A–Z rail replaces it);
- each `ul > li` is a group: its `<t anchor>` gives the anchor, and the label is the character whose code point the anchor names (`rfc.index.u65` is `A`), since that `<t>` is empty;
- each `dt`/`dd` pair of the group's `dl` is an entry; each `xref` in the `dd` a locator, primary when wrapped in `<strong><em>`; a `dl` nested in a `dd` holds the subentries.

Anything outside that shape leaves the whole section as generic blocks, as it reads today. The reader is a static function over an `XMLTree.Element`, reachable from tests.

**Serializer.** Writes an `IndexBlock` back in prep's shape: the anchored `<t>`, a `ul > li` per group with its anchored `<t>`, a `dl` of entries, the primary locator in `<strong><em>`, subentries in a nested `dl`. Parse, write, parse is a fixed point (`SerializerRoundTripTests`). Part 4 depends on it.

**Builder until part 3.** Sets the block as a plain nested list, so nothing reads worse in the meantime and `BuilderCompletenessTests` holds.

**Tests.**

- Guard-level, over hand-written elements in prep's shape: a group and its anchor, a primary and a secondary locator, a heading entry with subentries, the letter paragraph dropped, the fallback on a stray element.
- `Corpus-backed: index` over the six documents, added to `CORPUS_TEST_XML_DOCUMENTS`: each parses to an `IndexBlock`; every locator resolves to an anchor its document declares; the round trip is a fixed point. Places are found by locators of a word (`Grammar`), never by quoting.

**Out of scope.** Feeding the block into `definedTerms` (#455) and the defined-term intent (#730), which the block makes easy later.

---

## Part 3: The index in the reader

### Layout, in `DocumentTextBuilder+Index.swift`

- **Group label:** the letter on a line of its own, small, tracked and secondary, not heading chrome. It carries the group's anchor, and is a heading to accessibility, so the rotor steps through letters.
- **Entry:** the term, then its locators on the same line as in-document section links shortened to `§9.3.1`, the primary first and semibold. A wrapped line hangs under the term. No dot leaders and no right-aligned column: on a phone-width column both wrap badly and add ink, not information. Links, not chips: a chip is another document.
- **Subentries:** one indent step under their heading entry.
- **`IndexMap`**, recorded into `BuiltDocument` by the build: each group's label and text range, each entry's folded match key (case- and diacritic-insensitive) and text range. The overlays read it; nothing searches the text.

### Overlays, drawn by the App target from pure functions in RFCReaderKit

All three show only while the index section intersects the visible text, and not while it is folded.

- **Sticky letter.** The current group's letter pinned at the top of the text area, pushed out by the next group's label as Contacts does.
  - *Current group:* the group whose range holds the top visible text location. It needs no layout of text off screen.
  - *Offset:* from the next label's fragment frame, when that is on screen.
- **A–Z rail.** The labels of the groups present. On macOS in the trailing margin beside the column, clear of the scroller; on iOS at the trailing edge, as `UITableView`'s section index. Tapping or dragging scrolls to the group's anchor through the existing scroll request. One adjustable element to VoiceOver.
  - *Hit-testing:* which label a point falls on.
- **Type-select.** While the reader's text view is first responder and the index is visible, an unmodified key extends a buffer that resets after about a second, as `NSTableView`'s does, and the reader scrolls to the first entry whose key starts with the buffer, or else to the next entry in order, and flashes it. Space joins only a buffer that holds something; otherwise it pages as it does now. macOS: `ReaderTextView.keyDown`. iOS: hardware keyboards, `pressesBegan`; touch has the rail.
  - *Matching:* `IndexTypeSelect`, the buffer and the entries' keys to an entry.

### Tests

- Builder, over a hand-built `IndexBlock` value: the text, the locator links and their targets, the primary's weight, `IndexMap` ranges against the text.
- `BuilderCompletenessTests` unchanged: no attachments are added.
- Current group, sticky offset, rail hit-testing, `IndexTypeSelect`: unit tests.
- The wiring by hand, with RFC 9110, on the Mac and in the Simulator.

### Out of scope

A filter that hides entries in the body, and a sort order for it; ⌘F already searches the document, and an index is in A–Z order by definition. Printing and the PDF export set the layout without overlays.

---

## Part 4: Legacy indexes

### The shapes (sampled 2026-10-05)

| Shape | Documents | Locators |
|---|---|---|
| letter group lines, entries indented under them | 5598, 7230–7235 | pages, ranges `13-14` |
| groups apart by blank lines only | 1034, 1035 | pages |
| subentries one or two levels deeper | 5598, 7749 | pages |
| dot leaders | 4601, 5015 | pages, `27,128` without spaces |
| `term -- 4.1` | 3536 | sections |

### Recognition

A section titled exactly `Index` is an index when most of its lines classify as one of:

- a group label: a single letter or digit alone on a line;
- an entry: a term, then two or more spaces or a dot leader, then a locator list;
- a heading entry: a term without locators, followed by entries indented deeper.

Groups apart by blank lines only take their label from their terms' first letter. Anything else stays generic: the PostScript pointers, the capability lists of 6241, 8526 and 8527, whatever the corpus run turns up.

### Locators

- **Sections:** any `--` form, or dotted numbers, resolve to section anchors as `Section 3` in prose does.
- **Pages:** depagination already sees every page break and `[Page N]` footer. It records, per page, the block holding that page's first line, and that block gets the anchor `page-N` — stable, since the text is frozen. A block that already has an anchor keeps it, and the locator uses that. A range points at its first page. The serializer writes `page-N` as an ordinary `anchor` on the `<t>`, so the round trip holds.
- **Validation:** a page past the document's last, or a section it does not have, leaves the whole section generic. A wrong link is worse than none.

### Overrides

None planned. A single document the heuristic cannot reach may still get a patch under `corpus/overrides/README.md`'s rules; a shape that recurs is a parser fix.

### Process

The `legacy-parser-change` workflow:

- guard-level tests of the line classifier over hand-written lines in RFC shape, never quoted;
- `Corpus-backed: legacy index` over one document per shape — 1034, 5598, 7749, 3536, 4601, 7230 — and 2616 and 6241, which must stay generic; added to `CORPUS_TEST_DOCUMENTS`;
- a full corpus run before and after, compared in `corpus/report.json`. Expected: those documents gain an `IndexBlock` and `page-N` anchors, and nothing else moves.

### Out of scope

Resolving "RFC 1034, page 12" citations through `page-N` anchors, which this makes possible.

---

## Decision records

Each part records its decision in `docs/decisions/` when it lands, with its measurements: part 2 the index block and why prep's anchor is the recognizer, part 3 why the index has overlays and type-select but no filter, part 4 the page anchors and why legacy indexes are a heuristic and not overrides.
