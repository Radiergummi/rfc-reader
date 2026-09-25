# Architecture

## Shape of the code base

```
rfc-reader/
├── Packages/RFCKit/          Swift package: everything that is not UI. Builds and tests on Linux and macOS.
│   ├── Sources/RFCKit/
│   │   ├── Models/           DocumentID, RFCMetadata, RFCIndex, enums for status/stream/format
│   │   ├── Index/            RFCIndexParser (streaming SAX), XMLTree (small DOM used by the document parser)
│   │   ├── Document/         RFCDocument model, RFCXMLParser (RFCXML v3), LegacyTextParser (plain text), RFCXMLSerializer
│   │   ├── Client/           RFCEditorEndpoints, RFCEditorClient (actor), RFCLink (URL scheme + web URLs), feed parser
│   │   ├── Citation/         CitationFormatter (short, full, Markdown, BibTeX, URL)
│   │   └── Search/           IndexSearch (in-memory metadata search with a small query grammar)
│   └── Tests/RFCKitTests/    Swift Testing suites with real fixtures (RFC 1149, 2119, 5234, 8999, index sample, RSS, JSON)
├── Tools/corpus-build/       Offline pipeline (fetch, convert to RFCXML, manifest); see DATA_PIPELINE.md
├── App/RFCReader/            SwiftUI multiplatform app (iOS, iPadOS, macOS)
│   ├── Model/                LibraryModel (@Observable app state), DocumentStore (actor, disk cache), SwiftData models
│   ├── Views/                Navigation, list, reader, table of contents
│   │   └── Rendering/        RFCTextView, RFCTextViewCoordinator, RFCTextLayoutFragment — one TextKit 2 text view over one document text storage
│   └── Intents/              App Intents (Open RFC)
├── project.yml               XcodeGen spec that produces RFCReader.xcodeproj
└── docs/
```

The split is the point: **RFCKit knows nothing about SwiftUI, and the app knows nothing about XML or the 72-column text format.** The boundary is the `RFCDocument` model. That keeps the hard, testable logic on a fast Linux/macOS test loop and lets the UI be rewritten (TextKit 2, a different navigation model, visionOS) without touching parsing.

## The document model

```
RFCDocument
├── header: DocumentHeader          title, id, authors, date, abstract blocks, keywords, obsoletes/updates
├── sections: [Section]             tree; each has anchor, number ("4.2", "A.1"), title: [Inline], blocks, subsections
└── source: .xml | .text

Block (indirect enum)
  paragraph(Paragraph)              inlines + optional anchor
  list(ListBlock)                   bullet / numbered(format, start) / bare; items hold blocks
  definitionList([DefinitionItem])  term inlines + definition blocks
  preformatted(Preformatted)        artwork or sourceCode, verbatim text, optional language
  figure(Figure) · table(Table) · blockQuote · aside
  references(ReferenceList)         bibliographic entries with resolved DocumentID where possible

Inline (indirect enum)
  text · emphasis · strong · code · superscript · subscript · link(URL) · crossReference · lineBreak

CrossReference.target
  .anchor(String)                          same document
  .document(DocumentID, section: String?)  another RFC, optionally a section
```

Design choices worth knowing:

- **Anchors are stable strings**, not indices. XML documents use the author's `anchor` or the RFC Editor's `pn` part number; text documents synthesise `section-4.2`, `appendix-A`, `name-security-considerations`, `ref-RFC2119`. Deep links, the table of contents and reading positions all key off these.
- **Cross references are resolved at parse time.** The XML parser indexes `<reference>` anchors first, so `<xref target="QUIC-TRANSPORT">` becomes `.document(RFC9000)`. The text parser does the same with `[RFC2119]`-style entries in the References section, then linkifies `[Anchor]`, `RFC 1234`, `Section 4.2 of [RFC9110]`, `Section 3` (only if that section exists) and URLs in prose.
- **A mention is linked in whatever spelling the document used.** `RFC 1156`, `RFC-1156` and `RFCs 734, 736 and 749` all name documents, and the series has written all three since the 1980s. The hyphen and the list were worth the patterns: measured over the corpus's prose, 1,640 mentions were of the plain shape, 2,223 hyphenated and 659 in lists. What the reference *reads* as is still not the parser's to decide — `isCanonicalTag` says `RFC 1156` is the series spelling its own name and composes back, while the hyphen in `RFC-1156` and the bare number in a list are the author's and survive verbatim.
- **Both parsers run `InlineLinker` over prose.** *Decided September 2026.* Marking up a citation is the author's choice, not the reader's: authored XML says "RFC 3986" in the middle of a sentence as readily as it writes `<xref>`, 160 times in RFC 9293 alone, and until the XML parser ran the same linker the whole post-8650 range showed those as plain text while the legacy range linked them. One linker, for the same reason there is one `isCanonicalTag`: two of them disagree, and the same reference then reads differently depending on which format it arrived in. It is suppressed exactly where the text is already a link (`<eref>`'s content) or is set as typed (`<tt>`, `<sourcecode>`, `<artwork>`, and every preformatted block, which never becomes inlines at all).
- **A heading is inlines, not a string.** *Decided September 2026.* Headings cite documents — "Changes from RFC 3066", "Differences from RFC 793", some 3,500 of them across the corpus — and a `String` title could not carry the link however well the linker worked. `Section.title` is `[Inline]`; `titleText` and `displayTitle` flatten it for the outline, and `displayTitleInlines` is what the reader draws. Anchors are built from the section number, not from the words. The number is never part of the words: it lives in `number` and the reader composes `4.2. ` around whatever the heading says, so the linker cannot mistake a heading's own number for a section reference.
- **Display text travels with the reference.** RFCXML's prepped output carries `derivedContent` ("Figure 1", "Section 4.2"); the parser reuses it rather than re-implementing numbering rules. The same goes for the bibliography: a `<reference>` carries the tag its citations print as `derivedAnchor` — `[HTTP]` for RFC 9110 under `<displayreference>`, `[1]` under `symRefs="false"`, half the modern series between them — and `Reference.displayAnchor` is that tag, while `anchor` stays the link key. The one thing it restyles is a bare canonical number (`RFC9110` → `RFC` + U+00A0 + `9110`); an author's own tag (`QUIC-TRANSPORT`) is left exactly as the document writes it.

## Parsing the two source formats

**RFCXML v3** (`RFCXMLParser`): the whole file is loaded into a tiny DOM (`XMLTree`) and walked. Documents are at most a couple of megabytes; RFC 9110 (1.2 MB, 305 sections, 1,376 paragraphs) parses in about 50 ms in a release build. Whitespace inside `<t>` is collapsed as HTML would; artwork and source code are kept byte-for-byte. `<artset>` picks the ASCII alternative until there is an SVG renderer.

**Legacy text** (`LegacyTextParser`), in order:
1. *Depaginate*: drop form feeds, `[Page N]` footers and the running header that follows a page break; remember where breaks were. Then drop the lines that recur at the page edges however they are worded (RFC 793's `Transmission Control Protocol`) — but only a line set off from the body by a blank and seen at the edges more often than inside the pages, because the body recurs too and a MIB's `STATUS current` lands at a page edge by chance. A line on half the pages names the document — half the pages of its parity, where headers alternate between facing pages (RFC 821). A section running header must head every page, or every other, of three or more. A line wrongly kept costs a stray heading; one wrongly dropped is lost text, so the rule errs towards keeping. `corpus/report.json` records each document's dropped lines as `furniture`, because the block counts cannot show that loss.
2. *Front matter*: the two-column header block (`Request for Comments: 1149`, `Obsoletes:`, `Category:`, authors, date) up to the first blank line, then the centred title.
3. *Headings*: any non-indented line. `1.2.` → numbered; `Appendix B.` / `B.1.` → appendix; anything else unnumbered. Depth from the number; sections nest with a stack.
4. *Blocks*: runs of lines separated by blank lines. A block is prose if every line shares a small indent and contains no artwork tell-tales (`+--`, `|`, `->`, runs of spaces); prose is reflowed. A block starting with `o`, `-`, `*`, `1.`, `(a)` becomes a list. Everything else is preformatted, minus common indent. Blocks cut by a page break are re-joined when both halves look like prose and the first half does not end a sentence; a trailing hyphen joins without a space. A block indented past a list's marker and carrying no marker of its own is that item's next paragraph: the indent cap is excused, because the list above says what the indent means, but every other test of prose still applies — and one of them has to be `readsLikeSentences`, or the algorithm steps and tagged values that fill those indents are swallowed into the item as prose.
5. *References*: `[Anchor] text…` entries with hanging indents; RFC/BCP/STD numbers, quoted title, date and URL are pulled from the text. An anchor may hold spaces (`[RFC 2119]`, `[Cheswick and Bellovin, 1994]`) and is capped at 40 characters, which is what separates a citation tag from a bracketed sentence.
6. *Boilerplate* ("Status of This Memo", "Table of Contents", copyright) is dropped from the model but stays in the "original text" view, which is `stripPagination(_:)` over the same file.

**Serializing back** (`RFCXMLSerializer`): the document model can be written out as RFCXML v3 using the RFC Editor's conventions (`pn` part numbers, anchors). This is how the corpus pipeline turns legacy text into XML once, offline, so the app needs only the XML path at runtime. Cross references to documents without a bibliography entry become `<eref>`s to rfc-editor.org, which the parser resolves back into document references; the round trip is tested on both a text-derived and a native XML document.

The index (`RFCIndexParser`) is different: 14 MB and flat, so it is a streaming SAX state machine rather than a DOM. About one second for ~9,850 entries.

Both XML parsers ignore a parser error reported *after* the root element has closed. swift-corelibs-foundation emits one on large inputs even for valid XML (verified with `xmllint`); a truncated file still fails because its root never closes, and there is a test for that.

## Data flow in the app

```
RFC Editor ──HTTP──▶ RFCEditorClient (actor) ──bytes──▶ DocumentStore (actor)
                                                          │  writes rfcNNNN.xml/.txt to Application Support
                                                          │  parses on demand, memoises RFCDocument
                                                          ▼
                       LibraryModel (@Observable, @MainActor) ── index, filter, search text, selection, pendingSection
                                                          ▼
                       SwiftUI views ── macOS: NSSplitViewController(sidebar, list, DocumentView, panel)
                                        iOS:   NavigationSplitView(sidebar, list, DocumentView)
                                                          ▼
                       SwiftData ── Bookmark, ReadingPosition (user data only; iCloud later)
```

- Legacy RFCs arrive pre-converted to XML through data packs (DATA_PIPELINE.md); on-device text parsing is the fallback when no pack is installed.
- Raw files are cached exactly as served. Re-parsing after a parser fix is free, and the "original text" mode needs no second download.
- The index is cached to disk and re-fetched in the background when older than a day; a bundled snapshot (drop `rfc-index.xml` into the app's resources) makes first launch work offline.
- Navigation is data: `LibraryModel.open(RFCLink)` sets `selection` and `pendingSection`; `DocumentView` scrolls once the document has loaded. The URL scheme handler, the App Intent, cross-reference taps and the status banner all go through the same call.
- Cross references render as `.link` attributes on an `AttributedString` with two private schemes (`rfc://…` for other documents, `rfc-anchor:…` for the same document). `DocumentView` installs an `OpenURLAction` that intercepts them; everything else falls through to the system.

## Testing

`swift test --package-path Packages/RFCKit` runs 65 Swift Testing cases in about 0.1 s on real fixtures: the full RFC 8999 XML, RFCs 1149, 2119 and 5234 as text, a trimmed index, the RSS feed and a per-RFC JSON record. Each parser has a truncated-input test. `swift test --package-path Packages/RFCReaderKit` (`make test-app`) runs 70 Swift Testing cases over the app-side package's own suite — `DocumentTextBuilder`, the chip and completeness guards, `FragmentGeometry`, `ReaderLayout`, platform helpers — against the same harness; it needs an Apple SDK, so it is not part of `make check`.

The App target has no test bundle of its own, so **nothing that can be tested is allowed to live there**. The rule that keeps this honest: anything in the reader that is a pure function of its inputs belongs in `RFCReaderKit`, and the App target keeps only what genuinely needs UIKit/AppKit object graphs — the two representables, the coordinator's view wiring, and drawing. Where a decoration goes (`FragmentGeometry`), how wide the column is (`ReaderLayout`) and what the text says (`DocumentTextBuilder`) are all in the package, under test. This is not cosmetic: both of the reader's hardest bugs were index arithmetic that had been written in the App target, where the only thing a test could do was re-implement it and check the copy.

CI (`.github/workflows/ci.yml`) runs `Packages/RFCKit`'s tests on both macOS and in a Linux Swift container; the macOS job also runs `make test-app` for `RFCReaderKit`. A third job builds the app itself, unsigned, for macOS and the iOS Simulator.

## Decision: TextKit 2 for the reader body

*Decided September 2026.* The reader's prose is rendered by `UITextView` / `NSTextView` with TextKit 2, not by SwiftUI `Text`. The wishlist needs link previews on hard press, hover popovers on Mac and find-in-document; SwiftUI `Text` built from an `AttributedString` handles link taps but cannot attach a per-link context menu or preview, and offers no in-document find. TextKit 2 does all of that (`textView(_:menuConfigurationFor:defaultMenu:)` and `primaryActionFor` on iOS 17+, link hover on macOS), scales to very long documents, and keeps selection across paragraphs.

`DocumentTextBuilder` is not main-actor bound. A build is string assembly, `CTLine` measurement and paragraph styles — it costs hundreds of milliseconds on the largest RFCs, and running it on the main thread is what made the font-size slider stutter. `DocumentView` builds in a detached task and `BuiltDocument` carries the result back; it is `@unchecked Sendable` on the strength of one invariant, that `build` copies its mutable working buffer on the way out so nothing mutable escapes.

The text column is a pure function of the view's width (`ReaderLayout`), which is why `DocumentView` derives it rather than being told by the text view. Artwork scaling and table shape are measured against the column at *build* time, so a column that arrives after the first build means a document built against a guess and immediately thrown away; deriving it up front means one build per document instead of two, and no visible re-scroll on open.

Shape: one `NSTextContentStorage` holds the whole document body — paragraphs, lists, definition lists, artwork, tables, figures, block quotes, asides and references are all text, built by `DocumentTextBuilder` in a new `RFCReaderKit` package and laid out by a shared `RFCTextViewCoordinator` behind a macOS `NSTextView` and an iOS `UITextView`. Nothing in the body becomes a hosted SwiftUI view; the decorations attributed text cannot express on its own — the card behind artwork and tables, the rule beside a block quote, the aside tint, the reference chip — are drawn by an `NSTextLayoutFragment` subclass instead. The document header is not in the storage: it is a SwiftUI view hosted in the text view's top content inset, because it carries buttons (the status banner's links to newer RFCs) that nobody selects through. `DocumentTextBuilder` replaces `InlineText.attributedString(_:)` and the per-block SwiftUI views that fed the old `LazyVStack`; `BuilderCompletenessTests.nothingBecomesAnAttachment` guards the "nothing becomes a hosted view" rule directly, failing on any `NSTextAttachment` outside the one chip run the design allows. See `docs/superpowers/specs/2026-09-21-textkit-2-reader-design.md` for the full design.

### Decision: the parsers do not decide how a reference reads

*Decided September 2026 (issue #6), replacing the baked-label note this paragraph used to
carry.* `CrossReference.text` holds only what the **source** said: the author's own words
inside an `<xref>`, or the tag the document uses for the reference (`QUIC-TRANSPORT`,
`[1]`). `nil` is the load-bearing value — it means nothing in the source dictates the
wording, so the label is ours to compose and ours to restyle. `isCanonicalLabel` is no
longer a stored flag both parsers set and could disagree about; it is `text == nil`.

The label is composed in one place, `CrossReference.label` for plain text and `.display`
for the reader, from the target plus `sectionFormat` (`of` / `comma` / `parens` / `bare`,
RFCXML's own wording, which the serializer now round-trips instead of writing a fixed
`of`). U+00A0 still joins each word to its number so a reference never breaks across a
line; that part is unchanged, it just happens once at the end rather than in four places
in two parsers.

Why it was worth undoing: the renderer had been recovering structure out of the baked
string by looking for brackets, and `isCanonicalTag` compared against `RFC9110` only.
Legacy prose linkifies a bare `RFC 95`, which is the series' own spelling with a space in
it — so the predicate called it an author's tag, and the bracket hunt found nothing to
strip. Measured over 1,200 corpus documents: **12,612 references, 253 of them chips**.
After: **2,902**. The remaining majority are labels like `[1]`, which genuinely are the
document's own name for the reference and must survive verbatim, since its own reference
list uses them.

`DocumentTextBuilder` draws a composed label as a chip: a leading `doc.text` glyph (the
one `NSTextAttachment` in the whole design) followed by a tinted rounded background
painted by `RFCTextLayoutFragment`, the whole run marked `.rfcChip` so the builder's
completeness test and the fragment's drawing code can both find it. `sectionFormat:
.bare` is the one composed shape that does not chip: it is the source asking for the
section number alone, which is a wording decision like any other.

This is the first app task after the Xcode project builds.

## Decision: per-tab navigation, and how a tab gets opened

*Decided September 2026.* A reference opens in its own tab on Command-click, in front with Shift; the conventions are the browser's, because that is what a reader's hands already know. What a click means is `LinkActivation`, and where it goes is `LinkDestination.resolve` — both in `RFCReaderKit`, because the App target has no test bundle and the three rules that make a click feel right are not obvious: an anchor never leaves the document whatever is held down, a section of the document already on screen scrolls instead of re-opening it, and that shortcut applies only when following in place. `LibraryModel.open(_:activation:in:)` is the single place an activation becomes an effect, so a Command-click means the same thing on a cross reference in the prose, a reference in the inspector and a button in the status banner. The document list is the one surface that does not join in: `List(selection:)` is handed the outcome rather than the click, and Command-click on a row is the platform's multi-select chord rather than ours to take.

**Superseded for macOS in September 2026 — see "Decision: the window layer is AppKit's on macOS".** A tab is now a `ReaderWindowController` the app delegate makes and joins with `addTabbedWindow(_:ordered:)`; `LibraryModel`'s latch works exactly as described below, because a window still cannot be handed a value as it is made. The paragraph below remains true of iOS and of why `openWindow` is not the answer.

**Neither `WindowGroup(id:)` nor `WindowGroup(for:)` can be used here** — measured, both leave the app running at launch with no interface at all, and the plain `WindowGroup` that does open a window cannot be handed a value. So a new tab comes from AppKit: `NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)))`, the same action behind the tab bar's own "+", which SwiftUI implements for a plain `WindowGroup`. Nothing can be passed along that path, which is why `LibraryModel` holds the link in a private latch for the scene that appears to take in `register(_:)`. A background tab is opened and then the previous window is made key again on the next turn of the run loop — the new tab is ordered front as part of being made, so taking focus back any sooner is simply undone by it. This is the part to re-read before reaching for `openWindow` again.

## Decision: the window layer is AppKit's on macOS

*Decided 22 September 2026, after four earlier attempts recorded in issue #34 and two more measured in `docs/superpowers/specs/2026-09-22-window-hijack-probe-results.md`.*

The contents panel must sit in the window the way Pages' inspector does: full-height glass, the **window tab bar** ending at the panel's leading edge rather than running under it, and the toolbar splitting at the same point. None of that is reachable from SwiftUI, because window chrome only engages for an `NSSplitViewController` that **is** the window's `contentViewController`. `.inspector` is not a split item at all — probed on the running app, the controller still reports three items with it showing — and an item added to SwiftUI's own controller is reconciled away.

Replacing a `WindowGroup` window's `contentViewController` looked like the cheap way in, and it is not: SwiftUI treats the scene as closed and opens a replacement window, which the installer replaces in turn — **24 windows in 0.9 s**, measured, with the scene's view tree parked, hidden, visible and spike-shaped. So macOS has no `WindowGroup`. `AppDelegate` makes every window; each is a `ReaderWindowController` holding a four-item split controller — sidebar, list, reader, inspector — with the existing SwiftUI views in `NSHostingController`s.

What this costs and what it does not: the menu bar is still SwiftUI's, because a `Settings`-only scene honours `.commands` (measured: the full `File`/`Edit`/`View`/`Window`/`Help` bar, with our own items in it). What `WindowGroup` used to contribute and we now write ourselves is New Window, New Tab, and the per-window state that `ContentView` held as `@State`. `@FocusedValue` does **not** survive: published from a hosted root it never resolves, and ⌘L opened nothing at all until the commands were pointed at the key window through `ActiveReaderWindow`.

The toolbar has a tracking separator on **all three dividers**, which is what gives each item a column to belong to: the sidebar's toggle over the sidebar, the title over the list it names, Back and Forward at the leading edge of the reader they act on, the document's actions at the reader's trailing edge, and the panel's toggle out on the panel's glass.

**The title and subtitle are a toolbar item of our own** (`titleVisibility = .hidden`), declared after Back and Forward. A window that draws its own title puts it in a block at the start of the document's toolbar section, and that block expands to fill — measured, it pushed Back and Forward from 204 pt out to 1199 on a 1500 pt window, with and without a subtitle. Two other ways out were built and rejected: the expanded toolbar style gives the title its own row and costs a second row of titlebar, with the sidebar's toggle dropping onto the sidebar's search field; a leading `NSTitlebarAccessoryViewController` is laid out over the sidebar and pushes the sidebar's toggle into the overflow menu. An ordinary item sits where it is declared and takes the width it needs. Like every custom view in a toolbar it must carry its own constraints — an intrinsic width alone left the title drawn on top of the navigation group — and it is `isBordered = false`, or the toolbar draws it as a button.

Three pieces of arithmetic are load-bearing, and each was got wrong first:

- **The window must not grow when the panel opens.** AppKit adds an uncollapsed inspector's thickness on top of `contentMinSize`, so a fixed 900 pt floor became 1222 and the window grew to meet it. The floor drops by the panel's width while the panel shows, which keeps the effective minimum constant.
- **The reader keeps its full width underneath, and two separate layers have to be told so.** The panel's width comes back as a right safe-area inset, and it does damage twice over. *In SwiftUI:* the width `DocumentView` derives its column from is read by a `GeometryReader` in the reader's hosted root, and a root that honours the inset reports 919 pt with the panel shut and 599 pt with it open — so `NSHostingController.safeAreaRegions = []` on that root is load-bearing, and holds it at 919 both ways with the view's own frame unchanged and the inset still arriving. *In AppKit:* a scroll view turns the same inset into content insets that the text view tracks — the scroll view stayed 1019 pt while the text view went to 699 and its column from 712 to 392 — and `safeAreaRegions` does not reach the clip view, nor does `ignoresSafeArea` from any level above it. `ReaderScrollView` refuses the trailing inset there, and only the trailing one: zeroing the insets outright puts the first lines of the document behind the toolbar. Neither fix substitutes for the other; removing either one re-wraps the document when the panel opens.
- **A hosted view must not size the window.** A hosting controller reports its content's preferred size, and as a split item that reaches the window: it pinned the window at 219 pt tall. `sizingOptions = []` on every hosted root.

**The panel follows the document, and a new tab will try not to.** A window ordered into a tab group adopts the group's inspector state, which left an empty strip of glass over a tab that had nothing open in it. Measured on this build: `isCollapsed` is still the one the controller set immediately after `addTabbedWindow(_:ordered:)`, and the sibling's immediately after the window is ordered front — so the adoption happens inside `makeKeyAndOrderFront(_:)`, and a tab opened in the background, which is never made key, never inherits at all. A correction made once the ordering call has returned holds, unchanged on the next turn of the run loop and a second later. `AppDelegate` makes it there, at the one place that creates a tab; everywhere else the rule is the document's own, observed on `ReaderState.hasDocument`. Enforcing it on `windowDidBecomeKey` instead works but is a recurring answer to a question only asked at creation.

The toolbar's items are AppKit's own. Hosted SwiftUI controls were tried first, to keep the declarations `DocumentView` already had, and an `NSHostingView` reports no width the toolbar will honour: every item drew on top of the one before it, the bookmark inside the back/forward group and the share icon over the panel's toggle.

Verified by measurement rather than by eye, on RFC 9110 in a 1500 pt window with a 320 pt panel: the tab bar ends at 1177 pt against a panel edge of 1180; window and reader unchanged at 1500 and 1019 across a toggle; column 712 both ways; **zero differing pixels** in the region the panel does not cover. Captures that disagreed with that turned out to be racing the reading-position restore — settle the document before diffing.

## Decision: a section is a fragment

*Decided September 2026.* The app's own scheme spells a section as a fragment and in the RFC Editor's shape — `rfc://9110#section-4.2`, `rfc://9110#appendix-A.1` — not as a path (`rfc://9110/section/4.2`) and not bare (`rfc://9110#4.2`). A section is a place within a document, not a document of its own, so it belongs in the fragment; and spelling it their way means one section names the same place whether the link points at our reader or at their HTML. `RFCLink.fragment(for:)` builds it and `RFCLink.section(fromFragment:)` parses it, kept together so the two halves cannot drift, and every URL builder in `RFCKit` goes through them. The prefix is required on both schemes: an unprefixed `#4.2` is not a section, and `#page-12` stays unrecognised rather than becoming one.

## Planned engines

- **Search.** SQLite FTS5 (via GRDB) with BM25 ranking, one row per section, over all abstracts plus every downloaded document; snippets from `snippet()`. Later, a hybrid reranker with `NLContextualEmbedding` vectors: per abstract for the whole index (precomputed pack, ~20 MB), per section for downloaded documents. Metadata search moves into the same database.
- **Highlighting.** A tokenizer per language (ABNF, JSON, HTTP messages, YANG, ASN.1, C-like) in RFCKit producing `[Token]` with kinds; the renderer maps kinds to colours. Heuristic language detection for legacy text (`rulename = ` lines → ABNF).
- **Diff.** Section alignment by title similarity and position, LCS over paragraphs within aligned sections, word-level diff (`CollectionDifference` or Myers) inside changed paragraphs. Output is a diff document rendered with the same block views plus insert/delete styling. Works for draft revisions and for obsoleted RFC → successor.
- **Diagrams.** Box-art to Unicode box-drawing conversion per block; packet-diagram parser producing a bit-field model rendered natively.

## Two TextKit 2 traps this reader already fell into

*Found September 2026, both by instrumenting a running build rather than by reading.*

**`NSTextContentStorage.attributedString = …` discards the backing `NSTextStorage`.** Assigning it is the obvious way to install a document and it renders perfectly, because TextKit 2 lays out and draws from `attributedString` alone. But `textStorage` goes nil, and with it everything AppKit still routes through the text storage: dragging computed a correct selection and threw it away at mouse-up, and `clickedOnLink` never fired. The reader could be read but not selected, copied or clicked, with no error anywhere. Install through `storage.textStorage?.setAttributedString(_:)`.

**`attribute(_:at:effectiveRange:)` returns the storage run, not the attribute's run.** It stops at *any* attribute change, so a stacked table's bold label and regular value are separate runs even though both carry the same `.rfcDecoration`. Every fragment then reported itself as both the first and last fragment of its decoration, drawing a fully rounded card at its own indent — the staircase down the page that artwork, tables and authors' blocks all showed. `longestEffectiveRange:in:` is the one that coalesces. Two corollaries: the value has to be `String`-backed to compare equal across insertions (`RFCDecoration.attributeValue`), and every character of a block has to carry it — an undecorated separator newline splits the run just as effectively as a missing attribute.

## Known gaps and the next technical steps

- Legacy text: definition lists with hanging indents (e.g. the cache directives in RFC 2616 §14.9.1) render as preformatted blocks; nested lists are flattened; multi-author front matter picks up only authors that sit on their own line.
- Search: ~70 ms per query over the full index, in memory. Run it off the main actor with a short debounce for now; move to SQLite FTS5 (GRDB) when full-text search over document bodies lands, and let the same index serve metadata search.
- SVG artwork (`<artwork type="svg">`) is skipped in favour of the ASCII alternative.
- No Spotlight indexing, iCloud sync, errata or Datatracker integration yet; the client has the endpoints, the model has the fields.
- The reader still lays out the whole document body, but no longer in one pass: `install` lays out the first 20,000 characters synchronously and the rest in slices of the same size with a turn of the run loop between them (issue #9, September 2026). One pass measured 547 ms of frozen interface on RFC 5661; the first slice measures 12 ms, and the click-to-readable stall on that document fell from ~708 ms to ~204 ms, the remainder being SwiftUI's own update and first draw. The full layout is still what the reader runs on — a stable content size, exact anchor → y — it just arrives about a second later, and until it does `laidOutEnd` is nil, which `scrollContainerTopTo` already reads as "do not clamp". The one case that still pays up front is a jump: a deep link or a restored reading position lays out everything above its target before scrolling, because an un-laid-out fragment has no y (~450 ms for a section near the end of RFC 5661).
- `CrossReference.isCanonicalLabel` is recomputed on reparse rather than persisted: `RFCXMLSerializer` writes neither the flag nor `derivedContent`, so it can diverge when a source document's `derivedContent` differs from its own reference anchor. The legacy corpus-build path is safe and has a test; issue #6's layering change would dissolve this gap entirely (issue #10).
- Copying a reference chip puts U+FFFC on the pasteboard and loses the bracket delimiters, so adjacent references (`RFC 9110 RFC 9111`) run together in copied text instead of staying separated the way the chip's tint separates them on screen (issue #11).
- VoiceOver still reads artwork character by character during ordinary swipe-through reading; only a Diagrams rotor for jumping between artwork blocks was added, not a spoken-through replacement (issue #12).
