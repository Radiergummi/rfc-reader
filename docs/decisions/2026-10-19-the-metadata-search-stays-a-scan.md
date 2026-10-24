# The metadata search stays a scan

*Decided 19 October 2026 (issue #37, its step 4; the maintainer's answer is recorded on the issue).*

The metadata search, `IndexSearch` over the RFC index's numbers, titles, keywords, authors, working groups and abstracts, stays what it is: a scan of every entry per query, in memory, with no index.
It does not move into the full-text database, which closes #37 without its fourth step.
The decision of #605 and #118 still holds as a rule: if the metadata ever gets an index, it goes into the FTS5 database, not a hand-built inverted index. What was measured here says it does not need one.

## What was measured

**Today's scan.** The "Search" benchmarks of `make benchmark`, over the real index, Release, Apple M3 Pro, on 2026-10-02 (pull request #626):

| Benchmark | p50 | p99 |
|---|---|---|
| Search: author:fielding | 0.48 ms | 0.79 ms |
| Search: http | 4.4 ms | 6.1 ms |
| Search: transport layer security | 5.6 ms | 6.9 ms |

Run again for this record on 2026-10-24 (`make benchmark-core BENCHMARK_ARGS='--filter "Search.*"'`), the fastest of 50 samples agreed: 0.92 ms, 4 ms and 7 ms.
Its medians do not count: the machine was running other builds at a load average of about 400, which spread the samples from those to 15, 53 and 139 ms.

**The scan moved into FTS5.** A probe over the same index (`corpus/benchmarks/rfc-index.xml`, 9,842 entries), on 2026-10-19 (the step 4 design comment on #37): SQLite 3.54, run from Python with `bm25()` ordering, p50, so indicative only.

| | the scan (#626) | FTS5, `unicode61` | FTS5, `trigram` |
|---|---|---|---|
| `http` | 4.4 ms | 2.1 ms | 0.7 ms |
| `transport layer security` | 5.6 ms | 1.8 ms | 6.5 ms |
| `author:fielding` | 0.48 ms | a filter, not FTS | a filter, not FTS |
| build | part of "Index: prepare" | 1.0 s | 4.6 s |
| on disk | none | 13 MB | 32 MB |

Either way, both sides fit well inside a frame.

**The hits change.** The scan matches substrings; `unicode61` matches words and word prefixes.
Under it `tls` loses 26 RFCs (the DTLS ones), `dns` loses 29 (mDNS, IDNs), `ipv6` loses PMIPv6, and `negoti` loses "renegotiation" and "autonegotiation".
`trigram` keeps today's hits for terms of three characters or more, matches nothing shorter (`ip`, `5g`), and is the slower and the larger of the two.

## Why it stays

The move would make no difference a person could notice, and it costs:

- **A dependency the search does not have.** The full-text database is one the person can remove (Remove Full-Text Index), and one that can fail to open. The metadata search depends on the RFC index alone, which every list needs anyway, so it works whatever has happened to the full-text index.
- **An async search.** `IndexSearch` is a `Sendable` value called synchronously: by `ListedRows` for every list, the sidebar's included; by `LibraryModel.listedNow` on the main actor, for scripts; by the palette, the App Intents and every query collection; and by `LibraryList.textQuery`, to say which RFCs a section hit may be in. Each would go through `TextIndexer` or need a connection of its own.
- **Different hits, or a slower and larger index.** Either the substring matches above are lost, or `trigram` is 2.5 times the size and blind to two-letter terms, which the scan would then still have to answer: two search paths instead of one.

The section ranking is not touched by this: it stays flat BM25 ([the 7 October decision](2026-10-07-full-text-search-is-built-on-the-device-and-ranked-flat.md)), and anything more is #739's.

## When to look at it again

When a query leaves the frame budget on a device the app supports: a "Search" benchmark of `make benchmark` whose p99 passes 8 ms (a frame at 120 Hz) on the Mac, or the "List" signpost, which carries the query, passing a frame in a trace (`make trace`, or Instruments on an iPhone).
The index grows by a few hundred entries a year, so that is far off unless the scan's own work grows: a new field searched, or a matcher costlier than a substring.
A search that needs what only FTS5 gives, such as ranking the RFC rows by BM25 with the section hits, would also reopen it, as a decision of its own.
