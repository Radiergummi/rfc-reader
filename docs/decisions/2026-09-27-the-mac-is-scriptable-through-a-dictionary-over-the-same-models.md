# The Mac is scriptable through a dictionary over the same models

*Decided September 2026 (issue #269).*
`App/RFCReader/Scripting/RFCReader.sdef` makes the Mac app scriptable with AppleScript and JXA.
A script can open an RFC by number, name or link, in the front tab, a new tab or a new window.
It can go back, go forward or jump to a section, show the inspector and choose its pane, and bookmark an RFC.
Each window's collection and search text can be read and set, and so can the RFCs its list shows.
The dictionary is a Mac's alone: iOS has App Intents, and the file is left out of the iOS build.

Cocoa Scripting resolves everything by key-value coding, so the pieces sit where the keys lead.
An RFC is a `ScriptableRFC`, named by its number (`rfc id 9110`) from the application's `rfcs`, which `AppDelegate` answers.
A window's properties are `ReaderWindow`'s, since every window and tab is one.
The commands are `NSScriptCommand` subclasses.
None of them decides anything.
They call what the menus and toolbar already call: `LibraryModel.open(_:placement:)`, `NavigationModel`, `ReaderWindowController.setPanelOpen(_:)`, `BookmarkStore`.
A script can only read a window's list because the list is computed in the model, not in its view (#280).

What does need deciding is in `RFCReaderKit` and tested there.
`LibraryFilter(scriptName:workingGroups:)` turns a name into a collection, and every collection's title round-trips.
`DocumentReference.link(from:section:)` turns a reference into a link, and Go to RFC (the Mac's palette, the iOS sheet) uses it too, so they accept the same input.
`LibraryFilter` moved into the package for this.

A collection or document a script names wrongly is an error to the script, in words, not an empty list or a no-op.
`listed rfcs` is a list-valued property rather than an element, so AppleScript needs `get` before indexing into it (`item 1 of (get listed rfcs of front window)`).
