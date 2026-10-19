# A draft is a document of its own

*Decided 16 October 2026 on #734, the drafts epic, with #728, #729 and #196.*

The reader opens an Internet-Draft as it opens an RFC, and a draft is identified by a type of its own, `DraftID`: a name and an optional two-digit revision, `draft-ietf-httpbis-semantics-19`, or the name alone for the newest. A fifth `DocumentID.Series` was the alternative. `DocumentID` is a series and a number, and the index, citations, the library and the user data all assume a document has one, so a draft there would have been a document with a name in place of a number, touched by every one of them. Instead, what reads either — the reader, its history and stack of readers, the routing of links, the reading positions and the draft cache — takes a `ReadableDocument`, `.rfc(DocumentID)` or `.draft(DraftID)`, and everything else keeps its `DocumentID`. The user data already keys a row by a string, `fileStem`, so a draft's reading position is a row keyed by its name and revision, which no `DocumentID` reads as its own: Recently Read never lists a draft.

The app's own link to a draft is `rfc://draft-…`, the draft's name as the host, and without `-NN` it opens the newest revision. A draft's name always starts with `draft-`, so it cannot be read as an RFC number or a series, and `rfc://draft-…` never collides with `rfc://9110` or `rfc://bcp14`.

The diff between two revisions, and between a draft and its RFC (#729), is a redline in the reader's one text storage: the newer text, with what was inserted and deleted marked in it, built by `DocumentTextBuilder` from a diff model. Two revisions side by side, with #187's coupled scrolling, was the alternative; it shows each change twice and needs a window wide enough for two columns, which an iPhone's is not.

SwiftUI has a `ReadableDocument` protocol of its own, for document-based apps, which this one is not; the App target names RFCKit's at its module's scope, so the name means RFCKit's in every file there.
