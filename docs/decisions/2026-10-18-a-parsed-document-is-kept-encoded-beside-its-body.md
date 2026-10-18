# A parsed document is kept encoded beside its body

*Decided October 2026 (issue #606, design on #118).*
The store kept the last eight parsed documents in memory, so any other open, and every open after a relaunch, parsed its body again.
Now a parse of a body on disk, or of one just fetched, is written beside the body as JSON, `rfc9110.model.json`, and an open the in-memory cache misses decodes it instead of parsing.

## What was measured first

The rule, set before measuring: a source format gets the cache only if decoding its model is at least twice as fast as parsing it.
`make benchmark`'s "Decode JSON" and "Decode property list" against "Parse XML" and "Parse text", Release, median of 50 runs (13 for RFC 5661's parse), on an Apple M3 Pro, 2026-10-18:

| Document | Parse | JSON decode | Binary property list decode | JSON size / source size |
|---|---|---|---|---|
| RFC 9110, XML | 75 ms | 29 ms (2.6×) | 53 ms (1.4×) | 0.79 |
| RFC 9000, XML | 45 ms | 19 ms (2.4×) | 35 ms (1.3×) | 0.95 |
| RFC 5661, text | 743 ms | 35 ms (21×) | 63 ms (12×) | 1.26 |
| RFC 793, text | 86 ms | 4.7 ms (18×) | 8.2 ms (10×) | 1.21 |

So both formats qualify, with JSON, which decodes in about half the time of a binary property list.
The issue expected XML not to gain; it does, by a little more than the bar.

## How it is kept

- **Keyed by the app's build and the body.** A model records the `CFBundleVersion` that wrote it and the creation date of the body it was parsed from, read before the body. Either differing, it is parsed again and written over. So no version constant has to be remembered when the model or a parser changes; the price is that every new build parses each document once more. Every local build is build 1 (`project.yml` sets `CURRENT_PROJECT_VERSION` only in the release workflow), so the build also carries its executable's modification date: without it, a parser fixed in a local build would never reach a document an earlier one had parsed. A body written again is a new file, with a new creation date; a move between the tiers keeps it.
- **Beside its body, in its tier.** The model is one more file of the document's, moved with it between the reading cache and the kept tier and removed with it, by eviction, Clear Cache or a removal. It counts toward the reading cache's bound and the Storage tab's sizes, but never makes a document cached on its own: `DocumentCacheIndex` counts bodies only.
- **Written off the actor**, one write after another as the index snapshot's are, once the open has its document. A body removed while its model was encoded gets no model.
- **Not for a document read from the legacy pack**, whose XML is no body of either tier. With a pack installed, those documents parse as before.

The encoded form is still not a format ("The document model is a value, and its encoding is internal"): a model from another build is discarded rather than migrated.
