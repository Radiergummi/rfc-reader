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
- The title is the number as the heading names it, then the heading: `10.2.3 Retry-After`, `Appendix A Collected ABNF`. The full-text index keeps each section's label and display title for this (its version 4).
- The description is `RFC 9110: HTTP Semantics`. The document's number spellings are not keywords of a section, so a search by number finds the RFC's own item first rather than every section of it; the section's number is (`Appendix A`, `§10.2.3`).
- The section's own text is searched but not shown.
- Each item carries its `SectionEntity`, titled and linked as the section query's entity for it is, so a result is the section Shortcuts and Siri act on.
- A chosen result opens through `SpotlightEntry.link(from:)` as a `rfc://` link to the anchor would: by its number where the anchor spells one, else at the anchor.
- The items are in their own named index, `rfc-sections`, and have no expiry: a section leaves Spotlight when its body leaves the app, not when CoreSpotlight's 30-day default runs out.

What Spotlight holds is kept to that set by a comparison, not by events. After each change to the full-text index, `SpotlightSection.Plan` compares the documents held, each with when its body was written, against a record of what Spotlight holds.
1. The documents that are gone, whose body was written again, or that were indexed only in part are deleted, in a batch of their own when there are any.
2. The new ones are indexed in `SpotlightSection.Batches`, at most 500 sections each, a large document's cut across batches and recorded as partial until its last.

Indexing is coalesced: a change during one runs one more once it is done, and no batch is thrown away.
Only making the items is on the main actor, because each carries a `SectionEntity`; reading the rows, cutting the batches and writing the record are not.

The body's date does not change everywhere the rows do, so two more things rebuild Spotlight's sections from nothing.
The record's format carries the full-text index's version, whose change empties that index and indexes its documents again under the dates their bodies had.
Installing the legacy pack does the same for the RFCs then read from it, with its anchors, and the app rebuilds Spotlight's sections after it.
A document Index All RFCs indexed stays in the full-text index when its body is evicted; the reconcile counts that as a change, so its sections leave Spotlight then.

The record is a file beside the full-text index (`spotlight-sections.json`), not Spotlight's client state.
A probe on macOS 27 found that `endBatch(withClientState:)` accepts 1,024 bytes and refuses 2,048 with `CSIndexErrorDomain` -1002. A record of 329 documents is 9 KB.
The record is written before each batch, and the client state written with the batch is the record's SHA-256 digest.
If a batch fails, the record and its digest no longer match, so the next indexing empties `rfc-sections` and indexes everything again rather than trust the record.
A format marker in the record does the same when what an item carries changes.

## What was measured

Release build, Apple M3 Pro, 3 November 2026, with the "Index sections for Spotlight" and "Make section items" signposts:

- **The cache:** a test copy's cache of 329 RFCs, every 30th of the index, legacy and XML alike, 57 MB of cache.
- **One full indexing** (the record removed, so everything is indexed again): 10,132 sections in 21 batches of at most 500, in 7.1 s, of which the batches' round trips to the Spotlight daemon are nearly all.
- **The main thread:** making the items there, as `SectionEntity` requires, took 182 ms in all, at most 17 ms per batch.
- **Filling the cache:** the indexings that ran as the 329 documents arrived, coalesced, had no batch refused.
- **Launches after the first:** with nothing changed, they compare the record and do nothing.
- **Scale:** the cache's 500 MB bound, filled with documents like these, would be on the order of 90,000 sections and about a minute of background indexing, done once, then a document at a time.
