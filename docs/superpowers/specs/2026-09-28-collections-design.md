# Custom collections — design

*28 September 2026. Approved in brainstorming (issue #349), revised after an adversarial review;
implementation plan to follow.*

## Why

The library can be browsed by what the index says about a document — its stream, status or
working group — and by what the reader has done with it — bookmarked, read, downloaded. There
is no way to gather documents by what they mean to the reader. Collections are that: named,
user-made lists of RFCs in the sidebar, with the folder controls Notes has.

They serve three uses, which the design has to hold together:

- **Project reading lists.** "Everything for my HTTP/3 server", added to while reading.
- **Topic grouping.** Organising the library by subject, which means one document may be in
  several collections.
- **Ordered reading paths.** A sequence read in order, which means the order is the reader's
  own, set by hand. Issue #189 builds such paths automatically; these are made by hand.

Sharing a collection with someone else is not part of this, but the model must not rule it
out: a collection has to be describable as a name, a colour and an ordered list of
designations, which any later export format can carry.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Membership | A document may be in any number of collections. | Topic groups overlap; one RFC serves several projects. |
| What is collected | RFCs only. A BCP or STD opened from the reader resolves to its first member RFC, as `NavigationModel.open` already does, and that RFC is what is added. | The index lists RFCs (`RFCIndex[id]` answers nil for a series); every other list is RFCs too. The stored key stays a `fileStem`, so a later export can carry any designation. |
| Order | Manual, new items at the end, reorderable. Newest/Oldest First are view options on top. | Reading paths need the reader's order; a large topic collection still wants to be seen by date. |
| Bookmarks | Stays separate and unchanged. | Bookmarking is one-tap "keep this"; a collection is a deliberate, named list. No migration of existing bookmarks. |
| Nesting | Flat. | Nesting brings reparenting, cycle checks and "what does a parent list" for little gain now. A parent can be added later as an optional attribute. |
| Colour | One of a fixed palette of system colours, stored by name. | Adapts to dark mode and increased contrast, and syncs as a word. |
| Platforms | iOS and macOS together. | The model and list logic are shared; once sync is on, lists made on one platform must be visible on the other. |
| Name | "Collections" in the interface. Scripting keeps "collection" for every sidebar entry, user-made ones included. | Matches the user's wording. Scripting's existing term already means "a thing the sidebar lists". |

## Model

### Schema

`SchemaV4` in `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift` declares its own
nested copies of every model, as V1 to V3 each do: `Bookmark` and `ReadingPosition` identical to
V3's, and two new ones. Reusing V3's classes across schema versions is a known source of
staged-migration failures in SwiftData, so V4 does not. All are in CloudKit's shape: no
`@Attribute(.unique)`, every attribute optional or defaulted.

```swift
@Model public final class DocumentCollection {
  public var identifier: UUID = UUID()
  public var name: String = ""
  /// A `CollectionColor` raw value. An unknown name reads as the default.
  public var colorName: String = CollectionColor.default.rawValue
  /// Where the collection sits in the sidebar, ascending.
  public var position: Double = 0
  public var createdAt: Date = Date.distantPast
}

@Model public final class DocumentCollectionItem {
  public var collectionIdentifier: UUID?
  /// The document's `fileStem`, as `Bookmark.documentKey` is: `rfc9110`.
  public var documentKey: String = ""
  /// Where the item sits in its collection, ascending.
  public var position: Double = 0
  public var addedAt: Date = Date.distantPast
}
```

The names avoid `Collection`, which is Swift's own protocol; the interface still says
"Collection". Every insert sets `createdAt` and `addedAt` to now: `distantPast` is only the
default CloudKit's shape requires, and the integrity rules below depend on real dates.

**Membership is by identifier, not a SwiftData relationship.** Each item is an independent row
naming its collection. Two devices adding to the same collection each insert a row, and nothing
is lost when they meet. A relationship would make the collection's to-many side the thing two
devices both edit.

**Order is `(position, addedAt, documentKey)`**, ascending, everywhere an order is read. The
tie-break makes two items that ended up at one position — two devices appending offline both
write "after the last" — sort the same way on every launch and every device.

**Positions are `Double`s** so an item can move between two neighbours by taking their
midpoint, writing one row. When the gap is too narrow to split, or the neighbours are equal,
the collection is renumbered in one pass first.

**Accepted under sync:** a reorder on one device racing a renumber on another may leave one
item in a stale place, since CloudKit resolves conflicts per record. The reader moves it again.
No attempt is made to prevent this.

### Files the schema change touches

- `UserData.swift`: `SchemaV4`; the public typealiases (`Bookmark`, `ReadingPosition`, and new
  `DocumentCollection`, `DocumentCollectionItem`) point at V4; `UserDataMigrationPlan.schemas`
  gains V4 and `stages` a lightweight V3 → V4 stage, which only adds entities; `UserData.container`
  opens `SchemaV4` instead of the hard-coded `SchemaV3`.
- `App/RFCReader/Model/AppData.swift`: the in-memory fallback's warning (`storeWarning`) names
  collections alongside bookmarks and reading positions.

### Integrity

`UserData.deduplicate`, which runs when the container opens, also removes items naming the same
document twice in one collection, keeping the one with the earliest `(addedAt, position)`, so
the place the reader first gave it survives.

**It does not remove items whose collection is missing.** CloudKit imports in batches without an
order guarantee, so a device can hold another device's new items before their collection
arrives; deleting them as orphans would sync the deletion back and empty the collection where
it was made. An item without a collection is harmless: every list and count is computed per
existing collection, so it is never shown. Deleting a collection locally deletes its items in
the same save. A sweep of true orphans, with a grace period, belongs to the sync work.

Two collections with the same name are allowed: names are labels, identifiers are identity.

## RFCReaderKit

Everything that decides an outcome lives here and is tested, as `CLAUDE.md` requires; the App
target keeps only views and wiring.

### `CollectionStore`

Mutations on a `ModelContext`, the way `BookmarkStore` works but in the package, tested against
a store on disk as `UserData.deduplicate` is:

- `create(name:color:)` — trims the name; refuses an empty one; appends at the end of the
  sidebar; returns the collection.
- `rename`, `setColor`, `delete` — delete removes the collection and all its items in one save.
- `add(_:to:)` — appends at the end; adding a document already in the collection changes
  nothing.
- `toggle(_:in:)` — removes **every** item naming the document in that collection, or adds it;
  answers the state it leaves.
- `move(_:in:after:before:)` — places a document between two neighbours named by document, not
  by row offset; renumbers first when `CollectionOrder` says so.
- `moveCollection(_:after:before:)` — the same for the sidebar.

Removals register with the context's `undoManager`, so a mistaken removal from a reading path
comes back at its old position rather than at the end.

### `CollectionOrder`

Pure arithmetic: the position after the last; the midpoint of two neighbours; whether a gap is
too narrow or the neighbours equal, so a renumber is due; and the renumbering itself, which
keeps the `(position, addedAt, documentKey)` order and spaces positions evenly.

It also maps a move made in a **visible** list onto real neighbours. The visible list may hide
obsolete documents or only hold the rows paged in so far (`ListWindow`), so a move is resolved
by the documents above and below the drop point in the visible list, then placed between those
two in the full collection, never by offset.

### `CollectionColor`

An enum of named system colours — blue, green, orange, red, purple, pink, teal, yellow, grey —
with `default` blue and `init(name:)` falling back to the default for a name it does not know,
which is what a newer device may sync to an older one.

### `CollectionSnapshot`

What the app reads collections through, built from one fetch: the collections in sidebar order
with name and colour, and for each its members as ordered RFC numbers. Value-typed, `Sendable`
and `Equatable`, so the app can publish it only when it changed. Tested: order, the tie-break,
items of a missing collection ignored, duplicate items collapsed.

### Filters, lists and options

- **`LibraryFilter.collection(UUID)`** — a new case. It fixes no status or working group, is
  not in order of publication, and `includes` answers nil for it. Its `title` is the empty
  string, and nothing shows it: every place that shows a filter's title goes through
  `LibraryModel.title(for:)` (below).
- **`ListOptions`** gains `collectionOrder` — Manual, Newest First or Oldest First, defaulting
  to Manual — read only by a collection's list, and separate from `order` so a tab set to
  Oldest First for the library still opens every collection in its own order. For a collection,
  Newest and Oldest First **sort by publication date**, then number; they do not reverse the
  manual order. `showsObsolete` applies as elsewhere. `YearSections.apply` answers false for a
  collection. Tested: each order, and that the library's Oldest First leaves a collection alone.
- **Reordering is allowed** only in Manual order and without a search, whose results are in
  order of relevance. A pure `canReorder` answers it and is tested.
- **A deleted selection** — `KeptFilter`, beside `KeptSelection`: given the selected filter and
  the snapshot, the filter to show, which is `.all` when the selected collection is gone,
  whether deleted in another tab or on another device.
- **Scripting names** — `LibraryFilter(scriptName:workingGroups:collections:)` resolves in this
  order, first match wins: the fixed collections and streams, a series (`BCP 14`), a working
  group, then a user collection, and among collections of one name the first in sidebar order.
  So no existing script changes meaning; a collection named "Bookmarks" or "httpbis" cannot be
  reached by name, which the dictionary says.

## App

### `LibraryModel`

- **An observable `collections: CollectionSnapshot`**, refreshed the way `bookmarkedNumbers`
  is: fetched on `ModelContext.didSave` and published only when it differs. `didSave` fires on
  every reading-position save too, so the fetch uses `propertiesToFetch` and the comparison is
  what keeps a reading-position save from re-rendering the sidebar. The snapshot serves the
  sidebar and its counts, a collection's list, the reader's checkmarks, the Mac menu bar (whose
  commands can observe a model but not a fetch) and scripting.
- **`title(for: LibraryFilter) -> String`** — the collection's name from the snapshot for a
  collection, `filter.title` for everything else. Every place that shows a filter's title uses
  it: the Mac window and tab title and list title (`ReaderWindowController`, where it is read
  under `withObservationTracking`, so a rename shows at once), `ContentView`'s scene title,
  `RFCListView`'s navigation title, search prompt and empty state, `SidebarView`, and the
  scripting getter, so a script that sets a collection reads its name back.
- **The list** — `computeList` handles `.collection` by the snapshot's member numbers, in order,
  through the index. `ListKey` carries those numbers for a collection filter (empty otherwise),
  so adding, removing or reordering changes the key and the cache cannot serve a stale list.
- **The selection** — when the snapshot changes, each scene's filter goes through `KeptFilter`.

### Sidebar

- A **Collections** section below Library and above Browse, hidden while there are none. It
  collapses and remembers it, like the other sections.
- Each row: `folder` tinted with the collection's colour, and the name; on iOS also the count,
  as the other rows have. On the Mac, where the sidebar's icons are untinted so a selected row
  turns them white, the tint applies only while the row is not selected.
- **New Collection** (`folder.badge.plus`) opens a sheet: a name field, focused, and a row of
  colour swatches. **Create** is disabled while the trimmed name is empty. On iOS the button
  sits in the sidebar's top bar beside **Edit**, as in Notes; on the Mac, at the sidebar's foot
  and as File ▸ New Collection, which sets a sheet flag on `NavigationModel` reached through
  `ActiveReaderWindow`, as Go to RFC is (`@FocusedValue` does not resolve from a hosted root).
- **Edit** (iOS) makes the Collections section reorderable and deletable; the fixed sections are
  unaffected. Entering and leaving Edit must neither push nor clear the sidebar's selection,
  which drives navigation in compact width — to verify on the device before step 2 closes.
- A collection row's context menu (long press on iOS, right click on the Mac): **Rename…**,
  **Colour** (a submenu of the palette), **Delete**. iOS also offers delete by trailing swipe.
- **Delete** asks first, saying how many documents the collection holds and that the documents
  themselves are not affected.

### A collection's list

- In the collection's own order by default, with every field in each row: a collection fixes
  no status or working group.
- **iOS:** **Edit** enables dragging to reorder and swiping to remove. The list's `…` menu
  offers Manual, Newest First and Oldest First, and Show Obsolete.
- **Mac:** in Manual order rows can always be dragged to reorder; Delete and a row's context
  menu item **Remove from Collection** remove. Sorting and Show Obsolete, which have no Mac
  control today, get View ▸ Sort By and View ▸ Show Obsolete menu items, for every list.
- Reordering is off while searching or outside Manual order (`canReorder`).
- VoiceOver: each row in a reorderable list has **Move Up** and **Move Down** actions.
- Empty, it says so and offers **Add**; searched without results, it says "No Results" as other
  lists do.
- **Add** opens a picker over the library: searchable, windowed like the list, each result
  marked when it is already in the collection. Choosing a result toggles it, and the picker
  stays open for more.

### Adding from elsewhere

One **Add to Collection** menu serves every entry point: each collection with a checkmark where
the document is already in it — choosing a checked one removes it, undoably — then **New
Collection…**, which creates the collection and adds the document to it.

- **Reader, iOS.** The bottom bar's Bookmark button becomes a `Menu` with a primary action: a
  tap bookmarks, a long press opens the menu. ⌘D must still reach the bookmark action — to
  verify.
- **Reader, Mac.** A submenu of the menu bar's document menu, and the toolbar's Bookmark item
  becomes an `NSMenuToolbarItem`: a click bookmarks, its indicator opens the menu. The glyph swap
  `validateToolbarItem` does for the bookmark state must survive the change — to verify.
- **List rows.** In the row's context menu on both platforms; on the Mac that context menu is
  new (today's `RowActions` is iOS only). On iOS also a second leading swipe beside Bookmark,
  opening the menu as a sheet.
- **Drag and drop** (last step). List rows dragged onto a collection in the sidebar, on iPad and
  the Mac.

### Scripting

The dictionary's description of a window's `collection` (`RFCReader.sdef`) mentions user
collections and the order names resolve in. Getting it returns the name through
`LibraryModel.title(for:)`; setting it resolves through the scripting names above.

## Out of scope

- Sharing, import and export (the model keeps it possible; see Why).
- Nesting.
- Icons other than the folder; custom colours outside the palette.
- Turning on iCloud sync, and with it any sweep of orphaned items. The schema is ready for it;
  enabling it is its own change.
- Smart collections defined by a query.

## Sequencing

Each step ends compiling, tested and working on both platforms.

1. **Model and store.** `SchemaV4` with its migration and test; the deduplication rule;
   `CollectionStore`, `CollectionOrder`, `CollectionColor`, `CollectionSnapshot`, `KeptFilter`,
   `ListOptions.collectionOrder` with `canReorder`, the scripting-name order; and
   `LibraryFilter.collection` together with the app's minimum for it — `LibraryModel`'s snapshot,
   `title(for:)` at every title site, and `computeList`'s case — since the new case does not
   compile without them. No interface yet.
2. **Sidebar and a read-only collection list.** The Collections section with create, rename,
   colour, delete and sidebar reorder; selecting a collection shows its documents in manual
   order.
3. **Editing a collection's list.** Reordering, removal with undo, the sort options on both
   platforms (including the Mac's View menu items), VoiceOver actions, the Add picker, the empty
   state.
4. **Adding from elsewhere.** The Add to Collection menu in the reader and on list rows, on both
   platforms.
5. **Drag and drop** onto sidebar collections, on iPad and the Mac.

## Testing

- **RFCReaderKit, Swift Testing, on a store on disk where a store is involved:**
  - the V3 → V4 migration, a V3 store with a bookmark and a reading position opened under the
    plan, in `UserDataTests`;
  - two new collections get different identifiers;
  - deduplication keeps the earliest item and leaves items of a missing collection alone;
  - `CollectionStore`: add is idempotent; toggle removes every duplicate; delete cascades; a
    move renumbers when the gap is too narrow or the neighbours equal; an undone removal returns
    to its old position; an empty or whitespace name is refused;
  - `CollectionOrder`: append, midpoint, both ends, the renumbering threshold, equal
    neighbours, and a move resolved from a visible list with hidden and unpaged rows;
  - `CollectionColor`: round trip, unknown name;
  - `CollectionSnapshot`: order with the tie-break, missing collections, duplicates;
  - `ListOptions.collectionOrder` and `canReorder`, and that the library's Oldest First leaves a
    collection alone;
  - `KeptFilter`: a deleted collection falls back to `.all`, anything else stays;
  - scripting names: the full precedence, same-named collections, and a round trip from setting
    a collection to reading its name back.
- **On the device:** each step on the iPhone and the Mac before it closes, including the three
  "to verify" points above (Edit and the sidebar selection, ⌘D, the Mac toolbar item).

## Documentation

`docs/ARCHITECTURE.md` gets a dated decision for collections — membership by identifier rather
than relationship, the `(position, addedAt, documentKey)` order and `Double` positions, no
orphan deletion until sync, the palette stored by name — beside the #152 entry, and its
data-flow diagram names the two new models beside `Bookmark` and `ReadingPosition`.
