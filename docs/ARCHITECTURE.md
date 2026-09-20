# Architecture

## Shape of the code base

```
rfc-reader/
├── Packages/RFCKit/          Swift package: everything that is not UI. Builds and tests on Linux and macOS.
│   ├── Sources/RFCKit/
│   │   ├── Models/           DocumentID, RFCMetadata, RFCIndex, enums for status/stream/format
│   │   ├── Index/            RFCIndexParser (streaming SAX), XMLTree (small DOM used by the document parser)
│   │   ├── Document/         RFCDocument model, RFCXMLParser (RFCXML v3), LegacyTextParser (plain text)
│   │   ├── Client/           RFCEditorEndpoints, RFCEditorClient (actor), RFCLink (URL scheme + web URLs), feed parser
│   │   ├── Citation/         CitationFormatter (short, full, Markdown, BibTeX, URL)
│   │   └── Search/           IndexSearch (in-memory metadata search with a small query grammar)
│   └── Tests/RFCKitTests/    Swift Testing suites with real fixtures (RFC 1149, 2119, 5234, 8999, index sample, RSS, JSON)
├── App/RFCReader/            SwiftUI multiplatform app (iOS, iPadOS, macOS)
│   ├── Model/                LibraryModel (@Observable app state), DocumentStore (actor, disk cache), SwiftData models
│   ├── Views/                Navigation, list, reader, table of contents
│   │   └── Rendering/        BlockView, InlineText, PreformattedView — the document model → SwiftUI mapping
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
- **Display text travels with the reference.** RFCXML's prepped output carries `derivedContent` ("Figure 1", "Section 4.2"); the parser turns it into the exact label the RFC Editor renders, so we never re-implement numbering rules.

## Parsing the two source formats

**RFCXML v3** (`RFCXMLParser`): the whole file is loaded into a tiny DOM (`XMLTree`) and walked. Documents are at most a couple of megabytes; RFC 9110 (1.2 MB, 305 sections, 1,376 paragraphs) parses in about 50 ms in a release build. Whitespace inside `<t>` is collapsed as HTML would; artwork and source code are kept byte-for-byte. `<artset>` picks the ASCII alternative until there is an SVG renderer.

**Legacy text** (`LegacyTextParser`), in order:
1. *Depaginate*: drop form feeds, `[Page N]` footers and the running header that follows a page break; remember where breaks were.
2. *Front matter*: the two-column header block (`Request for Comments: 1149`, `Obsoletes:`, `Category:`, authors, date) up to the first blank line, then the centred title.
3. *Headings*: any non-indented line. `1.2.` → numbered; `Appendix B.` / `B.1.` → appendix; anything else unnumbered. Depth from the number; sections nest with a stack.
4. *Blocks*: runs of lines separated by blank lines. A block is prose if every line shares a small indent and contains no artwork tell-tales (`+--`, `|`, `->`, runs of spaces); prose is reflowed. A block starting with `o`, `-`, `*`, `1.`, `(a)` becomes a list. Everything else is preformatted, minus common indent. Blocks cut by a page break are re-joined when both halves look like prose and the first half does not end a sentence; a trailing hyphen joins without a space.
5. *References*: `[Anchor] text…` entries with hanging indents; RFC/BCP/STD numbers, quoted title, date and URL are pulled from the text.
6. *Boilerplate* ("Status of This Memo", "Table of Contents", copyright) is dropped from the model but stays in the "original text" view, which is `stripPagination(_:)` over the same file.

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

- Raw files are cached exactly as served. Re-parsing after a parser fix is free, and the "original text" mode needs no second download.
- The index is cached to disk and re-fetched in the background when older than a day; a bundled snapshot (drop `rfc-index.xml` into the app's resources) makes first launch work offline.
- Navigation is data: `LibraryModel.open(RFCLink)` sets `selection` and `pendingSection`; `DocumentView` scrolls once the document has loaded. The URL scheme handler, the App Intent, cross-reference taps and the status banner all go through the same call.
- Cross references render as `.link` attributes on an `AttributedString` with two private schemes (`rfc://…` for other documents, `rfc-anchor:…` for the same document). `DocumentView` installs an `OpenURLAction` that intercepts them; everything else falls through to the system.

## Testing

`swift test --package-path Packages/RFCKit` runs 44 Swift Testing cases in about 0.1 s on real fixtures: the full RFC 8999 XML, RFCs 1149, 2119 and 5234 as text, a trimmed index, the RSS feed and a per-RFC JSON record. Each parser has a truncated-input test. The app target is not unit-tested yet; the plan is snapshot tests for `BlockView` once the rendering settles.

CI (`.github/workflows/ci.yml`) runs the package tests on macOS and in a Linux Swift container.

## Known gaps and the next technical steps

- Legacy text: definition lists with hanging indents (e.g. the cache directives in RFC 2616 §14.9.1) render as preformatted blocks; nested lists are flattened; multi-author front matter picks up only authors that sit on their own line.
- Search: ~70 ms per query over the full index, in memory. Run it off the main actor with a short debounce for now; move to SQLite FTS5 (GRDB) when full-text search over document bodies lands, and let the same index serve metadata search.
- Rendering: `LazyVStack` scroll-to-anchor is best-effort. If it proves unreliable, render sections in a plain `VStack` up to a size threshold, or move the reader to a `UITextView`/`NSTextView` with TextKit 2 and keep the block model as the source.
- SVG artwork (`<artwork type="svg">`) is skipped in favour of the ASCII alternative.
- No Spotlight indexing, iCloud sync, errata or Datatracker integration yet; the client has the endpoints, the model has the fields.
