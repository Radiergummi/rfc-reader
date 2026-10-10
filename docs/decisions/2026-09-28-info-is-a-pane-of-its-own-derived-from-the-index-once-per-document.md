# Info is a pane of its own, derived from the index once per document

*Decided September 2026 (issue #25).*
The inspector shows what the index knows about a document that is not its prose: its number, title and standing; a strip of key facts (year, pages, stream, working group); authors; obsoletes, obsoleted by, updates, updated by and the other members of its series, each drawn as the reader's own chip and opening in the reader the way a reference does; the errata, rfc-editor.org and Datatracker pages and the DOI, as rows with an icon; and the details the header and the strip leave out (full date, the status it was published as where that differs, area, keywords, formats).
What goes in it is `DocumentInfo` in `RFCReaderKit`, a pure function of `RFCMetadata` and the index, tested there.
A field the index lacks has no fact or row and a section with no rows is not shown, so a legacy RFC's pane is short rather than a column of dashes.
`DocumentSession` derives it into `ReaderState.info` before the body is fetched, and again whenever the index loads or refreshes, for a document opened before the index finished loading and for a series whose members changed; never in a view body, which the reader re-evaluates on every section crossing.

It was first a third tab beside Contents and References, and moved out because those two are ways of navigating the document and this is about it.
Each is now a pane (`InspectorPane`) with its own toolbar button (Contents ⌥⌘I, Info ⌘I, Get Info's chord), sharing the one inspector slot as Pages' Format and Document buttons do: a button opens a closed inspector on its pane, swaps an open one to it, and closes the one already showing it.
That rule is `InspectorPane.pressing`, tested; the Mac's window controller and the iOS toolbar both apply it.
The layout follows Books and the App Store's item pages rather than a label-and-value list.

The panel does not wait for the body (#325): it opens on `ReaderState.canDescribe`, which the index's entry sets as well as the body, so a document still loading, or one that failed to or was offline, has its Info pane, and an open panel stays open from one document to the next.
Without the body, the navigation pane's tabs show progress while it loads (`ReaderState.isLoading`, fed from `DocumentSession`'s load state) and say the document hasn't loaded once the load has failed, rather than showing empty lists; which pane has content is `InspectorPane.hasContent`, and what the navigation pane shows is `InspectorPane.navigationContent`.
The toolbar title, printing and export still wait for `hasDocument`.
The one part that is the store's rather than the index's, the offline copy's size and Remove Offline Copy, is read by the view itself when the pane shows and whenever the library's downloads change, which a removal does.
Removing the copy leaves the document on screen, since it is already in memory, and says so, because otherwise the button looks as if it did nothing.
AppleScript's `inspector pane` enumeration names the pane `information`, since Standard Additions already owns `info`.
