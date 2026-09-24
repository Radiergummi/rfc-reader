# Data pipeline: preprocessing the RFC corpus

*Direction decided September 2026. This document says what we precompute, why, and how it reaches the app.*

## The facts that shape everything

Numbers from the RFC Editor index as of 20 September 2026.

| | RFCs | Pages | Text size (est.) |
|---|---|---|---|
| Total | 9,842 | 245,324 | ~530 MB |
| With RFCXML v3 source (RFC 8650 onward, every one of them) | 1,378 | 36,462 | |
| Legacy, text only (everything before RFC 8650) | 8,464 | 208,862 | ~450 MB |

Two consequences:

1. **The legacy set is closed.** No RFC below 8650 will ever gain XML, and no new RFC will ever lack it. Whatever we do to the legacy set is a one-time job, plus an occasional re-run when the heuristics improve.
2. **Structure for legacy RFCs must be recovered heuristically**, and heuristics belong where they can be run over all 8,464 files at once, diffed against the previous run, and hand-corrected. That is a pipeline, not a phone.

## Why the RFC Editor never made this XML

The canonical format became RFCXML v3 in late 2019 (the RFC 7990 series). Before that, authors often wrote in xml2rfc v2 XML, but the RFC Editor applied its edits, including the final AUTH48 changes, to the text and published only the text. So the author XML that survives in the Internet-Draft archive does not match the published RFC, and the oldest RFCs were nroff or typed by hand. The published text is the only faithful source.

## Decision: publish the legacy set as RFCXML v3 ourselves

The pipeline runs `LegacyTextParser` over every legacy RFC, serializes the result with `RFCXMLSerializer`, validates it, and publishes the XML as a data pack. The app then has **one runtime document path, the XML parser**, for all 9,842 RFCs. `LegacyTextParser` stays in RFCKit as the engine the pipeline runs and as an on-device fallback if a pack is missing.

Why RFCXML rather than our own JSON:

- It is a standard, schema-validatable format with an ecosystem (xml2rfc, the RFC Editor's own tooling, Datatracker).
- Hand corrections are ordinary XML edits, reviewable in a pull request.
- The parser already exists and is fast: RFC 9110's 1.2 MB parses in about 50 ms, so the parse cost of XML over a binary format is irrelevant.
- If the output is ever good enough to contribute somewhere, it is already in the right format.

The serializer marks every generated file: a leading comment naming the source file and stating that the structure is heuristic and the text unchanged, plus `<link rel="alternate">` to the original `.txt`. `RFCXMLParser` round-trips the output into an identical section tree (tested on RFC 5234 and on the RFC Editor's own RFC 8999 XML).

### Licensing: what we know, and the fallback if the answer is no

The app is going to be public and possibly sold, so this is not a formality. Status of the question, to be resolved before the first public release of a legacy pack; private use meanwhile needs nothing.

What the licences say, as far as we know today (verify against the current text):

- **RFCs from November 2008 onward** are under the IETF Trust Legal Provisions (TLP). Everyone may reproduce and distribute them verbatim. Modifying them outside the IETF process is not granted, except for translations and for extracting Code Components under the BSD licence. These RFCs all have XML from the RFC Editor anyway (from 8650), or are covered by the same question as below (8650 is late 2019, so RFCs 5378–8649 are TLP-licensed text without official XML).
- **RFCs from roughly 1996 to 2008** carry the RFC 2026 Section 10 boilerplate: the document "may be copied and furnished to others, and derivative works that comment on or otherwise explain it or assist in its implementation may be prepared, copied, published and distributed ... without restriction of any kind, provided that the above copyright notice and this paragraph are included", but "this document itself may not be modified in any way".
- **RFCs before 1996** mostly have no licence statement at all; the Trust's position is that it cannot grant more than the original authors did.

Marking up unchanged text is a format conversion, and arguably a "derivative work that assists in implementation", but "may not be modified in any way" is exactly the kind of clause a cautious reading trips over. Three routes, in order of preference:

1. **Ask.** The IETF Trust (trustees@ietf.org) has granted permissions for tooling before, and a reader app that helps people use RFCs is squarely in the spirit of the licences. A written permission for "publishing the text of legacy RFCs, unchanged, with added RFCXML structure markup" settles it. Reach out with the generated file for a well-known RFC attached so they can see exactly what is being distributed.
2. **Ship structure, not text.** If publishing marked-up text is not permitted, the pack can carry only *structure sidecars*: for each legacy RFC, the byte ranges of the original `.txt` and the role of each range (section heading with number, paragraph, list item, artwork, reference entry, cross-reference target). The app fetches or caches the verbatim `.txt` from the RFC Editor, verifies its hash against the sidecar, and applies the structure at runtime. No RFC text ever leaves the RFC Editor's servers through us, the pack is metadata about a document rather than a copy of it, and the runtime cost is trivial (applying offsets, no heuristics). `LegacyTextParser` would gain a mode that emits ranges instead of a document, and the pipeline would emit sidecars instead of XML. This is a modest change to the pipeline and none to the reader.
3. **Keep the on-device renderer forever.** If even sidecars felt too close to the line, the app fetches the `.txt` and runs `LegacyTextParser` on device, as it does today. Unfortunate, because heuristic fixes then ship with app updates rather than data updates, but entirely workable; the parser already exists and handles RFC 2616 in under a second.

Note that route 2 preserves almost everything route 1 gives: one-time offline heuristics, reviewable overrides, and verified data packs. The difference is only where the bytes of the text come from. Design the pack format so the XML pack and the sidecar pack share the manifest and delivery mechanism, and the decision can be made late.

## Pipeline stages

All stages are subcommands of `Tools/corpus-build`, a Swift executable that depends on RFCKit. It has no other dependencies and runs on macOS and Linux.

```
rfc-index.xml ──▶ fetch ──▶ corpus/text.noindex/rfcNNNN.txt      (8,457 files, one-time, resumable)
                              │
                              ▼
                            convert ──▶ corpus/xml.noindex/rfcNNNN.xml   (+ corpus/report.json)
                              ▲
rfc-index.xml ──▶ fetch --format xml ─┘                          (1,378 files, no conversion)
      RFCs authored in RFCXML are already in the runtime format; `hasXMLSource`
      partitions the index, so the two fetches never write the same file.
                              ▲
              corpus/overrides/rfcNNNN.xml  (hand-corrected files win over generated ones)
                              │
                              ▼
                            manifest ──▶ manifest.json  (sha256 + size per file, pack version)
                              │
                              ▼
                     tar --zstd ──▶ legacy-xml-<version>.tar.zst ──▶ GitHub Release / R2
```

- **fetch** reads the index, picks every RFC without an XML format, and downloads the `.txt` with bounded concurrency (default 6, be polite to the RFC Editor). Existing files are skipped, so re-runs only fetch what is new or missing. `--limit N` for smoke tests.
- **convert** parses each text file, serializes to RFCXML, re-parses the output as a self-check, and writes a per-document report: section, paragraph, list, artwork and reference counts plus warnings ("no RFC number in front matter", "more artwork than prose", "round trip changed section count"). An override file replaces the generated output entirely, after being checked to parse. Overrides are the correction mechanism: fix the heuristic in RFCKit when a class of documents is wrong, add an override when one document is.
- **manifest** hashes every file so the app can verify downloads and fetch individual documents by path.

Regression review is a diff of two `report.json` files: a heuristic change that moves counts on hundreds of documents gets looked at before it ships. The reports for the 1969 RFCs already show what to expect: RFC 2 flags "more artwork than prose" (its hand-typed layout is indistinguishable from diagrams) and RFC 3 has no recognisable front matter. Those become overrides or targeted heuristics; the 1990s and 2000s RFCs, which are the bulk, follow the strict format the parser is built for.

## What we precompute, and what we never do

Rendering is never precomputed. Fonts, widths, Dynamic Type and dark mode differ per device; the app renders the model at runtime. Everything below is a model, an index or a graph.

| Pack | Contents | Raw | Shipped (zstd) | Delivery |
|---|---|---|---|---|
| `index` | Compact form of the RFC Editor index: metadata for all documents, series groupings | 14 MB XML | ~1 MB | **In the app bundle**, refreshed at runtime from the RSS feed and the live index |
| `graph` | Citation graph (who cites whom, from every References section), obsoletes/updates edges | a few MB | <1 MB | In the bundle or first optional pack |
| `errata` | Normalized errata: RFC, section, status, original and corrected text | 12 MB JSON | <1 MB | Bundle or fetched on first use |
| `legacy-xml` | RFCXML for the 8,464 legacy RFCs | ~480 MB | ~100 MB | Optional download, "Read everything offline" |
| `modern-xml` | Mirror of the RFC Editor's XML for RFCs ≥ 8650 | ~60 MB | ~15 MB | Optional; otherwise fetched per document |
| `fts` | SQLite FTS5 database, one row per section, BM25 ranking, over the whole corpus | 150–250 MB | ~80 MB | Optional, requires the XML packs |
| `embeddings-abstracts` | One vector per RFC abstract | ~10 MB | ~10 MB | Optional, enables semantic search over the whole series |
| `embeddings-sections` | One vector per section, 128 dimensions, int8 | ~60 MB | ~60 MB | Optional, only with the XML packs |

Notes on individual packs:

- **The citation graph is the one thing a device cannot compute alone**: "cited by" needs every References section in the series. It is small, so it goes in the bundle or the first pack everyone gets.
- **Modern XML** is fetched per document from the RFC Editor today and cached. The pack exists only so "everything offline" is truly everything.
- **The FTS database** could be built on device from the XML packs, but that costs minutes of CPU and battery on first run; shipping it prebuilt is kinder. It is a derived artifact, rebuilt whenever the XML changes.
- **Embeddings must be computed with a model we ship**, not with Apple's `NLContextualEmbedding`, because Apple's models are versioned per OS release and a vector computed on a Mac may not match a query embedded on an iPhone. A small open sentence encoder converted to Core ML, bundled with the app and used both offline and on device, keeps the two sides identical. Section vectors are reduced to 128 dimensions and quantized to int8 to stay under 100 MB.
- **Internet-Drafts are never packed.** The set is large and changes daily; drafts are fetched on demand.

The app bundle target is under about 30 MB: code plus the compressed index. Everything else is optional and downloaded on request or in the background.

## Delivery mechanism

- **Hosting.** GitHub Releases on this repository (or a dedicated `rfc-reader-data` repository) to start: free, CDN-backed, 2 GB per asset, and every pack is a tagged, immutable version. Move to a Cloudflare R2 bucket behind a custom domain if download volume ever matters; the manifest format does not change.
- **Manifest.** `manifest.json` lists every pack with version, size and SHA-256, and every file inside the XML packs by path and hash. The app verifies what it downloads and can also fetch a single document out of a pack by path once packs are served unpacked (R2 stage).
- **On the device.** Apple's Background Assets framework is built for exactly this: large optional downloads hosted by the developer, fetched at install time or in the background, not counted against the App Store download size, with managed storage and eviction. On-demand resources are being phased out in its favour, so do not build on ODR.
- **Versioning.** Packs are versioned `YYYY.MM[.patch]`. The legacy XML pack changes only when the heuristics or overrides change, which is rare. The index, graph and errata refresh whenever the RFC Editor publishes; the FTS and embedding packs are rebuilt after any XML change.

## Automation

`.github/workflows/corpus.yml` runs `fetch`, `convert` and `manifest`, compresses the packs and attaches them to a release. It is `workflow_dispatch` only for now: the first full run should be watched, its `report.json` reviewed, and a handful of overrides written before anything is published. Once the output is trusted, a monthly schedule picks up newly published RFCs for the index, graph and errata packs, and the legacy pack simply reproduces byte-for-byte unless the code changed.

The full text fetch is about 450 MB and 8,464 requests; at six concurrent connections it takes on the order of twenty minutes. Cache `corpus/text.noindex` between runs (an Actions cache keyed on the index version) so the RFC Editor is fetched once, not monthly.

## Repository layout for the data

```
corpus/                      (git-ignored working directory, or a separate data repository)
├── rfc-index.xml            snapshot used for this run
├── text/rfcNNNN.txt         fetched sources, byte-for-byte as served
├── overrides/rfcNNNN.xml    hand-corrected documents, committed and reviewed
├── xml/rfcNNNN.xml          generated output
├── report.json              per-document counts and warnings
└── manifest.json
```

Overrides are the only part that must be under version control; everything else is reproducible from the index and the RFC Editor.

## How the app consumes packs

1. On launch, load the bundled `index` pack; refresh from the RSS feed and live index in the background.
2. Opening a document: if a pack containing it is installed, read the XML from the pack; otherwise fetch the RFC Editor's XML (≥ 8650) or, for a legacy RFC without the pack, fall back to fetching the `.txt` and parsing on device with `LegacyTextParser`. Either way the reader sees an `RFCDocument`.
3. Search: metadata search always works from the index. Full-text and semantic search light up when the `fts` and embedding packs are installed; the search UI says so rather than silently returning less.
4. Settings ▸ Offline: a list of packs with sizes, install and remove, and the disk they use.

## Open work, in order

1. Run the full `fetch` and `convert` once, review `report.json`, fix the heuristic classes it exposes (1970s RFCs, hanging-indent definition lists), write the first overrides.
2. Add `graph` and `errata` builders to `corpus-build` (both are small transformations of data we already parse).
3. Add the `fts` builder (GRDB or the sqlite3 C library, FTS5, section rows) and the app-side reader.
4. Pick and convert the embedding model; add the `embeddings` builders; hybrid rerank in the app.
5. Background Assets integration and the Offline settings screen.
6. Resolve the licensing question for public distribution of `legacy-xml` (ask the Trust; fall back to structure sidecars).
