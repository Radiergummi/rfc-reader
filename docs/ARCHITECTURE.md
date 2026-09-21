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
├── sections: [Section]             tree; each has anchor, number ("4.2", "A.1"), title, blocks, subsections
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
- **Display text travels with the reference.** RFCXML's prepped output carries `derivedContent` ("Figure 1", "Section 4.2"); the parser reuses it rather than re-implementing numbering rules. The one thing it restyles is a bare canonical number (`RFC9110` → `RFC` + U+00A0 + `9110`); an author's own tag (`QUIC-TRANSPORT`) is left exactly as the document writes it.

## Parsing the two source formats

**RFCXML v3** (`RFCXMLParser`): the whole file is loaded into a tiny DOM (`XMLTree`) and walked. Documents are at most a couple of megabytes; RFC 9110 (1.2 MB, 305 sections, 1,376 paragraphs) parses in about 50 ms in a release build. Whitespace inside `<t>` is collapsed as HTML would; artwork and source code are kept byte-for-byte. `<artset>` picks the ASCII alternative until there is an SVG renderer.

**Legacy text** (`LegacyTextParser`), in order:
1. *Depaginate*: drop form feeds, `[Page N]` footers and the running header that follows a page break; remember where breaks were.
2. *Front matter*: the two-column header block (`Request for Comments: 1149`, `Obsoletes:`, `Category:`, authors, date) up to the first blank line, then the centred title.
3. *Headings*: any non-indented line. `1.2.` → numbered; `Appendix B.` / `B.1.` → appendix; anything else unnumbered. Depth from the number; sections nest with a stack.
4. *Blocks*: runs of lines separated by blank lines. A block is prose if every line shares a small indent and contains no artwork tell-tales (`+--`, `|`, `->`, runs of spaces); prose is reflowed. A block starting with `o`, `-`, `*`, `1.`, `(a)` becomes a list. Everything else is preformatted, minus common indent. Blocks cut by a page break are re-joined when both halves look like prose and the first half does not end a sentence; a trailing hyphen joins without a space.
5. *References*: `[Anchor] text…` entries with hanging indents; RFC/BCP/STD numbers, quoted title, date and URL are pulled from the text.
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
                       SwiftUI views ── NavigationSplitView(sidebar, list, DocumentView)
                                                          ▼
                       SwiftData ── Bookmark, ReadingPosition (user data only; iCloud later)
```

- Legacy RFCs arrive pre-converted to XML through data packs (DATA_PIPELINE.md); on-device text parsing is the fallback when no pack is installed.
- Raw files are cached exactly as served. Re-parsing after a parser fix is free, and the "original text" mode needs no second download.
- The index is cached to disk and re-fetched in the background when older than a day; a bundled snapshot (drop `rfc-index.xml` into the app's resources) makes first launch work offline.
- Navigation is data: `LibraryModel.open(RFCLink)` sets `selection` and `pendingSection`; `DocumentView` scrolls once the document has loaded. The URL scheme handler, the App Intent, cross-reference taps and the status banner all go through the same call.
- Cross references render as `.link` attributes on an `AttributedString` with two private schemes (`rfc://…` for other documents, `rfc-anchor:…` for the same document). `DocumentView` installs an `OpenURLAction` that intercepts them; everything else falls through to the system.

## Testing

`swift test --package-path Packages/RFCKit` runs 65 Swift Testing cases in about 0.1 s on real fixtures: the full RFC 8999 XML, RFCs 1149, 2119 and 5234 as text, a trimmed index, the RSS feed and a per-RFC JSON record. Each parser has a truncated-input test. `swift test --package-path Packages/RFCReaderKit` (`make test-app`) runs 64 Swift Testing cases over the app-side package's own suite — `DocumentTextBuilder`, the chip and completeness guards, platform helpers — against the same harness; it needs an Apple SDK, so it is not part of `make check`. The App target itself (the two representables, the coordinator, the layout fragment) has no test target of its own; there is no Xcode test bundle in `project.yml`.

CI (`.github/workflows/ci.yml`) runs `Packages/RFCKit`'s tests on both macOS and in a Linux Swift container; the macOS job also runs `make test-app` for `RFCReaderKit`. A third job builds the app itself, unsigned, for macOS and the iOS Simulator.

## Decision: TextKit 2 for the reader body

*Decided September 2026.* The reader's prose is rendered by `UITextView` / `NSTextView` with TextKit 2, not by SwiftUI `Text`. The wishlist needs link previews on hard press, hover popovers on Mac and find-in-document; SwiftUI `Text` built from an `AttributedString` handles link taps but cannot attach a per-link context menu or preview, and offers no in-document find. TextKit 2 does all of that (`textView(_:menuConfigurationFor:defaultMenu:)` and `primaryActionFor` on iOS 17+, link hover on macOS), scales to very long documents, and keeps selection across paragraphs.

Shape: one `NSTextContentStorage` holds the whole document body — paragraphs, lists, definition lists, artwork, tables, figures, block quotes, asides and references are all text, built by `DocumentTextBuilder` in a new `RFCReaderKit` package and laid out by a shared `RFCTextViewCoordinator` behind a macOS `NSTextView` and an iOS `UITextView`. Nothing in the body becomes a hosted SwiftUI view; the decorations attributed text cannot express on its own — the card behind artwork and tables, the rule beside a block quote, the aside tint, the reference chip — are drawn by an `NSTextLayoutFragment` subclass instead. The document header is not in the storage: it is a SwiftUI view hosted in the text view's top content inset, because it carries buttons (the status banner's links to newer RFCs) that nobody selects through. `DocumentTextBuilder` replaces `InlineText.attributedString(_:)` and the per-block SwiftUI views that fed the old `LazyVStack`; `BuilderCompletenessTests.nothingBecomesAnAttachment` guards the "nothing becomes a hosted view" rule directly, failing on any `NSTextAttachment` outside the one chip run the design allows. See `docs/superpowers/specs/2026-09-21-textkit-2-reader-design.md` for the full design.

Reference labels still ride on this decision. The parsers still bake the whole label into
`CrossReference.text` (`[RFC 9110]`, `Section 4.2 of [RFC 9110]`), with U+00A0 joining
each word to its number so a reference never breaks across a line — that part is
unchanged. What is new is `CrossReference.isCanonicalLabel`, set by both parsers, which
says whose brackets they are: true for a canonical series id (`[RFC 9110]`) that a
renderer may restyle, false for an author's own tag (`[QUIC-TRANSPORT]`), which must
survive verbatim. Whether the brackets themselves are ours depends on the source format:
the XML parser synthesises them around `derivedContent` (a bare `RFC9110`), so they are
ours on that path — but the legacy parser matches a literal `[RFC2119]` already sitting in
the plain-text source and copies it verbatim, so on that path the brackets are the RFC
Editor's own, not ours. `DocumentTextBuilder` uses the flag to drop the brackets and draw
a chip instead: a leading `doc.text` glyph (the one `NSTextAttachment` in the whole
design) followed by a tinted rounded background painted by `RFCTextLayoutFragment`, the
whole run marked `.rfcChip` so the builder's completeness test and the fragment's drawing
code can both find it.

This is the first app task after the Xcode project builds.

## Planned engines

- **Search.** SQLite FTS5 (via GRDB) with BM25 ranking, one row per section, over all abstracts plus every downloaded document; snippets from `snippet()`. Later, a hybrid reranker with `NLContextualEmbedding` vectors: per abstract for the whole index (precomputed pack, ~20 MB), per section for downloaded documents. Metadata search moves into the same database.
- **Highlighting.** A tokenizer per language (ABNF, JSON, HTTP messages, YANG, ASN.1, C-like) in RFCKit producing `[Token]` with kinds; the renderer maps kinds to colours. Heuristic language detection for legacy text (`rulename = ` lines → ABNF).
- **Diff.** Section alignment by title similarity and position, LCS over paragraphs within aligned sections, word-level diff (`CollectionDifference` or Myers) inside changed paragraphs. Output is a diff document rendered with the same block views plus insert/delete styling. Works for draft revisions and for obsoleted RFC → successor.
- **Diagrams.** Box-art to Unicode box-drawing conversion per block; packet-diagram parser producing a bit-field model rendered natively.

## Known gaps and the next technical steps

- Legacy text: definition lists with hanging indents (e.g. the cache directives in RFC 2616 §14.9.1) render as preformatted blocks; nested lists are flattened; multi-author front matter picks up only authors that sit on their own line.
- Search: ~70 ms per query over the full index, in memory. Run it off the main actor with a short debounce for now; move to SQLite FTS5 (GRDB) when full-text search over document bodies lands, and let the same index serve metadata search.
- SVG artwork (`<artwork type="svg">`) is skipped in favour of the ASCII alternative.
- No Spotlight indexing, iCloud sync, errata or Datatracker integration yet; the client has the endpoints, the model has the fields.
- The reader lays out the whole document body in one synchronous `ensureLayout` before first paint; measured at ~530 ms on RFC 5661, the largest RFC in the corpus. Accepted deliberately for this milestone — paging the layout is the deferred fix (issue #9).
- `CrossReference.isCanonicalLabel` is recomputed on reparse rather than persisted: `RFCXMLSerializer` writes neither the flag nor `derivedContent`, so it can diverge when a source document's `derivedContent` differs from its own reference anchor. The legacy corpus-build path is safe and has a test; issue #6's layering change would dissolve this gap entirely (issue #10).
- Copying a reference chip puts U+FFFC on the pasteboard and loses the bracket delimiters, so adjacent references (`RFC 9110 RFC 9111`) run together in copied text instead of staying separated the way the chip's tint separates them on screen (issue #11).
- VoiceOver still reads artwork character by character during ordinary swipe-through reading; only a Diagrams rotor for jumping between artwork blocks was added, not a spoken-through replacement (issue #12).
