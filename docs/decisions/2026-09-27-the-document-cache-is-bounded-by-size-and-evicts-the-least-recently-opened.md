# The document cache is bounded by size, and evicts the least recently opened

*Decided September 2026 (issue #39).*
Nothing removed a cached body except an explicit Remove Download, and a whole library is about 3.5 GB at the ~370 KB per document measured.
The cache is now bounded at 500 MB (`CacheEviction.defaultBound`, about 1,350 documents).
The bound is on size, not age: a document read once a year is worth keeping while there is room, and evicting it by age alone saves nothing.
Past the bound, the least recently *opened* documents go first, ties in document order, until what is left fits.
A document is its bodies together, so its `.xml` and `.txt` go at once, and its size is their sum.
Data packs (#36) do not count against the bound.

Some documents are pinned and never go: bookmarks, because a bookmark is a promise to keep the document offline; anything with a reading position from the last 30 days; and every window's selection, which includes the document just fetched. When the pinned documents alone are over the bound, everything else goes and the cache stays over it; saying so is the Storage settings' job (#32).

"Last opened" is the bodies' modification date.
A body is never modified after it is written, so the date is free to carry that meaning, and unlike a table in memory it survives a relaunch; setting a file's date does not change its directory's, so it does not send `DocumentCacheIndex` to scan again.
Which files are entries is the index's own naming rule, `DocumentCacheIndex.document(named:)`, and the choice of victims is `CacheEviction` in `RFCReaderKit`, a pure function with tests.
The store runs it only after it has written a body, and `LibraryModel` asks before building the pinned set, so an open that wrote nothing costs neither the SwiftData fetches nor the enumeration.
Removal goes through `remove(_:)`, which keeps the index and the parsed-document cache right.
