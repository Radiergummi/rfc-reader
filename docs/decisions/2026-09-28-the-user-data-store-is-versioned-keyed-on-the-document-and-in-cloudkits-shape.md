# The user data store is versioned, keyed on the document, and in CloudKit's shape

*Decided September 2026 (issue #152).*
Bookmarks and reading positions keyed on a bare, unique RFC number, which cannot tell RFC 1 from BCP 1, and the schema had no version, so any change to it was a store that would not open.
The models are now `VersionedSchema`s in `RFCReaderKit` (`UserData.swift`), where the migration is tested against a store written on disk.
`SchemaV3` keys each row on the document's `fileStem` and is in CloudKit's shape: no `@Attribute(.unique)`, every attribute optional or defaulted.
Uniqueness is the code's job instead: `BookmarkStore` looks a document up before inserting, and `UserData.deduplicate` merges rows naming one document, newest first, when the container opens.
The one the app uses is `SchemaV4`, which keeps V3's keys and adds collections (below).

The migration never takes a row out of the store.
SwiftData's inferred step cannot turn a number into a key, so `SchemaV2` is only a step: V1's rows, with V3's columns beside the number.
V1 to V2 is inferred; V2 to V3 writes each row's key from its own number and then drops the number.
A launch that stops between the two leaves a V2 store, and the next one finishes the job.
An earlier draft carried the rows across one custom stage in memory, which a crash between its halves would have lost for good.
A V1 row is read as an RFC, since a number is all it kept.
