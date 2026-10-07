# RFC Reader — vision and feature brainstorm

*September 2026. A working document; argue with it.*

## The one-line pitch

Every RFC, beautifully readable, instantly searchable, and one tap from any reference — native on iPhone, iPad and Mac.

## Why this app should exist

The RFC series is the source of truth for how the Internet works, and the reading experience is stuck in 1995. Engineers read RFCs in a browser tab, in monospaced 72-column text, with page footers interrupting paragraphs, and with `[RFC7231]` being dead text that needs a second tab and a search. The two apps that exist on the App Store are old, wrap a web view or the raw text, and do little more than list titles.

Modern Apple platforms make a fundamentally better reader cheap to build:

- RFCs published since 2019 (about 1,400 and growing at every publication) have a semantic XML source (RFCXML v3). Sections, lists, cross-references, code and tables are all structured. Nobody renders that natively today.
- The remaining ~8,400 legacy text RFCs follow a strict enough layout that structure can be recovered heuristically, and the original text is always available as a fallback.
- Cross-referencing between RFCs is the single most valuable thing a reader can add, and the RFC Editor's index gives us the full obsoletes/updates graph for free.

## Who it is for

1. **Protocol engineers** implementing or debugging something. They know the RFC number, want a specific section, and need to jump between three related documents. Speed and deep links matter most.
2. **Learners** reading a spec front to back. Typography, a table of contents that follows along, and being able to see "this was obsoleted, read 9110 instead" matter most.
3. **Writers and reviewers** (IETF participants, standards people, authors of internal specs) who need to cite precisely: "RFC 9110, Section 8.3", BibTeX, a Markdown link.

## Guiding principles

- **The document is the interface.** No dashboards, no feeds pretending to be content. Get out of the way of the text.
- **Structure over appearance.** Parse into a document model, then render natively. Never ship a web view.
- **Everything is a link.** `[RFC2119]`, `Section 4.2`, `Section 3 of [RFC9000]`, `Figure 1`, `https://` — all tappable, all in-app, with a peek before you commit.
- **Truth about status.** The first thing a reader sees is whether the document is current, updated, obsoleted or has errata.
- **Offline by default.** The index and everything you have opened stays on device. Sync the user's own data through iCloud, never their reading history to us.
- **Kind to metered and poor connections.** Never spend bandwidth on something nobody is waiting for: a download the reader has walked away from is canceled, not finished in the background.
- **Native on every platform.** One SwiftUI code base. Real menu bar commands and keyboard shortcuts on Mac, Split View and Pencil on iPad, Handoff and Spotlight everywhere.

## Feature set, in tiers

### Tier 0 — the core reader (MVP, "0.1")

*Shipped. Items of later tiers that have shipped say so.*

Browse and find
- Full index of every RFC, BCP, STD and FYI, refreshed from the RFC Editor. Snapshot bundled for offline first launch.
- Instant type-ahead search over number, title, keywords, authors, working group, abstract. Query grammar: `wg:httpbis` (or `wg:quic,tls`), `author:fielding`, `status:std`, `status:internet-standard`, `status:current`, `year:2020-2022`, `after:2023-06`, `before:2024`, `published:<90d`, `has:xml`, `is:bookmarked|read|offline`, `in:rfc9110`, `in:bcp14` or `in:"Some collection"`, `sort:newest|oldest|last-read`. A term this version doesn't know finds nothing rather than being searched as text (#355).
- Sidebar: Bookmarks, Recently read, Available offline, All, Internet Standards, BCPs, streams, top working groups, "Just published" from the RFC Editor RSS feed.
- Command-L "Go to RFC…" accepting a number, `BCP 14`, or any rfc-editor.org / datatracker URL.

Read
- Native rendering of the document model: headings, paragraphs, lists, definition lists, tables, figures, monospaced artwork and code (copied with Copy Figure or an ordinary selection), references.
- Legacy text RFCs: page furniture removed, paragraphs reflowed and re-joined across page breaks, prose vs. ASCII art detected, headings recovered, references linked. "Original text" toggle shows the file as published.
- Status banner: obsoleted by / updated by / has errata, with one-tap navigation to the newer document.
- Table of contents inspector that tracks the current section.
- Adjustable type size; Dynamic Type; selectable text.
- Reading position remembered per document.

Reference
- Every cross-reference is a link. Same-document references scroll; other-RFC references open the document at that section.
- Cite menu: short (`RFC 9110, Section 4.2`), RFC Editor full citation, Markdown link, BibTeX, URL. Section-aware.
- Share sheet with the canonical info page URL.
- `rfc://9110#section-4.2` URL scheme; App Intents for Siri, Shortcuts and Spotlight: Open RFC and Open Section, Look Up Identifier and Find Requirements, over RFC, section and registry entry entities (#192).
- Bookmarks (SwiftData, local for now).

### Tier 1 — the reader people recommend ("0.2 – 0.3")

- **Full-text search** across downloaded documents with snippets and section-level results (SQLite FTS5 via GRDB). Offer "download everything" (~600 MB of text) for people who want a complete offline corpus.
- **Reference peek** *(shipped)*. Long-press or hover a `[RFC7231]` link to see title, status, abstract and the referenced section, without leaving the page.
- **Lineage view.** For any RFC: what it obsoletes and updates, what obsoletes and updates it, drawn as a small graph. "Show me the current version of this" in one tap.
- **Errata inline.** Fetch the errata feed; mark affected sections with a glyph; show original vs. corrected text in a popover. This is a real reading aid nobody offers.
- **Collections.** Manual reading lists plus automatic ones: a STD or BCP number is already a collection; a working group is a collection; "everything this RFC references" is a collection. *Shipped, except the last.*
- **iCloud sync** of bookmarks, reading positions and collections (SwiftData + CloudKit is mostly a capability toggle).
- **Highlights and notes**, synced, exportable as Markdown with citations attached.
- **Spotlight indexing** of the index (title, number, abstract) so system search finds RFCs; Handoff between iPhone, iPad and Mac.
- **Mac polish**: multiple windows and tabs *(shipped)*, Services menu ("Open in RFC Reader" and "Replace with RFC Link" on selected text) *(shipped)*, Quick Look-style popover for reference links, printing and PDF export of the rendered document.
- **Widgets**: "Just published", "Continue reading".
- **Coding agents.** A local MCP server, so the agent beside the code reads the same anchored, status-aware text the reader shows: search, sections, requirements with stable IDs, definitions, citations, and the reader's own library. It answers with sources, never generated text. Design: `docs/superpowers/specs/2026-10-02-mcp-server-design.md`.

### Tier 2 — beyond RFCs ("later, if it earns its place")

- **Internet-Drafts** from the Datatracker, with the same renderer, and "what changed" diffs between draft versions or between a draft and the RFC it became.
- **On-device intelligence** via the Foundation Models framework: summarize a section, explain a term in context, "which sections of RFC 9110 replaced Section 5.1 of RFC 7231". Everything stays on device, and every answer links to the text it came from. Worth doing only if it can be honest about its sources.
- **Translation** of a selection via the Translation framework, for non-native readers.
- **visionOS**: a reading room with a spec pinned next to your code is a genuinely good use of the platform.
- **Pencil annotation** on iPad, kept as an overlay per section so it survives re-rendering.

### Things deliberately out of scope

- Editing or authoring RFCs (the `xml2rfc` toolchain does that well).
- Being a mailing-list or Datatracker client.
- Server-side anything. No accounts, no analytics beyond opt-in crash reports.

## Wishlist, mapped to the plan

Ideas from the first brainstorm session and where each one lands.

| Idea | Where it lands | Notes |
|---|---|---|
| Prose reflowed to the viewport with adjustable typography (Safari Reader, Apple Books) | Tier 0, already the core design | The block model separates prose from artwork, so reflow is free. Add a `ReadingSettings` object: font family, size, line height, measure, margins, theme incl. sepia. Pagination is a possible later mode; scrolling stays the default. |
| Full semantic search, BM25 and/or vectors | Tier 1 (BM25), Tier 1–2 (hybrid) | SQLite FTS5 has BM25 built in: section-level hits with snippets over everything downloaded plus every abstract. Vectors come second, as an optional reranker of BM25's top hits with a retrieval-tuned model we ship; `NLContextualEmbedding` was measured and helped nothing. The measured configuration is [the search decision](decisions/2026-09-24-full-text-search-ranks-by-measurement-and-was-measured-before-it-was-built.md)'s. |
| ASCII flowcharts and diagrams rendered well | Tier 1 | Per-block, reversible upgrade of `+-|` art to Unicode box drawing. Packet diagrams (`0 1 2 3 … +-+-+`) follow a strict format and can be parsed into a native bit-field table, which no reader does today. SVG alternatives in newer RFCs need a small dependency or a web view for that one block. |
| ABNF and other grammars, syntax highlighting for code (confirmed: ABNF, not "DNF") | Tier 1 | RFCXML labels `<sourcecode type="abnf">`, `json`, `http-message`, `yang`, `asn.1`, `c`; legacy text ABNF is detectable from `rulename =` lines. One regex lexer engine in RFCKit, with a rule table per language, produces tokens the renderer colors; JSON, XML and HTTP messages first. No JavaScript-based highlighters. |
| Working inter-spec links | Tier 0, done in the model | Cross references resolve to document and section at parse time. Still to add: Internet-Draft references (`[I-D.ietf-quic-http]`) and IANA registry URLs. |
| Drafts, and a pleasing delta between versions | Tier 2 | Every draft revision is served as text (and XML for recent ones) from the IETF archive, so both sides parse into the same model. Diff at three levels: align sections by title and position, LCS over paragraphs, word-level diff inside changed paragraphs. The same engine gives "what changed from RFC 7231 to RFC 9110", probably the more valuable view for implementers. Fuzzy alignment after restructurings is the hard part. Drafts also enable "notify me when this draft has a new version". |
| Links with a preview on hard press | Tier 1, **decided: TextKit 2 renderer** | SwiftUI `Text` cannot attach per-link context menus or previews. The reader body is a TextKit 2 backed text view, which also brings hover popovers on Mac, find-in-document and better selection. See [the preview decision](decisions/2026-09-26-a-reference-previews-on-hover-and-force-click-on-macos-and-on-long-press-on-ios.md). |
| Handoff between iPhone, iPad and Mac | Tier 1 | `NSUserActivity` carrying the `rfc://` link of the current section. |
| ⌘-click a reference to open it in a new window (Mac) | Tier 1 | Falls out of navigation being a link. |
| An MCP server for local coding agents | Tier 1 (#193) | A helper executable in the app bundle, over stdio: the corpus and the iCloud-synced library read straight from the app's shared files, so it works with the app closed. Prompts for the common questions and an agent-run conformance review against a document's requirements. Local, so it is not the "server-side anything" ruled out below. |

## What the experience should feel like

**iPhone.** Tab-less: a stack. Search field at the top of the list, reader full screen with a translucent bottom bar (contents, type size, cite, share). Pull the table of contents up as a sheet. Cross-reference taps push the other document; swipe back returns to where you were.

**iPad and Mac.** Three columns: sidebar, list, reader; the table of contents docks as an inspector on the right. Command-L jumps to a number, Command-F finds in document, Command-Option-I toggles contents, Command-D bookmarks. On Mac the reader opens in tabs, cross references can open in a new window with Command-click, and the menu bar has everything.

**Reading typography.** Prose in the system serif or a well-chosen humanist face at a comfortable measure (about 70 characters), artwork in SF Mono in a subtle card, never wrapped and scaled so its widest line fits the measure. Headings numbered exactly as the RFC numbers them. Dark mode from day one.

**The status banner** sits between title and abstract, not in a toolbar. If a document is obsolete, the banner is red and the newer RFC is one tap away. That single design decision would already put this app ahead of the web.

## Data sources (all verified live, none need authentication)

| What | URL | Notes |
|---|---|---|
| Full index | `https://www.rfc-editor.org/rfc-index.xml` | ~14 MB, 9,842 RFCs (counts dated in `DATA_PIPELINE.md`) plus BCP/STD/FYI groups; parses in about a second |
| Document, semantic | `https://www.rfc-editor.org/rfc/rfcNNNN.xml` | RFCXML v3; available for ~1,400 RFCs (roughly 8650 onwards) |
| Document, text | `https://www.rfc-editor.org/rfc/rfcNNNN.txt` | Available for every RFC but a few early ones published only as PDF (#207) |
| Per-RFC metadata | `https://www.rfc-editor.org/rfc/rfcNNNN.json` | Small; status, obsoletes, updates, errata URL |
| Recently published | `https://www.rfc-editor.org/rfcrss.xml` | RSS, cheap to poll |
| Errata | `https://www.rfc-editor.org/errata.json` | ~12 MB, every erratum with section and original/corrected text |
| Datatracker record | `https://datatracker.ietf.org/api/v1/doc/document/?name=rfcNNNN&format=json` | Working group, history, related drafts |

The 8,464 legacy RFCs are a closed set; the 8,457 of them published as text are converted to RFCXML once, offline, and shipped as optional packs together with search indexes and the citation graph. `DATA_PIPELINE.md` has sizes and the delivery design.

RFC numbers passed 10000 in 2026 (RFC 10050 was published on 19 September 2026). Nothing may assume four digits.

## Risks and open questions

- **Legacy text parsing will never be perfect.** Definition lists with hanging indents, nested lists, and tables drawn in ASCII are hard to classify. Mitigation: bias toward preformatted (never mangle), keep the original text one toggle away, and let users report a misrendered section.
- **Rendering performance.** Settled: the reader body is one TextKit 2 text storage per document in `UITextView`/`NSTextView`, not a lazy stack of SwiftUI views; [the decision](decisions/2026-09-20-textkit-2-for-the-reader-body.md) says why.
- **Search latency.** Metadata search scans the whole index per query in the current in-memory implementation (the "Search" benchmarks of `make benchmark` measure it). FTS5 replaces it when full-text search arrives.
- **Business model.** The app will be public and possibly sold. AGPL open source plus a paid App Store build is a legitimate combination (the source is free, the convenience and signing are not). This makes the licensing of the legacy XML pack a real question rather than a formality; see DATA_PIPELINE.md.
- **Name.** "RFC Reader" is descriptive and probably taken. Worth a short list of alternatives before the App Store listing exists.

## Roadmap sketch

1. **Week 1–2:** Xcode project from this scaffold; index loads; list, search and Go-to work; XML and text documents render; cross references navigate. Ship to TestFlight for yourself.
2. **Week 3–4:** Status banner, table of contents inspector, cite menu, bookmarks, reading position, URL scheme and App Intent. Typography pass. First outside testers.
3. **Month 2:** Reference peek, lineage view, errata inline, iCloud sync, Spotlight. Mac polish. App Store submission.
4. **Month 3+:** Full-text search and offline corpus, collections, highlights and notes, widgets. Then decide about drafts and on-device intelligence based on what testers actually ask for.
