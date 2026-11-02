# Spotlight indexes the sections of the documents the app holds

*Decided and built November 2026 (issue #178, its second half; the design comment and the maintainer's answers are on the issue).*

Each section of a document the app holds a body of is a Spotlight item, so system search, Siri and Shortcuts find a passage, not only an RFC.
"Holds a body of" means the reading cache and the kept-offline tier. That is the set the full-text index takes from stored bodies, and so what the app's own full-text search covers.
What Index All RFCs indexed without keeping a body is left out: it is on the order of hundreds of thousands of sections, and the app searches it already.
Cache eviction decides what is in the set, with its bound and its pins (bookmarks, documents read in the last month, Keep Offline, annotations, open windows). Nothing new decides it.

An item is one row of the full-text index, read back from it (`FullTextIndex.indexedRows`), so no document is parsed again for Spotlight.
- The abstract is left out, because the RFC's own item indexes it.
- The identifier is `SectionIdentifier` (`rfc9110#section-10.2.3`), the stable anchor.
- The domain is `rfc-sections.rfc9110`, one per document, so a document's items are deleted together.
- The title is the number and heading, and the description is `RFC 9110: HTTP Semantics`.
- The section's own text is searched but not shown.
- Each item carries its `SectionEntity`, so a result is the section Shortcuts and Siri act on.
- A chosen result opens at its anchor through `SpotlightEntry.link(from:)`, the way a `rfc://` link does.
- The items are in their own named index, `rfc-sections`, and have no expiry: a section leaves Spotlight when its body leaves the app, not when CoreSpotlight's 30-day default runs out.

What Spotlight holds is kept to that set by a comparison, not by events. After each change to the full-text index, `SpotlightSection.Plan` compares the documents held, each with when it was indexed, against a record of what Spotlight holds.
1. The documents that are gone or were indexed again are deleted.
2. The new ones are indexed, a batch at a time.

An indexing under way gives way to the next one at a batch boundary.

The record is a file beside the full-text index (`spotlight-sections.json`), not Spotlight's client state.
A probe on macOS 27 found that `endBatch(withClientState:)` accepts 1,024 bytes and refuses 2,048 with `CSIndexErrorDomain` -1002. A record of 329 documents is 9 KB.
The record is written before each batch, and the client state written with the batch is the record's SHA-256 digest.
If a batch fails, the record and its digest no longer match, so the next indexing empties `rfc-sections` and indexes everything again rather than trust the record.
A format marker in the record does the same when what an item carries changes.

## What was measured

Release build, Apple M3 Pro, 3 November 2026, with the "Index sections for Spotlight" and "Make section items" signposts:

- **The cache:** a test copy's cache of 329 RFCs, every 30th of the index, legacy and XML alike, 57 MB of cache.
- **One full indexing:** 10,132 sections in 19 batches, in 12.9 s, of which the batches' round trips to the Spotlight daemon are nearly all.
- **The main thread:** making the items there, as `SectionEntity` requires, took 199 ms in all, at most 26 ms per batch.
- **Launches after the first:** with nothing changed, they compare the record and do nothing.
- **Scale:** the cache's 500 MB bound, filled with documents like these, would be on the order of 90,000 sections and two minutes of background indexing, done once, then a document at a time.
