# The document cache is indexed in memory, and revalidated by the directory's date

*Decided September 2026 (issue #39). Amended November 2026: the bodies have folders of their own since the storage tiers (#810), so the files kept beside them no longer change the date the index compares (#758).*
Which documents are downloaded was answered from the file system: `DocumentStore.cachedNumbers()` enumerated the cache directory and parsed every name, and the list calls it on every filter change, so the Downloaded filter paid for a scan that grew with what it served.
The store now scans once, on first use, into a `DocumentCacheIndex` (in `RFCReaderKit`, because which names count is the part worth testing), and answers from memory.
A name counts only when it is exactly what the store writes, a document's `fileStem` plus `.xml` or `.txt`: `rfc-index.xml` sat in the same directory then, and `rfc0791.txt` parses as RFC 791 but is not a file `remove` would ever delete.

The trade-off is staleness.
An index is a copy, and the store is not the only thing that can change the directory: it is in Application Support, and Finder will delete from it.
Two rules keep the copy honest.
Every write and removal goes through `update(_:by:)`, which records what the change *left on disk* rather than what it meant to do, so a body that could not be deleted stays downloaded — it is still what `document` reads.
And every question starts with `revalidate()`, which compares the directory's modification date with the one recorded when the index last matched it and scans again only when they differ.
That is one `stat` per filter change instead of an enumeration.
`update` revalidates before its change and records the date after it, so the store's own writes cost no scan and cannot absorb a change made before them.
Each tier's bodies are in a folder of their own, `Offline/` in Application Support and `Documents/` in Caches, so writing the RFC index, its snapshot or the data files kept beside them (the revisions, the working groups, the errata, the registries) changes neither folder's date and costs no scan.

What is left: two changes within one tick of the file system's clock share a date, so a deletion in the same instant as the store's own write can go unnoticed until the next change or launch. A file-system watcher would close that and report changes sooner, and was not worth a live source kept for a list nobody may be looking at.
