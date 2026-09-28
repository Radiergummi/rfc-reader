# Custom collections — design

*28 September 2026. Approved in brainstorming (issue #349); implementation plan to follow.*

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

Settled in brainstorming, with the reason each was chosen.

| Question | Decision | Why |
|---|---|---|
| Membership | A document may be in any number of collections. | Topic groups overlap; one RFC serves several projects. |
| Order | Manual, new items at the end, reorderable. Newest/Oldest First are view options on top. | Reading paths need the reader's order; a large topic collection still wants to be seen by date. |
| Bookmarks | Stays separate and unchanged. | Bookmarking is one-tap "keep this"; a collection is a deliberate, named list. No migration of existing bookmarks. |
| Nesting | Flat. | Nesting brings reparenting, cycle checks and "what does a parent list" for little gain now. A parent can be added later as an optional attribute without a painful migration. |
| Colour | One of a fixed palette of system colours, stored by name. | Adapts to dark mode and increased contrast, and syncs as a word. |
| Platforms | iOS and macOS together. | The model and list logic are shared; once sync is on, lists made on one platform must be visible on the other. |
| Name | "Collections" in the interface. Scripting keeps "collection" for every sidebar entry, user-made ones included. | Matches the user's wording. Scripting's existing term already means "a thing the sidebar lists". |

## Model

### Schema

`SchemaV4` in `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift` is `SchemaV3` plus two
models. Both are in CloudKit's shape, as V3's are: no `@Attribute(.unique)`, every attribute
optional or defaulted.

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
"Collection". `Bookmark` and `ReadingPosition` keep their `SchemaV3` definitions and move to
`SchemaV4` unchanged, and the public typealiases point at V4.

**Membership is by identifier, not a SwiftData relationship.** Each item is an independent row
naming its collection. Two devices adding to the same collection each insert a row, and nothing
is lost when they meet. A relationship would make the collection's to-many side the thing two
devices both edit.

**Positions are `Double`s** so an item can move between two neighbours by taking their
midpoint, writing one row. When a gap becomes too narrow to split (see `CollectionOrder`), the
collection's items are renumbered in one pass.

### Migration

`UserDataMigrationPlan` gains V4 and a lightweight stage from V3: it adds two entities and
changes nothing else, which SwiftData infers. `UserDataMigrationTests` covers it the way #152's
stages are covered: a V3 store written to disk with a bookmark and a reading position, opened
under the plan, and both rows found intact beside empty collection tables.

### Integrity

`UserData.deduplicate`, which already runs when the container opens, also:

- removes items naming the same document twice in one collection, keeping the oldest, so the
  position the reader first gave it survives;
- removes items whose collection no longer exists. Deleting a collection deletes its items in
  the same save; this catches a deletion that arrived from another device before its items did.

Two collections with the same name are allowed: names are labels, identifiers are identity.

## Logic in RFCReaderKit

Everything here is a pure function of its inputs and tested without a store.

- **`CollectionOrder`** — where a new or moved item lands: after the last item, or at the
  midpoint of its new neighbours; and whether the positions need renumbering first (a gap below
  a threshold). The same arithmetic orders collections in the sidebar.
- **`CollectionColor`** — the palette: an enum of named system colours (blue, green, orange,
  red, purple, pink, teal, yellow, grey), `default` blue, and `init(name:)` falling back to the
  default for a name it does not know, which is what a newer device may sync to an older one.
- **The collection's list** — given the items and the index, the documents in the collection's
  order, dropping a key the index does not know. `ListOptions` gains a separate
  `collectionOrder` — Manual, Newest First or Oldest First, defaulting to Manual — which only a
  collection's list reads. It is separate from `order` so that a tab set to Oldest First for
  the library still opens every collection in its own order. Year sections are never applied to
  a collection (`YearSections.apply` returns false for it).
- **`LibraryFilter.collection(UUID)`** — a new case. It fixes no status or working group, is
  not in order of publication, and `includes` returns nil for it (the index cannot decide it).
  Its title is the collection's name, which the filter does not carry: the app resolves it
  through the store, and `LibraryFilter.title` is not used for this case.
- **Scripting names** — `LibraryFilter(scriptName:workingGroups:)` gains the collections' names.
  A built-in name wins a clash, then a working group, then a collection, so no existing script
  changes meaning.

## Interface

### Sidebar

- A **Collections** section below Library and above Browse, hidden while there are none. It
  collapses and remembers it, like the other sections.
- Each row: `folder` tinted with the collection's colour, the name, and the count of its
  items the index knows.
- **New Collection** (`folder.badge.plus`) opens a small sheet: a name field, focused, and a
  row of colour swatches. On iOS it sits in the sidebar's top bar beside **Edit**, as in
  Notes; on the Mac, at the sidebar's foot and as File ▸ New Collection.
- **Edit** (iOS) makes the Collections section reorderable and deletable; the fixed sections
  are unaffected.
- A collection row's context menu (long press on iOS, right click on the Mac): **Rename…**,
  **Colour** (a submenu of the palette), **Delete**. iOS also offers delete by trailing swipe.
- **Delete** asks first, saying how many documents the collection holds and that the documents
  themselves are not affected.

### Adding documents

One **Add to Collection** menu serves every entry point: each collection with a checkmark where
the document is already in it (choosing a checked one removes it), then **New Collection…**,
which creates the collection and adds the document to it.

- **Reader.** On iOS, a long press on the bottom bar's Bookmark button opens the menu; a tap
  still bookmarks. On the Mac, the menu is a submenu of the menu bar's document menu and the
  menu of the toolbar's bookmark button.
- **List rows.** In the row's context menu on both platforms, and on iOS as a second leading
  swipe beside Bookmark, opening the menu as a sheet.
- **Inside a collection.** An **Add** button opens a picker: the library, searchable, where
  choosing results adds them and the picker stays open for more.
- **Drag and drop** (second step). List rows dragged onto a collection in the sidebar, on iPad
  and the Mac.

### A collection's list

- In the collection's own order by default. **Edit** enables dragging to reorder and swiping to
  remove from the collection.
- The list's `…` menu offers **Manual**, **Newest First** and **Oldest First**. It is a view
  option, per tab like the others; reordering is available only in Manual.
- Rows show every field: a collection fixes no status or working group.
- Empty, it says so and offers the Add button; searched without results, it says "No Results"
  as other lists do.

## Out of scope

- Sharing, import and export (the model keeps it possible; see Why).
- Nesting.
- Icons other than the folder; custom colours outside the palette.
- Turning on iCloud sync. The schema is ready for it; enabling it is its own change.
- Smart collections defined by a query.

## Sequencing

Each step ends in a working, tested state and closes on its own.

1. **Model.** `SchemaV4`, the migration and its test, integrity in `deduplicate`,
   `CollectionOrder`, `CollectionColor`, `LibraryFilter.collection` with its scripting name,
   `ListOptions`' manual order, all tested.
2. **Sidebar.** The Collections section; create, rename, colour, delete, reorder.
3. **The collection's list.** Manual order and its reordering, removal, the Add picker, the
   empty state.
4. **Adding from elsewhere.** The Add to Collection menu in the reader and on list rows, on both
   platforms.
5. **Drag and drop** onto sidebar collections, on iPad and the Mac.

## Testing

- **RFCReaderKit, Swift Testing:** the migration against a V3 store on disk; `deduplicate`'s two
  new cases; `CollectionOrder` (append, move between neighbours, move to either end, the
  renumbering threshold); `CollectionColor` (round trip, unknown name); the collection's list
  (order, unknown keys dropped, Newest/Oldest views); `LibraryFilter.collection`'s properties
  and scripting-name precedence.
- **On the device:** each sequencing step on the iPhone and the Mac before it closes, as the
  navigation work was checked.

## Documentation

`docs/ARCHITECTURE.md` gets a dated decision for collections — membership by identifier rather
than relationship, positions as `Double`s, the palette stored by name — beside the #152 entry
on the user data store.
