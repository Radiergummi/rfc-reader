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
- **Native on every platform.** One SwiftUI code base. Real menu bar commands and keyboard shortcuts on Mac, Split View and Pencil on iPad, Handoff and Spotlight everywhere.

## Feature set, in tiers

### Tier 0 — the core reader (MVP, "0.1")

Browse and find
- Full index of every RFC, BCP, STD and FYI, refreshed from the RFC Editor. Snapshot bundled for offline first launch.
- Instant type-ahead search over number, title, keywords, authors, working group, abstract. Query grammar: `wg:httpbis`, `author:fielding`, `status:std`, `status:current`, `year:2020-2022`, `has:xml`.
- Sidebar: Bookmarks, Recently read, Available offline, All, Internet Standards, BCPs, streams, top working groups, "Just published" from the RFC Editor RSS feed.
- Command-L "Go to RFC…" accepting a number, `BCP 14`, or any rfc-editor.org / datatracker URL.

Read
- Native rendering of the document model: headings, paragraphs, lists, definition lists, tables, figures, monospaced artwork and code with copy button, references.
- Legacy text RFCs: page furniture removed, paragraphs reflowed and re-joined across page breaks, prose vs. ASCII art detected, headings recovered, references linked. "Original text" toggle shows the file as published.
- Status banner: obsoleted by / updated by / has errata, with one-tap navigation to the newer document.
- Table of contents inspector that tracks the current section.
- Adjustable type size; Dynamic Type; selectable text.
- Reading position remembered per document.

Reference
- Every cross-reference is a link. Same-document references scroll; other-RFC references open the document at that section.
- Cite menu: short (`RFC 9110, Section 4.2`), RFC Editor full citation, Markdown link, BibTeX, URL. Section-aware.
- Share sheet with the canonical info page URL.
- `rfc://9110/section/4.2` URL scheme; App Intent "Open RFC" for Siri, Shortcuts and Spotlight.
- Bookmarks (SwiftData, local for now).

### Tier 1 — the reader people recommend ("0.2 – 0.3")

- **Full-text search** across downloaded documents with snippets and section-level results (SQLite FTS5 via GRDB). Offer "download everything" (~600 MB of text) for people who want a complete offline corpus.
- **Reference peek.** Long-press or hover a `[RFC7231]` link to see title, status, abstract and the referenced section, without leaving the page.
- **Lineage view.** For any RFC: what it obsoletes and updates, what obsoletes and updates it, drawn as a small graph. "Show me the current version of this" in one tap.
- **Errata inline.** Fetch the errata feed; mark affected sections with a glyph; show original vs. corrected text in a popover. This is a real reading aid nobody offers.
- **Collections.** Manual reading lists plus automatic ones: a STD or BCP number is already a collection; a working group is a collection; "everything this RFC references" is a collection.
- **iCloud sync** of bookmarks, reading positions and collections (SwiftData + CloudKit is mostly a capability toggle).
- **Highlights and notes**, synced, exportable as Markdown with citations attached.
- **Spotlight indexing** of the index (title, number, abstract) so system search finds RFCs; Handoff between iPhone, iPad and Mac.
- **Mac polish**: multiple windows and tabs, Services menu ("Open RFC" on selected text), Quick Look-style popover for reference links, printing and PDF export of the rendered document.
- **Widgets**: "Just published", "Continue reading".

### Tier 2 — beyond RFCs ("later, if it earns its place")

- **Internet-Drafts** from the Datatracker, with the same renderer, and "what changed" diffs between draft versions or between a draft and the RFC it became.
- **On-device intelligence** via the Foundation Models framework: summarise a section, explain a term in context, "which sections of RFC 9110 replaced Section 5.1 of RFC 7231". Everything stays on device, and every answer links to the text it came from. Worth doing only if it can be honest about its sources.
- **Translation** of a selection via the Translation framework, for non-native readers.
- **visionOS**: a reading room with a spec pinned next to your code is a genuinely good use of the platform.
- **Pencil annotation** on iPad, kept as an overlay per section so it survives re-rendering.

### Things deliberately out of scope

- Editing or authoring RFCs (the `xml2rfc` toolchain does that well).
- Being a mailing-list or Datatracker client.
- Server-side anything. No accounts, no analytics beyond opt-in crash reports.

## What the experience should feel like

**iPhone.** Tab-less: a stack. Search field at the top of the list, reader full screen with a translucent bottom bar (contents, type size, cite, share). Pull the table of contents up as a sheet. Cross-reference taps push the other document; swipe back returns to where you were.

**iPad and Mac.** Three columns: sidebar, list, reader; the table of contents docks as an inspector on the right. Command-L jumps to a number, Command-F finds in document, Command-Shift-T toggles contents, Command-D bookmarks. On Mac the reader opens in tabs, cross references can open in a new window with Command-click, and the menu bar has everything.

**Reading typography.** Prose in the system serif or a well-chosen humanist face at a comfortable measure (about 70 characters), artwork in SF Mono in a subtle card that scrolls horizontally rather than wrapping. Headings numbered exactly as the RFC numbers them. Dark mode from day one.

**The status banner** sits between title and abstract, not in a toolbar. If a document is obsolete, the banner is red and the newer RFC is one tap away. That single design decision would already put this app ahead of the web.

## Data sources (all verified live, none need authentication)

| What | URL | Notes |
|---|---|---|
| Full index | `https://www.rfc-editor.org/rfc-index.xml` | ~14 MB, ~9,850 RFCs plus BCP/STD/FYI groups; parses in about a second |
| Document, semantic | `https://www.rfc-editor.org/rfc/rfcNNNN.xml` | RFCXML v3; available for ~1,400 RFCs (roughly 8650 onwards) |
| Document, text | `https://www.rfc-editor.org/rfc/rfcNNNN.txt` | Available for every RFC |
| Per-RFC metadata | `https://www.rfc-editor.org/rfc/rfcNNNN.json` | Small; status, obsoletes, updates, errata URL |
| Recently published | `https://www.rfc-editor.org/rfcrss.xml` | RSS, cheap to poll |
| Errata | `https://www.rfc-editor.org/errata.json` | ~12 MB, every erratum with section and original/corrected text |
| Datatracker record | `https://datatracker.ietf.org/api/v1/doc/document/?name=rfcNNNN&format=json` | Working group, history, related drafts |

RFC numbers passed 10000 in 2026 (RFC 10050 was published on 19 September 2026). Nothing may assume four digits.

## Risks and open questions

- **Legacy text parsing will never be perfect.** Definition lists with hanging indents, nested lists, and tables drawn in ASCII are hard to classify. Mitigation: bias toward preformatted (never mangle), keep the original text one toggle away, and let users report a misrendered section.
- **Rendering performance.** A 1,400-paragraph document in a lazy stack is fine; scroll-to-anchor inside a lazy stack is less reliable. Fallback is a plain stack for documents under a threshold, or `UITextView`/`NSTextView` with TextKit 2 if SwiftUI text proves limiting.
- **Search latency.** Metadata search over the whole index takes ~70 ms per query in the current in-memory implementation. Fine off the main actor with a debounce; FTS5 replaces it when full-text search arrives.
- **Business model.** AGPL open source plus a paid App Store build is a legitimate combination (the source is free, the convenience and signing are not). Alternatively free with a tip jar. Decide before 1.0, not before 0.1.
- **Name.** "RFC Reader" is descriptive and probably taken. Worth a short list of alternatives before the App Store listing exists.

## Roadmap sketch

1. **Week 1–2:** Xcode project from this scaffold; index loads; list, search and Go-to work; XML and text documents render; cross references navigate. Ship to TestFlight for yourself.
2. **Week 3–4:** Status banner, table of contents inspector, cite menu, bookmarks, reading position, URL scheme and App Intent. Typography pass. First outside testers.
3. **Month 2:** Reference peek, lineage view, errata inline, iCloud sync, Spotlight. Mac polish. App Store submission.
4. **Month 3+:** Full-text search and offline corpus, collections, highlights and notes, widgets. Then decide about drafts and on-device intelligence based on what testers actually ask for.
