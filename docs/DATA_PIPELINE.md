# Data pipeline: preprocessing the RFC corpus

*Direction decided September 2026. This document says what we precompute, why, and how it reaches the app.*

## The facts that shape everything

Numbers from the RFC Editor index as of 20 September 2026, and unchanged on 28 September. The other documents quote these.

| | RFCs | Pages | Text size (est.) |
|---|---|---|---|
| Total | 9,842 | 245,324 | ~530 MB |
| With RFCXML v3 source (RFC 8650 onward, every one of them) | 1,378 | 36,462 | |
| Legacy, text only (everything before RFC 8650) | 8,464 | 208,862 | ~450 MB |
| … of which a plain-text file exists (the rest are PDF only, #207) | 8,457 | | |

Two consequences:

1. **The legacy set is closed.** No RFC below 8650 will ever gain XML, and no new RFC will ever lack it. Whatever we do to the legacy set is a one-time job, plus an occasional re-run when the heuristics improve.
2. **Structure for legacy RFCs must be recovered heuristically**, and heuristics belong where they can be run over all 8,457 files at once, diffed against the previous run, and hand-corrected. That is a pipeline, not a phone.

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

The app is going to be public and possibly sold, so this is not a formality. Status of the question, to be resolved before the first public release of a legacy pack; private use meanwhile needs nothing. The IETF Trust has been asked (route 1 below), and its answer is pending.

What the licenses say, as far as we know today (verify against the current text):

- **RFCs from November 2008 onward** are under the IETF Trust Legal Provisions (TLP). Everyone may reproduce and distribute them verbatim. Modifying them outside the IETF process is not granted, except for translations and for extracting Code Components under the BSD license. These RFCs all have XML from the RFC Editor anyway (from 8650), or are covered by the same question as below (8650 is late 2019, so RFCs 5378–8649 are TLP-licensed text without official XML).
- **RFCs from roughly 1996 to 2008** carry the RFC 2026 Section 10 boilerplate: the document "may be copied and furnished to others, and derivative works that comment on or otherwise explain it or assist in its implementation may be prepared, copied, published and distributed ... without restriction of any kind, provided that the above copyright notice and this paragraph are included", but "this document itself may not be modified in any way".
- **RFCs before 1996** mostly have no license statement at all; the Trust's position is that it cannot grant more than the original authors did.

Marking up unchanged text is a format conversion, and arguably a "derivative work that assists in implementation", but "may not be modified in any way" is exactly the kind of clause a cautious reading trips over. Three routes, in order of preference:

1. **Ask.** The IETF Trust (trustees@ietf.org) has granted permissions for tooling before, and a reader app that helps people use RFCs is squarely in the spirit of the licenses. A written permission for "publishing the text of legacy RFCs, unchanged, with added RFCXML structure markup" settles it. *Asked; the answer is what is pending.*
2. **Ship structure, not text.** If publishing marked-up text is not permitted, the pack can carry only *structure sidecars*: for each legacy RFC, the byte ranges of the original `.txt` and the role of each range (section heading with number, paragraph, list item, artwork, reference entry, cross-reference target). The app fetches or caches the verbatim `.txt` from the RFC Editor, verifies its hash against the sidecar, and applies the structure at runtime. No RFC text ever leaves the RFC Editor's servers through us, the pack is metadata about a document rather than a copy of it, and the runtime cost is trivial (applying offsets, no heuristics). `LegacyTextParser` would gain a mode that emits ranges instead of a document, and the pipeline would emit sidecars instead of XML. This is a modest change to the pipeline and none to the reader.
3. **Keep the on-device renderer forever.** If even sidecars felt too close to the line, the app fetches the `.txt` and runs `LegacyTextParser` on device, as it does today. Unfortunate, because heuristic fixes then ship with app updates rather than data updates, but entirely workable; the parser already exists and handles RFC 2616 in under a second.

Note that route 2 preserves almost everything route 1 gives: one-time offline heuristics, reviewable overrides, and verified data packs. The difference is only where the bytes of the text come from. Design the pack format so the XML pack and the sidecar pack share the manifest and delivery mechanism, and the decision can be made late.

## Pipeline stages

All stages are subcommands of `Tools/corpus-build`, a Swift package that depends on RFCKit and runs on macOS and Linux. Its `RFCCorpusKit` library holds what is a pure function of its inputs: converting one document (`DocumentConverter`), the report types and the manifest's hashing, query generation, the schema check's causes and fetch planning. The `corpus-build` executable is the command line around it: arguments, file IO, concurrency, logging and xmllint. Its three third-party dependencies are Apple's: [swift-argument-parser](https://github.com/apple/swift-argument-parser) for the commands, [swift-log](https://github.com/apple/swift-log) for their logs, and [swift-crypto](https://github.com/apple/swift-crypto) for the manifest's SHA-256 (CryptoKit on Apple platforms, BoringSSL on Linux). The logs go to standard error, one line per event, with a fixed message and the values as metadata (`documents=8457 [corpus_build] converting`), so a run's log can be grepped by message and compared field by field. An unknown or misspelled flag is an error, and `corpus-build help <command>` lists each command's options.

```
rfc-index.xml ──▶ fetch ──▶ corpus/text.noindex/rfcNNNN.txt      (8,457 files, one-time, resumable)
                              │
                              ▼
                            convert ──▶ corpus/xml.noindex/rfcNNNN.xml   (+ corpus/report.json, corpus/prose.json)
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
              split at 8650, a manifest.json of its own at each pack's root
                              │
                              ▼  (macOS job)
              aa archive -a lzfse ──▶ legacy-xml-<version>.aar  (RFCs before 8650) ──┐
                                  ──▶ modern-xml-<version>.aar  (RFC 8650 onwards)  ─┼──▶ GitHub Release / R2
                                      manifest.json of both, beside them ────────────┘
```

The packs split at RFC 8650 so that the RFC Editor's own RFCXML, already licensed for redistribution, never waits on the licensing question the converted legacy documents are held by.

- **fetch** reads the index, picks every RFC without an XML format, and downloads the `.txt` with bounded concurrency (default 6, be polite to the RFC Editor). Existing files are skipped, so re-runs only fetch what is new or missing. `--limit N` for smoke tests.
- **convert** parses each text file, serializes to RFCXML, re-parses the output as a self-check, and writes a per-document report: section, paragraph, list, artwork and reference counts plus warnings ("no RFC number recognized in front matter", "more artwork than prose", "round trip changed section count"). With `--index`, the header's title, number, authors, date, `obsoletes` and `updates` come from the document's index entry rather than its title page (`IndexHeader`); where the page states no number or another one, the report notes it ("RFC number from the index; the front matter states none") in place of the missing-number warning. With `--diagnostics` it also writes `prose.json`, what the prose test decided across the corpus and where it decided narrowly; `make corpus` asks for it. `--only 5 822` converts just those documents from `--in`, and fails if one has no text there; it refuses `--report`, which would replace the corpus report with one that holds only those documents. An override file replaces the generated output entirely, after being checked to parse. Overrides are the correction mechanism: fix the heuristic in RFCKit when a class of documents is wrong, and correct a single document with an override. No new override is committed until #197 makes one a patch on the converter's output rather than a whole converted document, which is RFC text. An override corrected mechanically rather than by hand carries the script that makes it beside it (`corpus/overrides/rfc1142.py`), and is regenerated with it when the converter's output changes: `make corpus-overrides-check` reruns every such script against the current converter and fails on any difference. It needs the source text, so it is not part of `make check`; what is, is corpus-build's `Corpus overrides` suite, which parses every committed override and pins what RFC 1142's script recovers.
  With `--schema`, every written file is also validated against xml2rfc's RFCXML v3 schema (`Tools/corpus-build/Schema/`, `xmllint --relaxng`), and the report's `schema` field says why a document fails: `[]` validates, otherwise a list of causes (`front-without-author`, `anchor-equals-pn`, …). The causes are found in the document rather than read from libxml2's messages, which cascade — one refused attribute on `<section>` was 203,612 lines over the corpus. A failure none of them explains is `unexplained`, with libxml2's first message as a warning: that bucket is where a new kind of failure shows up — in a document with no known cause. One that already has a known cause can hide a new kind behind it, so the causes say what a document contains rather than everything xmllint refused, and the bucket watches more of the corpus as known causes are fixed. Our parser round-tripping its own output never proved it was RFCXML, since it tolerates what it writes; the schema check is what does. From here on a regression is a document that stops validating: convert compares its results with the report it replaces (`SchemaComparison`) and exits non-zero, after writing the new report, when any document validated before and does not now. `make corpus` first runs `make corpus-schema-control`, which has xmllint validate RFCs 8999, 9113 and 9220 as the RFC Editor published them, so a broken schema or validator stops the run before its counts are read.
- **manifest** hashes every file so the app can verify downloads and fetch individual documents by path. It records the packs' version and, per document, its file name, size and SHA-256, and nothing of the run, so the same files make the same manifest. The type is RFCKit's `Manifest`, which the app reads, so the two sides cannot drift; the hashing is corpus-build's (swift-crypto) and the app's (CryptoKit), because RFCKit has no cryptography of its own. A pack carries a manifest of its own at its root, listing exactly its files by bare name (`rfc1.xml`), and the app verifies an installed pack against that one.

Regression review is a diff of two `report.json` files: a heuristic change that moves counts on hundreds of documents gets looked at before it ships. The reports for the 1969 RFCs already show what to expect: RFC 2 flags "more artwork than prose" (its hand-typed layout is indistinguishable from diagrams) and RFC 3 has no recognisable front matter. Those become overrides or targeted heuristics; the 1990s and 2000s RFCs, which are the bulk, follow the strict format the parser is built for.

A report diff compares a change with the heuristics before it, never with a right answer. The one right answer there is (#42) is the RFCs from 8650 on, whose text xml2rfc generated from their XML: `fetch --format modern-text` fetches that text into `corpus/modern-text.noindex/`, and `score` parses it with `LegacyTextParser`, parses the XML with `RFCXMLParser`, and compares the headings, artwork and source code of the two documents (`make corpus-score`). Blocks are matched by content, as multisets per kind, because the parser keeps no source lines to match by position. The content is normalized so that xml2rfc's rendering and the element compare equal: tabs are expanded to eight columns, a heading's superscript is written `^(8)` and its non-breaking hyphens are hyphens, and common indentation, trailing space, blank lines and the `<CODE BEGINS>`/`<CODE ENDS>` markers go, and SVG-only artwork, which the text only names, is not expected. Besides artwork, source code and headings, `verbatim` matches artwork and source code whatever they were called: plain text cannot say what is code, so a grammar the parser kept whole as artwork is a block it found, and a document's errors are counted from headings and `verbatim`. The labels are derived on every run and never committed. `corpus/score.json` holds the counts, precision and recall per kind and every document worst first, beside `report.json` rather than in it, so a diff of either is about one thing. It is a regression floor, not a measure of the legacy corpus: xml2rfc's output is uniform, and the documents that break the parser have no analogue in it.

The first run, over all 1,378:

| Kind | Precision | Recall |
|---|---|---|
| heading | 97.2 % | 97.7 % |
| verbatim | 13.7 % | 53.5 % |
| artwork | 7.6 % | 67.1 % |
| source code | – | 0 % |

The false verbatim blocks are the parser reading a hanging-indent definition list (#436), a caption (#361) or an ASCII table (#438) as artwork, and cutting one block into pieces where its indentation drops (#437).

## What we precompute, and what we never do

Rendering is never precomputed. Fonts, widths, Dynamic Type and dark mode differ per device; the app renders the model at runtime. Everything below is a model, an index or a graph.

| Pack | Contents | Raw | Shipped (LZFSE) | Delivery |
|---|---|---|---|---|
| `index` | Compact form of the RFC Editor index: metadata for all documents, series groupings | 14 MB XML | ~1 MB | **In the app bundle**, refreshed at runtime from the RSS feed and the live index |
| `graph` | Citation graph (who cites whom, from every References section), obsoletes/updates edges | a few MB | <1 MB | In the bundle or first optional pack |
| `errata` | Normalized errata: RFC, section, status, original and corrected text | 12 MB JSON | <1 MB | Bundle or fetched on first use |
| `legacy-xml` | RFCXML for the 8,457 legacy RFCs with a text file | 460 MB | 104 MB, measured | Optional download, "Read everything offline" |
| `modern-xml` | Mirror of the RFC Editor's XML for RFCs ≥ 8650 | ~60 MB | ~15 MB | Optional; otherwise fetched per document |
| `fts` | SQLite FTS5 database, one row per section, BM25 ranking, over the whole corpus | 150–250 MB | ~80 MB | Optional, requires the XML packs |
| `embeddings-abstracts` | One vector per RFC abstract | ~10 MB | ~10 MB | Optional, enables semantic search over the whole series |
| `embeddings-sections` | One vector per section, 128 dimensions, int8 | ~60 MB | ~60 MB | Optional, only with the XML packs |

Notes on individual packs:

- **The citation graph is the one thing a device cannot compute alone**: "cited by" needs every References section in the series. It is small, so it goes in the bundle or the first pack everyone gets.
- **Modern XML** is fetched per document from the RFC Editor today and cached. The pack exists only so "everything offline" is truly everything.
- **The FTS database** could be built on device from the XML packs, but that costs minutes of CPU and battery on first run; shipping it prebuilt is kinder. It is a derived artifact, rebuilt whenever the XML changes.
- **Embeddings are the search decision's** in ARCHITECTURE.md, which has the measurements. The reranker measured to help, Model2Vec, embeds BM25's top hits at query time and stores nothing, so the two embedding packs above are needed only if a search over stored vectors is ever wanted; what the reranker needs shipped is its token table. Either way the model is one we ship, never Apple's `NLContextualEmbedding`, which improved nothing when measured and is versioned per OS release, so a vector computed on a Mac may not match a query embedded on an iPhone.
- **Internet-Drafts are never packed.** The set is large and changes daily; drafts are fetched on demand.

The app bundle target is under about 30 MB: code plus the compressed index. Everything else is optional and downloaded on request or in the background.

## Delivery mechanism

- **Hosting.** GitHub Releases on this repository (or a dedicated `rfc-reader-data` repository) to start: free, CDN-backed, 2 GB per asset, and every pack is a tagged, immutable version. Move to a Cloudflare R2 bucket behind a custom domain if download volume ever matters; the manifest format does not change.
- **Manifest.** `manifest.json` carries the packs' version and every document inside the XML packs by file name, size and SHA-256. It does not list the packs themselves yet, their archives' sizes and hashes, nor which pack a document is in, which today is its number: below 8650 legacy, from 8650 modern. The app is to verify what it downloads against it, and can also fetch a single document out of a pack by path once packs are served unpacked (R2 stage).
- **On the device.** Apple's Background Assets framework is built for exactly this: large optional downloads hosted by the developer, fetched at install time or in the background, not counted against the App Store download size, with managed storage and eviction. On-demand resources are being phased out in its favor, so do not build on ODR.
- **Versioning.** Packs are versioned `YYYY.MM[.patch]`. The legacy XML pack changes only when the heuristics or overrides change, which is rare. The index, graph and errata refresh whenever the RFC Editor publishes; the FTS and embedding packs are rebuilt after any XML change.

## Automation

`.github/workflows/corpus.yml` runs `make corpus` — fetch, convert and manifest — on Linux in a read-only job, splits the output into one folder per pack with its own manifest, and hands the folders to a macOS job that archives them with `aa`; a separate job that builds nothing attaches the archives to a release, and only when asked to. A pack is an Apple Archive compressed with LZFSE (#36), because the app reads that with Apple's own frameworks and gains no dependency for it. The archive is made on macOS because nothing on Linux writes the Apple Archive container: an LZFSE library would compress, but corpus-build would have to reimplement the container, and the app would be the only test of that. It is `workflow_dispatch` only for now: a full run's `report.json` is reviewed, and what it exposes fixed in the heuristics, before anything is published. A full run's baseline is the report of the last successful full run, which only full runs upload, so a document that stops validating fails the run. Once the output is trusted, a monthly schedule picks up newly published RFCs for the index, graph and errata packs. The legacy pack's documents and its manifest then reproduce byte-for-byte unless the converter, the overrides or the index's record of a document changed — the manifest carries no date — though the archive does not: its file times record the run that made it.

The full text fetch is about 450 MB and 8,457 requests; at six concurrent connections it takes on the order of twenty minutes. So `corpus/text.noindex` is cached between runs: a full run saves it under its run ID, the next restores the newest (CI's cache pruning keeps only that one), and since fetch skips what is already there, the RFC Editor is asked only for what was published since.

`.github/workflows/revisions.yml` runs daily and on demand. It builds corpus-build and runs `corpus-build revisions`, which lists every active, adopted Internet-Draft on datatracker and reads the header of each one that changed. It uploads `revisions.json` (adopted drafts that intend to obsolete or update an RFC, which the app fetches) and `revisions-scan.json` (the scanner's record for its next run) to the `revisions` prerelease. A run that loses more than half the RFCs of the previous one fails instead of publishing; the `allow-shrink` input overrides that. See `docs/superpowers/specs/2026-09-29-rfc-revisions-design.md`.

After publishing those, the same run runs `corpus-build groups` (#363): every group the RFC index names, as datatracker describes it — name, type, state, area, current chairs by name, list archive and charter — written to `groups.json` and uploaded to the same prerelease, where the app fetches it for a working group's card. It lists all of datatracker's groups and chair roles (a few pages) and then reads one person record per chair of an active group, about 170 requests a quarter of a second apart. On 1 October 2026 the index named 531 groups, of which 530 were found, 96 of them active; the file is about 180 KB. It has the same shrink guard against its last published copy, and the same `allow-shrink` input. A failure here comes after the revisions are published, so it costs only `groups.json` that day.

## Repository layout for the data

```
corpus/                      (git-ignored working directory, or a separate data repository)
├── rfc-index.xml            snapshot used for this run
├── text.noindex/rfcNNNN.txt fetched sources, byte-for-byte as served
├── overrides/
│   ├── rfcNNNN.xml          hand-corrected documents, committed and reviewed
│   └── rfcNNNN.py           the script behind a mechanically corrected one (Python 3.9+)
├── xml.noindex/rfcNNNN.xml  generated output, and the RFC Editor's own XML beside it
├── report.json              per-document counts, warnings and schema causes
├── prose.json               the prose test's decisions (convert --diagnostics)
├── manifest.json
└── queries-xref.json        the search judgment set, from `make corpus-queries`
```

The `.noindex` suffixes keep Spotlight from indexing the pipeline's output as it is written, which held a full run to a quarter of the corpus in two hours (#38); the Makefile has the measurement. Overrides are the only part under version control; everything else is reproducible from the index and the RFC Editor.

## How the app consumes packs

1. On launch, load the bundled `index` pack; refresh from the RSS feed and live index in the background.
2. Opening a document: if a pack containing it is installed, read the XML from the pack; otherwise fetch the RFC Editor's XML (≥ 8650) or, for a legacy RFC without the pack, fall back to fetching the `.txt` and parsing on device with `LegacyTextParser`. Either way the reader sees an `RFCDocument`. Built for `legacy-xml` (#36): `DocumentStore` looks in the parsed cache, the cached XML, the installed pack, the cached `.txt` and then the network, so the pack wins over a `.txt` cached before it arrived, and that `.txt` still serves Original Text. A pack is installed from an `.aar`, a folder or a URL into `Application Support/RFCReader/Packs/<name>/`: unpacked into a staging folder beside it, verified file by file against its manifest, and only then swapped in, so a pack that fails leaves the installed one untouched. It is unpacked because an Apple Archive has no random access. So far the only way to install one is a developer's: Developer ▸ Install Data Pack… in a Debug build on macOS, or the launch argument `-installPack <url or path>`.
3. Search: metadata search always works from the index. Full-text and semantic search light up when the `fts` and embedding packs are installed; the search UI says so rather than silently returning less.
4. Settings ▸ Offline: a list of packs with sizes, install and remove, and the disk they use.

## Open work, in order

1. Fix the heuristic classes the full run's `report.json` exposes (1970s RFCs, hanging-indent definition lists). A single document that is wrong waits for #197, which makes an override a patch on the converter's output rather than a whole converted document; until then no new override is committed.
2. Add `graph` and `errata` builders to `corpus-build` (both are small transformations of data we already parse).
3. Add the `fts` builder (GRDB or the sqlite3 C library, FTS5, section rows) and the app-side reader.
4. Pick and convert the embedding model; add the `embeddings` builders; hybrid rerank in the app.
5. Background Assets integration and the Offline settings screen.
6. Resolve the licensing question for public distribution of `legacy-xml`: the Trust has been asked; if the answer is no, fall back to structure sidecars.
