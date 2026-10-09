# Full-text search is built on the device, and ranked by flat BM25

*Decided 7 October 2026 (issue #37), superseding the ranking of [the 24 September decision](2026-09-24-full-text-search-ranks-by-measurement-and-was-measured-before-it-was-built.md), whose measurements stand.*
The full-text index is built on the device, from the documents the app has downloaded and parsed, and not shipped as a pack: a pack carries RFC text, which waits on the licensing question (#215), and an index built from documents each device fetched from the RFC Editor redistributes nothing.
It indexes what the app holds, a document added when its body is stored and removed when it is evicted, and the whole corpus only when the person asks for it ("Index All RFCs"); that run keeps each section's text in the index and discards the bodies it downloaded, so snippets need no body, eviction cannot undo it, and the cache's bound is unchanged, at the cost of an index of a few hundred megabytes, which Settings states (the maintainer's choice).
A change to what the index holds empties it when it is opened: the app indexes its stored bodies again, and a corpus-wide index has to be made again by the same run.

It is SQLite FTS5, one row per section, ranked by flat BM25: no heading weight, no stopwords dropped, no obsolete penalty (the plan on #37).
The 24 September record adopted all three, and its own hand-written query set disagreed about the heading weight; the first version starts from the plain ranking, and any of the three comes back only through the instruments of that record (#739).
Bibliography sections stay out, as before, and so does a back-of-book index: a list of titles or of terms answers no question. The abstract is a row of its own.

SQLite is reached through a `CSQLite` system-library target in RFCKit, the system's library on every platform, rather than GRDB: corpus-build's index database reached it that way already and now does through RFCKit's target, it adds no dependency, and RFCKit stays testable on Linux, where GRDB's support is unofficial. (The app's citation index imports the SDK's `SQLite3`, the same library.)
A query is the person's words, each passed to FTS5 as a string, never FTS5's own syntax, so a stray quote or an operator's spelling searches for what is there rather than throwing; a quoted run is a phrase.
