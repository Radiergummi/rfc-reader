# Custom Collections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Named, user-made, hand-ordered lists of RFCs in the sidebar of the iOS and macOS app, with Notes-style folder controls (issue #349).

**Architecture:** Two new SwiftData models in a `SchemaV4` of the existing versioned, CloudKit-shaped user data store, linked by identifier rather than a relationship. Every decision — ordering arithmetic, mutations, the in-memory snapshot, filter fallbacks, sort options, scripting names — lives in `RFCReaderKit` and is tested there; the App target only wires views to it. `LibraryModel` publishes an observable `CollectionSnapshot`, keys its list cache on a collection's members, and answers every title through `title(for:)`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, AppKit (macOS window and toolbar), Swift Testing, XcodeGen, `make` targets.

**Spec:** `docs/superpowers/specs/2026-09-28-collections-design.md` — read it before starting; this plan argues from it.

## Global Constraints

- Work on branch `feat/349-collections` in the worktree `/Users/moritz/Projects/rfc-reader/.claude/worktrees/collections`. Never `git stash` bare; never touch other worktrees.
- `RFCReaderKit` holds everything testable; the App target has no test bundle (`CLAUDE.md`, "The App target has no test bundle").
- Every model attribute optional or defaulted; no `@Attribute(.unique)` (CloudKit's shape, `UserData.swift` header).
- Model names `DocumentCollection` and `DocumentCollectionItem` (never `Collection`, Swift's protocol). The interface says "Collection".
- Items are ordered by `(position, addedAt, documentKey)` ascending; collections by `(position, createdAt, identifier.uuidString)` ascending.
- Colour palette, in this order: blue, green, orange, red, purple, pink, teal, yellow, gray; default blue; stored by raw value.
- Items whose collection is missing are **never** deleted (spec, "Integrity").
- Scripting-name precedence: fixed collections and streams, series, working group, user collection (first in sidebar order).
- On macOS an `@Environment` lookup inside an `NSHostingController` root that was not handed the model is a runtime trap; `ReaderWindowController.host(_:)` hands `LibraryModel`, `NavigationModel`, `ReaderState` and the container. Menu commands reach the window through `ActiveReaderWindow`, never `@FocusedValue`.
- Tests use Swift Testing, named with raw identifiers: ``@Test func `a thing that is pinned`()``.
- `make lint` must be clean (`--strict`); run `make fmt` before committing. Long lines cap at 200.
- Commits are signed. If signing fails because Secretive is locked, commit with `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`. Messages are prose in the repo's style, end with `Refs #349` and the line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Commands: `swift test --package-path Packages/RFCReaderKit --filter <Suite>` for one suite; `make test-app` for the RFCReaderKit suite; `make build-app` (macOS) and `make ios-sim` (iOS) for the app; `make check` before every commit that touches `Packages/`.

## Review Focus

The inputs most likely to bite a person, each pinned by a test in the task named:

1. **A collection deleted while another tab shows it** (or on another device) — that tab falls back to All RFCs rather than an empty, untitled list. Pinned in Task 6 (`KeptFilter`) and Task 7 (wiring).
2. **Reordering with obsolete documents hidden or rows not yet paged in** — the moved row lands next to the visible neighbour it was dropped beside, not at an offset into hidden rows. Pinned in Task 1 (`CollectionOrder.neighbours`) and Task 5 (`move`).
3. **Many moves into the same gap, and two items at one position after an offline append** — order stays deterministic and a renumber happens instead of a collapse. Pinned in Task 1 and Task 5.
4. **A synced item naming something that is not an RFC, or a collection that has not arrived yet** — nothing crashes, the item is not listed or counted, and it is not deleted. Pinned in Task 3 and Task 4.
5. **A name of only spaces, on create and on rename** — refused, and the Create/Save button stays disabled. Pinned in Task 5; the button in Task 8.

---

## File Structure

**RFCReaderKit (`Packages/RFCReaderKit/Sources/RFCReaderKit/`)**
- `CollectionColor.swift` — create. The palette.
- `CollectionOrder.swift` — create. Position arithmetic and visible-to-full neighbour mapping.
- `UserData.swift` — modify. `SchemaV4`, typealiases, migration stage, container, item deduplication.
- `CollectionSnapshot.swift` — create. The value the app observes.
- `CollectionStore.swift` — create. Every mutation, on a `ModelContext`.
- `LibraryFilter.swift` — modify. `.collection(UUID)`, scripting names.
- `KeptFilter.swift` — create. Fallback for a deleted collection.
- `KeptSelection.swift` — modify. `replaceValue(_:)`.
- `ListOptions.swift` — modify. `CollectionSort`, `collectionSort`, `allowsMoving`.
- `YearSections.swift` — modify. `.collection` case.

**RFCReaderKit tests (`Packages/RFCReaderKit/Tests/RFCReaderKitTests/`)**
- create `CollectionOrderTests.swift`, `CollectionColorTests.swift`, `CollectionSnapshotTests.swift`, `CollectionStoreTests.swift`, `KeptFilterTests.swift`; modify `UserDataTests.swift`, `ListOptionsTests.swift`, `ScriptingTests.swift`, `LibraryFilterTests.swift`.

**App (`App/RFCReader/`)**
- `Model/LibraryModel.swift` — snapshot, `title(for:)`, `count(of:)`, list key, `editCollections`.
- `Model/NavigationModel.swift` — `keepFilter(in:)`, `collectionEditor`.
- `Model/AppData.swift` — warning copy.
- `Views/Components/CollectionColor+Color.swift` — create. Palette to SwiftUI `Color`.
- `Views/Collections/CollectionEditorSheet.swift` — create. Create/rename/colour sheet.
- `Views/Collections/AddToCollectionItems.swift` — create. The shared Add to Collection menu items and sheet.
- `Views/Collections/CollectionPickerSheet.swift` — create. The Add picker.
- `Views/SidebarView.swift`, `Views/RFCListView.swift`, `Views/ContentView.swift`, `Views/DocumentView.swift` — modify.
- `Window/ReaderWindowController.swift`, `Window/ReaderToolbar.swift`, `RFCReaderApp.swift` — modify.
- `Scripting/Scripting.swift`, `Scripting/RFCReader.sdef` — modify.

**Docs:** `docs/ARCHITECTURE.md` — modify.

---

## Step 1 of the spec: model and store

### Task 1: Palette and ordering arithmetic

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionColor.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionOrder.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionColorTests.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionOrderTests.swift`

**Interfaces:**
- Produces: `CollectionColor` (`CaseIterable`, `rawValue: String`, `static let default`, `init(name: String)`, `title: String`); `CollectionOrder.spacing`, `.minimumGap`, `.Placement { case at(Double), renumberFirst }`, `appending(after: Double?) -> Double`, `placement(between: Double?, and: Double?) -> Placement`, `renumbered(count: Int) -> [Double]`, `neighbours<Key: Equatable>(above: Key?, below: Key?, in: [Key]) -> (before: Key?, after: Key?)`.

- [ ] **Step 1: Write the failing tests**

`CollectionColorTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCReaderKit

/// A collection's colour, stored by name so it syncs as a word (#349).
@Suite("Collection colour")
struct CollectionColorTests {
  @Test func `every colour round-trips through its name`() {
    for color in CollectionColor.allCases {
      #expect(CollectionColor(name: color.rawValue) == color)
    }
  }

  /// What a newer device may sync to an older one.
  @Test func `an unknown name reads as the default`() {
    #expect(CollectionColor(name: "chartreuse") == .default)
    #expect(CollectionColor.default == .blue)
  }

  @Test func `the palette is in the order the swatches show it`() {
    #expect(
      CollectionColor.allCases.map(\.rawValue) == [
        "blue", "green", "orange", "red", "purple", "pink", "teal", "yellow", "gray",
      ])
  }
}
```

`CollectionOrderTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCReaderKit

/// Where rows sit in a collection and collections in the sidebar (#349).
@Suite("Collection order")
struct CollectionOrderTests {
  @Test func `the first row goes at one spacing`() {
    #expect(CollectionOrder.appending(after: nil) == CollectionOrder.spacing)
  }

  @Test func `a new row goes one spacing after the last`() {
    #expect(CollectionOrder.appending(after: 3) == 3 + CollectionOrder.spacing)
  }

  @Test func `a move between two neighbours takes their midpoint`() {
    #expect(CollectionOrder.placement(between: 1, and: 2) == .at(1.5))
  }

  @Test func `a move to either end steps one spacing past the end`() {
    #expect(CollectionOrder.placement(between: nil, and: 1) == .at(1 - CollectionOrder.spacing))
    #expect(CollectionOrder.placement(between: 4, and: nil) == .at(4 + CollectionOrder.spacing))
    #expect(CollectionOrder.placement(between: nil, and: nil) == .at(CollectionOrder.spacing))
  }

  /// Two devices appending offline both write "after the last".
  @Test func `equal neighbours call for a renumber`() {
    #expect(CollectionOrder.placement(between: 2, and: 2) == .renumberFirst)
  }

  @Test func `a gap too narrow to split calls for a renumber`() {
    let before = 1.0
    let after = before + CollectionOrder.minimumGap / 2
    #expect(CollectionOrder.placement(between: before, and: after) == .renumberFirst)
  }

  @Test func `renumbering spaces rows evenly in their order`() {
    #expect(CollectionOrder.renumbered(count: 3) == [1, 2, 3].map { $0 * CollectionOrder.spacing })
    #expect(CollectionOrder.renumbered(count: 0).isEmpty)
  }

  /// Obsolete documents hidden: the drop lands after the visible row above it,
  /// not somewhere among the hidden rows beyond it.
  @Test func `a drop below a visible row lands right after it`() {
    let full = ["a", "hidden", "b"]
    let neighbours = CollectionOrder.neighbours(above: "a", below: "b", in: full)
    #expect(neighbours.before == "a")
    #expect(neighbours.after == "hidden")
  }

  /// The list pages its rows in (`ListWindow`): a drop at the end of what is on
  /// screen lands after the last visible row, ahead of the rows not paged in yet.
  @Test func `a drop at the end of the window lands ahead of unpaged rows`() {
    let full = ["a", "b", "unpaged"]
    let neighbours = CollectionOrder.neighbours(above: "b", below: nil, in: full)
    #expect(neighbours.before == "b")
    #expect(neighbours.after == "unpaged")
  }

  @Test func `a drop at the top lands right before the visible row below it`() {
    let full = ["hidden", "a", "b"]
    let neighbours = CollectionOrder.neighbours(above: nil, below: "a", in: full)
    #expect(neighbours.before == "hidden")
    #expect(neighbours.after == "a")
  }

  @Test func `a drop into an empty list lands first`() {
    let neighbours = CollectionOrder.neighbours(above: nil, below: nil, in: ["a"])
    #expect(neighbours.before == nil)
    #expect(neighbours.after == "a")
  }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter "CollectionColorTests|CollectionOrderTests"`
Expected: build failure, `cannot find 'CollectionColor' in scope`.

- [ ] **Step 3: Implement**

`CollectionColor.swift`:

```swift
import Foundation

/// A collection's colour: one of a fixed palette of system colours, stored by name
/// (#349). A name rather than a colour value adapts to dark mode and increased
/// contrast, and syncs as a word.
public enum CollectionColor: String, CaseIterable, Sendable, Identifiable {
  case blue, green, orange, red, purple, pink, teal, yellow, gray

  public static let `default`: CollectionColor = .blue

  /// The colour a stored name names, or the default for one this version does not
  /// know, which is what a newer device may sync to an older one.
  public init(name: String) {
    self = CollectionColor(rawValue: name) ?? .default
  }

  public var id: Self { self }

  public var title: String {
    switch self {
    case .blue: "Blue"
    case .green: "Green"
    case .orange: "Orange"
    case .red: "Red"
    case .purple: "Purple"
    case .pink: "Pink"
    case .teal: "Teal"
    case .yellow: "Yellow"
    case .gray: "Grey"
    }
  }
}
```

`CollectionOrder.swift`:

```swift
import Foundation

/// Where rows sit in a collection, and collections in the sidebar (#349).
///
/// Positions are `Double`s so a move takes the midpoint of its new neighbours and
/// writes one row. Halving a gap runs out eventually, and two devices appending
/// offline can land on one position; both call for renumbering first.
public enum CollectionOrder {
  /// The gap between neighbours after appending or renumbering.
  public static let spacing: Double = 1

  /// Narrower than this, a gap is not split: the rows are renumbered first.
  public static let minimumGap: Double = 1e-9

  public enum Placement: Equatable, Sendable {
    case at(Double)
    case renumberFirst
  }

  /// One spacing after the last position, or the first position when there is none.
  public static func appending(after last: Double?) -> Double {
    (last ?? 0) + spacing
  }

  /// Between two neighbours, either of which may be missing at an end.
  public static func placement(between before: Double?, and after: Double?) -> Placement {
    switch (before, after) {
    case (nil, nil):
      .at(spacing)
    case (let before?, nil):
      .at(before + spacing)
    case (nil, let after?):
      .at(after - spacing)
    case (let before?, let after?):
      after - before > minimumGap ? .at((before + after) / 2) : .renumberFirst
    }
  }

  /// Evenly spaced positions for `count` rows, in the order they already have.
  public static func renumbered(count: Int) -> [Double] {
    (0..<count).map { Double($0 + 1) * spacing }
  }

  /// Where a row moved in a *visible* list goes in the full one.
  ///
  /// The visible list may hide obsolete documents, or hold only the rows paged in
  /// so far, so a move is never resolved by offset. `above` and `below` are the
  /// visible rows either side of the drop point; `full` is every row but the moved
  /// one, in order. The row goes right after `above` where there is one, otherwise
  /// right before `below`.
  public static func neighbours<Key: Equatable>(
    above: Key?, below: Key?, in full: [Key]
  ) -> (before: Key?, after: Key?) {
    if let above, let index = full.firstIndex(of: above) {
      let next = full.index(after: index)
      return (above, next < full.endIndex ? full[next] : nil)
    }
    if let below, let index = full.firstIndex(of: below) {
      return (index > full.startIndex ? full[full.index(before: index)] : nil, below)
    }
    return (nil, full.first)
  }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter "CollectionColorTests|CollectionOrderTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionColor.swift Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionOrder.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionColorTests.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionOrderTests.swift
git commit -m "Add the collection palette and ordering arithmetic" -m "Positions are Doubles so a move writes one row; a gap too narrow to split, or two equal neighbours, calls for a renumber. A move in a visible list resolves by the visible neighbours, never by offset.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 2: `SchemaV4` and its migration

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift` (typealiases at the top; new `SchemaV4` after `SchemaV3`; `UserDataMigrationPlan`; `UserData.container`)
- Modify: `App/RFCReader/Model/AppData.swift` (`storeWarning`)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/UserDataTests.swift`

**Interfaces:**
- Consumes: `CollectionColor` (Task 1).
- Produces: `DocumentCollection` (`identifier: UUID`, `name: String`, `colorName: String`, `position: Double`, `createdAt: Date`, `init(name:color:position:createdAt:)`, `color: CollectionColor { get set }`); `DocumentCollectionItem` (`collectionIdentifier: UUID?`, `documentKey: String`, `position: Double`, `addedAt: Date`, `init(collection:document:position:addedAt:)`, `document: DocumentID?`). Both are typealiases of `SchemaV4` classes, as `Bookmark` and `ReadingPosition` now are.

- [ ] **Step 1: Write the failing tests** (append inside `UserDataTests`, in the `// MARK: - Migration` part)

```swift
  /// V3 to V4 only adds the collections' tables: every existing row survives.
  @Test func `a version 3 store migrates to version 4 without losing a row`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let read = Date(timeIntervalSince1970: 1_750_000_000)

    do {
      let v3 = try ModelContainer(
        for: Schema(versionedSchema: SchemaV3.self), configurations: ModelConfiguration(url: url))
      let context = ModelContext(v3)
      context.insert(SchemaV3.Bookmark(document: .rfc(9110), title: "HTTP Semantics"))
      context.insert(
        SchemaV3.ReadingPosition(
          document: .rfc(9110), place: ReadingPlace(anchor: "section-8.3", offset: 4),
          updatedAt: read))
      try context.save()
    }

    let migrated = try UserData.container(configurations: ModelConfiguration(url: url))
    let context = ModelContext(migrated)
    #expect(try context.fetch(FetchDescriptor<Bookmark>()).map(\.document) == [.rfc(9110)])
    let positions = try context.fetch(FetchDescriptor<ReadingPosition>())
    #expect(positions.map(\.place) == [ReadingPlace(anchor: "section-8.3", offset: 4)])
    #expect(try context.fetch(FetchDescriptor<DocumentCollection>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
  }

  /// A constant default would give every row one identifier.
  @Test func `two new collections get different identifiers`() {
    let first = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let second = DocumentCollection(name: "DNS", color: .green, position: 2)
    #expect(first.identifier != second.identifier)
  }

  @Test func `a new store keeps a collection and its items`() throws {
    let url = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let identifier: UUID
    do {
      let container = try UserData.container(configurations: ModelConfiguration(url: url))
      let context = ModelContext(container)
      let collection = DocumentCollection(name: "HTTP/3", color: .teal, position: 1)
      identifier = collection.identifier
      context.insert(collection)
      context.insert(DocumentCollectionItem(collection: identifier, document: .rfc(9114), position: 1))
      try context.save()
    }
    let reopened = ModelContext(try UserData.container(configurations: ModelConfiguration(url: url)))
    let collections = try reopened.fetch(FetchDescriptor<DocumentCollection>())
    #expect(collections.map(\.name) == ["HTTP/3"])
    #expect(collections.map(\.color) == [.teal])
    let items = try reopened.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.collectionIdentifier) == [identifier])
    #expect(items.map(\.document) == [.rfc(9114)])
  }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter UserDataTests`
Expected: build failure, `cannot find 'DocumentCollection' in scope`.

- [ ] **Step 3: Implement**

In `UserData.swift`, replace the two typealiases at the top with:

```swift
public typealias Bookmark = SchemaV4.Bookmark
public typealias ReadingPosition = SchemaV4.ReadingPosition
public typealias DocumentCollection = SchemaV4.DocumentCollection
public typealias DocumentCollectionItem = SchemaV4.DocumentCollectionItem
```

and change the header comment's "`SchemaV3` is the one the app uses" to "`SchemaV4` is the one the app uses; V3's keys and shape carry over unchanged".

After the closing brace of `SchemaV3`, add:

```swift
/// V3 and the collections (#349). Its own copies of V3's two models, identical to
/// them: reusing one schema's classes in another is a known source of failed
/// staged migrations in SwiftData.
public enum SchemaV4: VersionedSchema {
  public static let versionIdentifier = Schema.Version(4, 0, 0)
  public static var models: [any PersistentModel.Type] {
    [Bookmark.self, ReadingPosition.self, DocumentCollection.self, DocumentCollectionItem.self]
  }

  @Model
  public final class Bookmark {
    /// The document's `fileStem`: `rfc9110`, `bcp14`.
    public var documentKey: String = ""
    public var title: String = ""
    public var createdAt: Date = Date.distantPast

    public init(document: DocumentID, title: String, createdAt: Date = .now) {
      self.documentKey = document.fileStem
      self.title = title
      self.createdAt = createdAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
  }

  /// V3's, without its `originalName: "sectionAnchor"`: that renamed V2's column on
  /// the way to V3, and here it would send V3 to V4 looking for a column a V3 store
  /// does not have.
  @Model
  public final class ReadingPosition {
    public var documentKey: String = ""
    /// The nearest anchor at or above the place the reader left, as a
    /// `ReadingPlace` has it.
    public var anchor: String?
    /// Characters past `anchor`, or nil when no place is recorded.
    public var offset: Int?
    public var updatedAt: Date = Date.distantPast

    public init(document: DocumentID, place: ReadingPlace?, updatedAt: Date = .now) {
      self.documentKey = document.fileStem
      self.anchor = place?.anchor
      self.offset = place?.offset
      self.updatedAt = updatedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }

    public var place: ReadingPlace? {
      get { offset.map { ReadingPlace(anchor: anchor, offset: $0) } }
      set {
        anchor = newValue?.anchor
        offset = newValue?.offset
      }
    }
  }

  /// A named, user-made list of documents. Its members are `DocumentCollectionItem`
  /// rows naming it by `identifier`, not a relationship: two devices adding to one
  /// collection then each insert a row, and nothing is lost when they meet.
  @Model
  public final class DocumentCollection {
    public var identifier: UUID = UUID()
    public var name: String = ""
    /// A `CollectionColor` raw value. An unknown name reads as the default.
    public var colorName: String = CollectionColor.default.rawValue
    /// Where the collection sits in the sidebar, ascending.
    public var position: Double = 0
    public var createdAt: Date = Date.distantPast

    public init(name: String, color: CollectionColor, position: Double, createdAt: Date = .now) {
      self.identifier = UUID()
      self.name = name
      self.colorName = color.rawValue
      self.position = position
      self.createdAt = createdAt
    }

    public var color: CollectionColor {
      get { CollectionColor(name: colorName) }
      set { colorName = newValue.rawValue }
    }
  }

  /// One document in one collection.
  @Model
  public final class DocumentCollectionItem {
    public var collectionIdentifier: UUID?
    /// The document's `fileStem`, as `Bookmark.documentKey` is: `rfc9110`.
    public var documentKey: String = ""
    /// Where the item sits in its collection, ascending.
    public var position: Double = 0
    public var addedAt: Date = Date.distantPast

    public init(collection: UUID, document: DocumentID, position: Double, addedAt: Date = .now) {
      self.collectionIdentifier = collection
      self.documentKey = document.fileStem
      self.position = position
      self.addedAt = addedAt
    }

    public var document: DocumentID? { DocumentID(fileStem: documentKey) }
  }
}
```

The existing migration tests (V1 and V2 stores opened under the plan) pin that `anchor` still reads correctly through V3 into V4; if the V3 → V4 test fails on `anchor`, that is the attribute to look at first.

In `UserDataMigrationPlan`:

```swift
  public static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
  }
  public static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4] }
```

and beside `v2ToV3` add:

```swift
  /// Adds the collections' two entities and changes nothing else (#349).
  static let v3ToV4 = MigrationStage.lightweight(
    fromVersion: SchemaV3.self, toVersion: SchemaV4.self)
```

In `UserData.container`, change `SchemaV3.self` to `SchemaV4.self` and the doc comment to "The app's container: V4, migrated from whatever version is on disk."

The `v2ToV3` stage refers to `SchemaV2` types explicitly and needs no change. Search for other explicit uses: `grep -rn "SchemaV3" App Packages` — only `UserData.swift` and the tests should name it.

In `AppData.swift`, change `storeWarning`'s message to:

```swift
    message:
      "Reading works as usual, but bookmarks, reading positions and collections changed in this session won't be saved. Nothing already saved has been touched."
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter UserDataTests`
Expected: all pass, including the existing V1 and V2 migration tests.

- [ ] **Step 5: Build the app and commit**

```bash
make fmt && make check && make build-app && make ios-sim
git add Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/UserDataTests.swift App/RFCReader/Model/AppData.swift
git commit -m "Add collections to the user data store as its fourth version" -m "SchemaV4 declares its own copies of V3's models and adds DocumentCollection and DocumentCollectionItem, in CloudKit's shape and linked by identifier. V3 to V4 is a lightweight stage that only adds the two entities.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 3: One item per document in a collection

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift` (`UserData.deduplicate`)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/UserDataTests.swift`

**Interfaces:**
- Consumes: `DocumentCollection`, `DocumentCollectionItem` (Task 2).
- Produces: `UserData.deduplicate(_:)` also merging items; nothing new to call.

- [ ] **Step 1: Write the failing tests** (in `// MARK: - Uniqueness`)

```swift
  /// The earliest item stays, so the place the reader first gave the document does.
  @Test func `duplicate items in one collection are merged, keeping the earliest`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    context.insert(collection)
    let id = collection.identifier
    context.insert(
      DocumentCollectionItem(
        collection: id, document: .rfc(9114), position: 5, addedAt: Date(timeIntervalSince1970: 2_000)))
    context.insert(
      DocumentCollectionItem(
        collection: id, document: .rfc(9114), position: 1, addedAt: Date(timeIntervalSince1970: 1_000)))
    try context.save()

    try UserData.deduplicate(context)

    let items = try context.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.position) == [1])
  }

  @Test func `one document in two collections is not a duplicate`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    try context.save()

    try UserData.deduplicate(context)

    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 2)
  }

  /// Under sync, items can arrive before their collection. Deleting them would
  /// sync the deletion back and empty the collection where it was made.
  @Test func `items of a collection not in the store are kept`() throws {
    let container = try UserData.container(
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1))
    try context.save()

    try UserData.deduplicate(context)

    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).count == 1)
  }
```

- [ ] **Step 2: Run to see the first one fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter UserDataTests`
Expected: `duplicate items in one collection are merged, keeping the earliest` fails (two items remain); the other two pass.

- [ ] **Step 3: Implement** — in `UserData.deduplicate`, before `if context.hasChanges`, add:

```swift
    // The earliest first, so the place the reader first gave a document survives.
    // Items whose collection is not in the store are left alone: under sync they
    // may have arrived before it.
    let items = try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(sortBy: [
        SortDescriptor(\.addedAt), SortDescriptor(\.position),
      ]))
    removeDuplicates(
      items, keyedBy: { "\($0.collectionIdentifier?.uuidString ?? "")/\($0.documentKey)" },
      in: context)
```

and update the doc comment of `deduplicate` to: "Merges rows that name the same document — keeping the newest bookmark and reading position, and the earliest item in a collection."

- [ ] **Step 4: Run to see all pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter UserDataTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/UserData.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/UserDataTests.swift
git commit -m "Keep one item per document in a collection" -m "The earliest stays. Items whose collection is missing are kept: under sync they may arrive before it, and deleting them would empty the collection where it was made.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 4: `CollectionSnapshot`

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionSnapshot.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionSnapshotTests.swift`

**Interfaces:**
- Consumes: `DocumentCollection`, `DocumentCollectionItem`, `CollectionColor`.
- Produces: `CollectionSnapshot` (`Equatable`, `Sendable`): `struct Entry: Equatable, Sendable, Identifiable { id: UUID; name: String; color: CollectionColor; members: [DocumentID]; var rfcNumbers: [Int] }`, `collections: [Entry]`, `static let empty`, `init(collections: [Entry])`, `init(collections: [DocumentCollection], items: [DocumentCollectionItem])`, `subscript(_ identifier: UUID) -> Entry?`, `func collections(containing: DocumentID) -> Set<UUID>`, `@MainActor static func fetch(in: ModelContext) -> CollectionSnapshot`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the app reads collections through (#349).
@Suite("Collection snapshot")
@MainActor
struct CollectionSnapshotTests {
  private let early = Date(timeIntervalSince1970: 1_000)
  private let late = Date(timeIntervalSince1970: 2_000)

  @Test func `collections are in sidebar order`() {
    let second = DocumentCollection(name: "DNS", color: .green, position: 2)
    let first = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)

    let snapshot = CollectionSnapshot(collections: [second, first], items: [])

    #expect(snapshot.collections.map(\.name) == ["HTTP/3", "DNS"])
    #expect(snapshot.collections.map(\.color) == [.blue, .green])
  }

  @Test func `members are in the collection's order`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 2),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9000), .rfc(9114)])
    #expect(snapshot[id]?.rfcNumbers == [9000, 9114])
  }

  /// Two devices appending offline both write "after the last".
  @Test func `equal positions fall back to when the item was added`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 1, addedAt: late),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1, addedAt: early),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9000), .rfc(9114)])
  }

  @Test func `items of a collection not in the snapshot are ignored`() {
    let items = [DocumentCollectionItem(collection: UUID(), document: .rfc(9114), position: 1)]
    #expect(CollectionSnapshot(collections: [], items: items).collections.isEmpty)
  }

  @Test func `a document listed twice appears once, where it first appears`() {
    let collection = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let id = collection.identifier
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 1),
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 2),
      DocumentCollectionItem(collection: id, document: .rfc(9114), position: 3),
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.members == [.rfc(9114), .rfc(9000)])
  }

  /// A key this version cannot read, or a series, is not an RFC the lists can show.
  @Test func `only RFCs are counted and listed`() {
    let collection = DocumentCollection(name: "Mixed", color: .blue, position: 1)
    let id = collection.identifier
    let unreadable = DocumentCollectionItem(collection: id, document: .rfc(1), position: 3)
    unreadable.documentKey = "draft-ietf-quic"
    let items = [
      DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1),
      DocumentCollectionItem(
        collection: id, document: DocumentID(series: .bcp, number: 14), position: 2),
      unreadable,
    ]

    let snapshot = CollectionSnapshot(collections: [collection], items: items)

    #expect(snapshot[id]?.rfcNumbers == [9000])
  }

  @Test func `which collections hold a document`() {
    let http = DocumentCollection(name: "HTTP/3", color: .blue, position: 1)
    let transport = DocumentCollection(name: "Transport", color: .green, position: 2)
    let items = [
      DocumentCollectionItem(collection: http.identifier, document: .rfc(9000), position: 1),
      DocumentCollectionItem(collection: transport.identifier, document: .rfc(9000), position: 1),
      DocumentCollectionItem(collection: http.identifier, document: .rfc(9114), position: 2),
    ]

    let snapshot = CollectionSnapshot(collections: [http, transport], items: items)

    #expect(snapshot.collections(containing: .rfc(9000)) == [http.identifier, transport.identifier])
    #expect(snapshot.collections(containing: .rfc(9114)) == [http.identifier])
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter CollectionSnapshotTests`
Expected: build failure, `cannot find 'CollectionSnapshot' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import RFCKit
import SwiftData

/// Every collection and its members, as values (#349).
///
/// What the app reads collections through: the sidebar and its counts, a
/// collection's list, the Add to Collection menus, the Mac's menu bar and scripts.
/// Built from one fetch, and `Equatable` so the app publishes a new one only when it
/// differs — most saves of the store record a reading position, not a collection.
public struct CollectionSnapshot: Equatable, Sendable {
  public struct Entry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let color: CollectionColor
    /// In the collection's order, each document once.
    public let members: [DocumentID]

    public init(id: UUID, name: String, color: CollectionColor, members: [DocumentID]) {
      self.id = id
      self.name = name
      self.color = color
      self.members = members
    }

    /// The members the lists can show: the lists list RFCs.
    public var rfcNumbers: [Int] {
      members.filter { $0.series == .rfc }.map(\.number)
    }
  }

  /// In sidebar order.
  public let collections: [Entry]

  public static let empty = CollectionSnapshot(collections: [])

  public init(collections: [Entry]) {
    self.collections = collections
  }

  /// From the store's rows: collections in `(position, createdAt, identifier)`
  /// order, members in `(position, addedAt, documentKey)` order. Items naming a
  /// collection that is not among `collections`, and keys that name no document,
  /// are left out.
  public init(collections: [DocumentCollection], items: [DocumentCollectionItem]) {
    let orderedItems = items.sorted {
      ($0.position, $0.addedAt, $0.documentKey) < ($1.position, $1.addedAt, $1.documentKey)
    }
    var membersByCollection: [UUID: [DocumentID]] = [:]
    for item in orderedItems {
      guard let collection = item.collectionIdentifier, let document = item.document else {
        continue
      }
      if membersByCollection[collection]?.contains(document) != true {
        membersByCollection[collection, default: []].append(document)
      }
    }
    let orderedCollections = collections.sorted {
      ($0.position, $0.createdAt, $0.identifier.uuidString)
        < ($1.position, $1.createdAt, $1.identifier.uuidString)
    }
    self.collections = orderedCollections.map {
      Entry(
        id: $0.identifier, name: $0.name, color: $0.color,
        members: membersByCollection[$0.identifier] ?? [])
    }
  }

  public subscript(_ identifier: UUID) -> Entry? {
    collections.first { $0.id == identifier }
  }

  /// The collections `document` is in, for the Add to Collection menus' checkmarks.
  public func collections(containing document: DocumentID) -> Set<UUID> {
    Set(collections.filter { $0.members.contains(document) }.map(\.id))
  }

  /// The store's collections, now.
  @MainActor
  public static func fetch(in context: ModelContext) -> CollectionSnapshot {
    let collections = (try? context.fetch(FetchDescriptor<DocumentCollection>())) ?? []
    let items = (try? context.fetch(FetchDescriptor<DocumentCollectionItem>())) ?? []
    return CollectionSnapshot(collections: collections, items: items)
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter CollectionSnapshotTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionSnapshot.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionSnapshotTests.swift
git commit -m "Add the collection snapshot the app reads collections through" -m "Collections in sidebar order, members in each collection's order with a tie-break on when they were added, each document once. Items of a missing collection and unreadable keys are left out.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 5: `CollectionStore`

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionStore.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionStoreTests.swift`

**Interfaces:**
- Consumes: `CollectionOrder`, `CollectionColor`, the two models.
- Produces (all `@MainActor`, all `throws`, all save before returning):
  - `CollectionStore.Failure { emptyName, noSuchCollection }`
  - `create(named: String, color: CollectionColor, in: ModelContext) -> DocumentCollection` (`@discardableResult`)
  - `rename(_ collection: UUID, to: String, in:)`, `setColor(_ collection: UUID, to: CollectionColor, in:)`, `delete(_ collection: UUID, in:)`
  - `add(_ document: DocumentID, to collection: UUID, in:)`
  - `remove(_ document: DocumentID, from collection: UUID, undoManager: UndoManager?, in:)`
  - `toggle(_ document: DocumentID, in collection: UUID, undoManager: UndoManager?, in:) -> Bool` (`@discardableResult`; true when it is now in the collection)
  - `move(_ document: DocumentID, in collection: UUID, afterVisible: DocumentID?, beforeVisible: DocumentID?, in:)`
  - `moveCollection(_ collection: UUID, afterVisible: UUID?, beforeVisible: UUID?, in:)`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Every change to collections (#349).
@Suite("Collection store")
@MainActor
struct CollectionStoreTests {
  private func context() throws -> ModelContext {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      .mainContext
  }

  private func members(of collection: UUID, in context: ModelContext) -> [DocumentID] {
    CollectionSnapshot.fetch(in: context)[collection]?.members ?? []
  }

  @Test func `a new collection is trimmed and goes after the others`() throws {
    let context = try context()
    try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    try CollectionStore.create(named: "  DNS \n", color: .green, in: context)

    let names = CollectionSnapshot.fetch(in: context).collections.map(\.name)
    #expect(names == ["HTTP/3", "DNS"])
  }

  @Test func `a name of only spaces is refused, on create and on rename`() throws {
    let context = try context()
    #expect(throws: CollectionStore.Failure.emptyName) {
      try CollectionStore.create(named: "   ", color: .blue, in: context)
    }
    let collection = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context)
    #expect(throws: CollectionStore.Failure.emptyName) {
      try CollectionStore.rename(collection.identifier, to: "\t", in: context)
    }
    #expect(CollectionSnapshot.fetch(in: context).collections.map(\.name) == ["HTTP/3"])
  }

  @Test func `rename and colour change what the snapshot says`() throws {
    let context = try context()
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.rename(id, to: "QUIC", in: context)
    try CollectionStore.setColor(id, to: .orange, in: context)

    let entry = CollectionSnapshot.fetch(in: context)[id]
    #expect(entry?.name == "QUIC")
    #expect(entry?.color == .orange)
  }

  @Test func `adding appends, and adding again changes nothing`() throws {
    let context = try context()
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: id, in: context)
    try CollectionStore.add(.rfc(9114), to: id, in: context)
    try CollectionStore.add(.rfc(9000), to: id, in: context)

    #expect(members(of: id, in: context) == [.rfc(9000), .rfc(9114)])
  }

  @Test func `adding to a collection that is gone is an error`() throws {
    let context = try context()
    #expect(throws: CollectionStore.Failure.noSuchCollection) {
      try CollectionStore.add(.rfc(9000), to: UUID(), in: context)
    }
  }

  @Test func `toggling removes every item naming the document`() throws {
    let context = try context()
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(9000), position: 1))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(9000), position: 2))
    try context.save()

    let isIn = try CollectionStore.toggle(.rfc(9000), in: id, undoManager: nil, in: context)

    #expect(!isIn)
    #expect(try context.fetch(FetchDescriptor<DocumentCollectionItem>()).isEmpty)
    #expect(try CollectionStore.toggle(.rfc(9000), in: id, undoManager: nil, in: context))
    #expect(members(of: id, in: context) == [.rfc(9000)])
  }

  @Test func `deleting a collection deletes its items and nothing else`() throws {
    let context = try context()
    let doomed = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let kept = try CollectionStore.create(named: "DNS", color: .green, in: context).identifier
    try CollectionStore.add(.rfc(9000), to: doomed, in: context)
    try CollectionStore.add(.rfc(1035), to: kept, in: context)

    try CollectionStore.delete(doomed, in: context)

    #expect(CollectionSnapshot.fetch(in: context).collections.map(\.id) == [kept])
    let items = try context.fetch(FetchDescriptor<DocumentCollectionItem>())
    #expect(items.map(\.collectionIdentifier) == [kept])
  }

  @Test func `a move places a document between its visible neighbours`() throws {
    let context = try context()
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2, 3] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    try CollectionStore.move(.rfc(3), in: id, afterVisible: .rfc(1), beforeVisible: .rfc(2), in: context)
    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])

    try CollectionStore.move(.rfc(2), in: id, afterVisible: nil, beforeVisible: .rfc(1), in: context)
    #expect(members(of: id, in: context) == [.rfc(2), .rfc(1), .rfc(3)])
  }

  /// A gap halved until it cannot be split again, and two items at one position:
  /// both renumber rather than collapse.
  @Test func `a move into a gap too narrow renumbers first`() throws {
    let context = try context()
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    let early = Date(timeIntervalSince1970: 1_000)
    let late = Date(timeIntervalSince1970: 2_000)
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(1), position: 1, addedAt: early))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(2), position: 1, addedAt: late))
    context.insert(DocumentCollectionItem(collection: id, document: .rfc(3), position: 5))
    try context.save()

    try CollectionStore.move(.rfc(3), in: id, afterVisible: .rfc(1), beforeVisible: .rfc(2), in: context)

    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3), .rfc(2)])
    let positions = try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(sortBy: [SortDescriptor(\.position)])
    ).map(\.position)
    #expect(Set(positions).count == 3)
  }

  @Test func `collections move in the sidebar`() throws {
    let context = try context()
    let a = try CollectionStore.create(named: "A", color: .blue, in: context).identifier
    let b = try CollectionStore.create(named: "B", color: .blue, in: context).identifier
    let c = try CollectionStore.create(named: "C", color: .blue, in: context).identifier

    try CollectionStore.moveCollection(c, afterVisible: nil, beforeVisible: a, in: context)

    #expect(CollectionSnapshot.fetch(in: context).collections.map(\.id) == [c, a, b])
  }

  /// A reading path must not lose its place to a mistaken tap.
  @Test func `an undone removal returns to its old place`() throws {
    let context = try context()
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let id = try CollectionStore.create(named: "HTTP/3", color: .blue, in: context).identifier
    for number in [1, 2, 3] { try CollectionStore.add(.rfc(number), to: id, in: context) }

    undoManager.beginUndoGrouping()
    try CollectionStore.remove(.rfc(2), from: id, undoManager: undoManager, in: context)
    undoManager.endUndoGrouping()
    #expect(members(of: id, in: context) == [.rfc(1), .rfc(3)])

    undoManager.undo()

    #expect(members(of: id, in: context) == [.rfc(1), .rfc(2), .rfc(3)])
  }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter CollectionStoreTests`
Expected: build failure, `cannot find 'CollectionStore' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import RFCKit
import SwiftData

/// Every change to collections, on a context (#349).
///
/// In the package rather than beside `BookmarkStore` in the App target, which has
/// no test bundle: what happens to a collection is decided here, and tested. Each
/// change saves before it returns, as `BookmarkStore.toggle` does, so the hosted
/// roots on a Mac — separate readers of one store — cannot disagree while a save is
/// pending.
@MainActor
public enum CollectionStore {
  public enum Failure: Error, Equatable {
    case emptyName
    case noSuchCollection
  }

  // MARK: - Collections

  /// A new collection, after the others in the sidebar.
  @discardableResult
  public static func create(
    named name: String, color: CollectionColor, in context: ModelContext
  ) throws -> DocumentCollection {
    let name = try validName(name)
    let last = try collections(in: context).last?.position
    let collection = DocumentCollection(
      name: name, color: color, position: CollectionOrder.appending(after: last))
    context.insert(collection)
    try context.save()
    return collection
  }

  public static func rename(_ identifier: UUID, to name: String, in context: ModelContext) throws {
    let name = try validName(name)
    try collection(identifier, in: context).name = name
    try context.save()
  }

  public static func setColor(
    _ identifier: UUID, to color: CollectionColor, in context: ModelContext
  ) throws {
    try collection(identifier, in: context).color = color
    try context.save()
  }

  /// The collection and its items, in one save. The documents are untouched.
  public static func delete(_ identifier: UUID, in context: ModelContext) throws {
    context.delete(try collection(identifier, in: context))
    for item in try items(in: identifier, context: context) {
      context.delete(item)
    }
    try context.save()
  }

  public static func moveCollection(
    _ identifier: UUID, afterVisible above: UUID?, beforeVisible below: UUID?,
    in context: ModelContext
  ) throws {
    var rows = try collections(in: context)
    guard let moving = rows.first(where: { $0.identifier == identifier }) else {
      throw Failure.noSuchCollection
    }
    rows.removeAll { $0.identifier == identifier }
    moving.position = place(
      between: CollectionOrder.neighbours(above: above, below: below, in: rows.map(\.identifier)),
      in: rows, key: \.identifier, position: \.position)
    try context.save()
  }

  // MARK: - Members

  /// At the end. A document already in the collection stays where it is.
  public static func add(
    _ document: DocumentID, to identifier: UUID, in context: ModelContext
  ) throws {
    _ = try collection(identifier, in: context)
    let items = try items(in: identifier, context: context)
    guard !items.contains(where: { $0.documentKey == document.fileStem }) else { return }
    context.insert(
      DocumentCollectionItem(
        collection: identifier, document: document,
        position: CollectionOrder.appending(after: items.last?.position)))
    try context.save()
  }

  /// Every item naming the document, since nothing stops there being two. Undoing
  /// puts it back where it was, not at the end.
  public static func remove(
    _ document: DocumentID, from identifier: UUID, undoManager: UndoManager?,
    in context: ModelContext
  ) throws {
    let removed = try items(in: identifier, context: context)
      .filter { $0.documentKey == document.fileStem }
    guard let first = removed.first else { return }
    let position = first.position
    let addedAt = first.addedAt
    removed.forEach(context.delete)
    try context.save()
    undoManager?.registerUndo(withTarget: context) { context in
      MainActor.assumeIsolated {
        context.insert(
          DocumentCollectionItem(
            collection: identifier, document: document, position: position, addedAt: addedAt))
        try? context.save()
      }
    }
    undoManager?.setActionName("Remove from Collection")
  }

  /// Removes the document if it is in the collection, adds it otherwise. Answers
  /// whether it is in the collection afterwards.
  @discardableResult
  public static func toggle(
    _ document: DocumentID, in identifier: UUID, undoManager: UndoManager?,
    in context: ModelContext
  ) throws -> Bool {
    let isIn = try items(in: identifier, context: context)
      .contains { $0.documentKey == document.fileStem }
    if isIn {
      try remove(document, from: identifier, undoManager: undoManager, in: context)
    } else {
      try add(document, to: identifier, in: context)
    }
    return !isIn
  }

  /// Between the rows either side of the drop point in the visible list, which may
  /// hide obsolete documents or hold only the rows paged in so far.
  public static func move(
    _ document: DocumentID, in identifier: UUID, afterVisible above: DocumentID?,
    beforeVisible below: DocumentID?, in context: ModelContext
  ) throws {
    var rows = try items(in: identifier, context: context)
    guard let moving = rows.first(where: { $0.documentKey == document.fileStem }) else { return }
    rows.removeAll { $0 === moving }
    let neighbours = CollectionOrder.neighbours(
      above: above?.fileStem, below: below?.fileStem, in: rows.map(\.documentKey))
    moving.position = place(
      between: neighbours, in: rows, key: \.documentKey, position: \.position)
    try context.save()
  }

  // MARK: - Helpers

  /// The position between two neighbours, renumbering `rows` first when the gap is
  /// too narrow or the neighbours are equal.
  private static func place<Row: AnyObject, Key: Equatable>(
    between neighbours: (before: Key?, after: Key?), in rows: [Row],
    key: KeyPath<Row, Key>, position: ReferenceWritableKeyPath<Row, Double>
  ) -> Double {
    func current(_ wanted: Key?) -> Double? {
      wanted.flatMap { wanted in rows.first { $0[keyPath: key] == wanted }?[keyPath: position] }
    }
    if case .at(let value) = CollectionOrder.placement(
      between: current(neighbours.before), and: current(neighbours.after))
    {
      return value
    }
    for (row, value) in zip(rows, CollectionOrder.renumbered(count: rows.count)) {
      row[keyPath: position] = value
    }
    guard
      case .at(let value) = CollectionOrder.placement(
        between: current(neighbours.before), and: current(neighbours.after))
    else {
      preconditionFailure("renumbered neighbours are a spacing apart")
    }
    return value
  }

  private static func validName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw Failure.emptyName }
    return trimmed
  }

  private static func collections(in context: ModelContext) throws -> [DocumentCollection] {
    try context.fetch(
      FetchDescriptor<DocumentCollection>(sortBy: [
        SortDescriptor(\.position), SortDescriptor(\.createdAt),
      ]))
  }

  private static func collection(
    _ identifier: UUID, in context: ModelContext
  ) throws -> DocumentCollection {
    let descriptor = FetchDescriptor<DocumentCollection>(
      predicate: #Predicate { $0.identifier == identifier })
    guard let collection = try context.fetch(descriptor).first else {
      throw Failure.noSuchCollection
    }
    return collection
  }

  /// In `(position, addedAt, documentKey)` order.
  private static func items(
    in identifier: UUID, context: ModelContext
  ) throws -> [DocumentCollectionItem] {
    let target: UUID? = identifier
    return try context.fetch(
      FetchDescriptor<DocumentCollectionItem>(
        predicate: #Predicate { $0.collectionIdentifier == target },
        sortBy: [
          SortDescriptor(\.position), SortDescriptor(\.addedAt), SortDescriptor(\.documentKey),
        ]))
  }
}
```

If `#Predicate` on the optional `UUID` does not compile, fetch all items and filter in memory with `.filter { $0.collectionIdentifier == identifier }` after sorting — the collection is small.

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter CollectionStoreTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/CollectionStore.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/CollectionStoreTests.swift
git commit -m "Add the collection store, where every change to collections is made" -m "Create, rename, colour, delete, add, remove, toggle and move, each saving before it returns. A removal can be undone to its old place; an empty name is refused.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 6: The collection filter, its fallback, options and script names

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/LibraryFilter.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/YearSections.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/ListOptions.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/KeptSelection.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/KeptFilter.swift`
- Test: `LibraryFilterTests.swift`, `ListOptionsTests.swift`, `ScriptingTests.swift`, create `KeptFilterTests.swift` (all in `Packages/RFCReaderKit/Tests/RFCReaderKitTests/`)

**Interfaces:**
- Consumes: `CollectionSnapshot` (Task 4).
- Produces: `LibraryFilter.collection(UUID)`; `LibraryFilter(scriptName:workingGroups:collections:)` with `collections: [CollectionSnapshot.Entry] = []`; `ListOptions.CollectionSort { manual, newestFirst, oldestFirst; title }`; `ListOptions.collectionSort`; `ListOptions.allowsMoving(in: LibraryFilter, query: String) -> Bool`; `KeptFilter.filter(_: LibraryFilter, keeping: CollectionSnapshot) -> LibraryFilter`; `KeptSelection.replaceValue(_:)`.

- [ ] **Step 1: Write the failing tests**

Append to `LibraryFilterTests`:

```swift
  /// Everything in a collection is there because the reader put it there: it fixes
  /// no field, and the index cannot decide it.
  @Test func `a collection fixes nothing and the index cannot decide it`() {
    let filter = LibraryFilter.collection(UUID())
    #expect(!filter.fixesStatus)
    #expect(!filter.fixesWorkingGroup)
    let rfc = RFCMetadata(id: .rfc(9000), title: "QUIC", date: PublicationDate(year: 2021))
    #expect(filter.includes(rfc) == nil)
    #expect(!YearSections.apply(to: filter, query: ""))
  }
```

Create `KeptFilterTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCReaderKit

/// A collection deleted in another tab or on another device (#349).
@Suite("Kept filter")
struct KeptFilterTests {
  private let entry = CollectionSnapshot.Entry(id: UUID(), name: "HTTP/3", color: .blue, members: [])

  @Test func `a deleted collection falls back to every RFC`() {
    #expect(KeptFilter.filter(.collection(UUID()), keeping: .empty) == .all)
  }

  @Test func `a collection still there stays`() {
    let snapshot = CollectionSnapshot(collections: [entry])
    #expect(KeptFilter.filter(.collection(entry.id), keeping: snapshot) == .collection(entry.id))
  }

  @Test func `other filters stay`() {
    #expect(KeptFilter.filter(.bookmarks, keeping: .empty) == .bookmarks)
    #expect(KeptFilter.filter(.workingGroup("quic"), keeping: .empty) == .workingGroup("quic"))
  }

  /// Replacing the value keeps a cleared selection cleared: a collapsed sidebar
  /// must not push a list because a collection went away.
  @Test func `replacing the kept value leaves a cleared selection cleared`() {
    var kept = KeptSelection(LibraryFilter.collection(entry.id))
    kept.selection = nil
    kept.replaceValue(.all)
    #expect(kept.value == .all)
    #expect(kept.selection == nil)
  }
}
```

Append to `ListOptionsTests` (read the file first; reuse its `rows` fixture, which holds RFC 9110 (2020, current), 7231 and 2616 (both obsoleted by 9110) — add dates where needed as below):

```swift
  private let dated = [
    RFCMetadata(id: .rfc(2616), title: "HTTP/1.1", date: PublicationDate(year: 1999)),
    RFCMetadata(id: .rfc(9110), title: "HTTP Semantics", date: PublicationDate(year: 2022)),
    RFCMetadata(id: .rfc(7231), title: "HTTP/1.1 Semantics", date: PublicationDate(year: 2014)),
  ]

  @Test func `a collection keeps its own order by default`() {
    let listed = ListOptions().apply(to: dated, filter: .collection(UUID()), query: "")
    #expect(listed.map(\.number) == [2616, 9110, 7231])
  }

  @Test func `a collection sorts by publication date, not by reversing`() {
    let collection = LibraryFilter.collection(UUID())
    let newest = ListOptions(collectionSort: .newestFirst).apply(to: dated, filter: collection, query: "")
    let oldest = ListOptions(collectionSort: .oldestFirst).apply(to: dated, filter: collection, query: "")
    #expect(newest.map(\.number) == [9110, 7231, 2616])
    #expect(oldest.map(\.number) == [2616, 7231, 9110])
  }

  /// A tab set to Oldest First for the library still opens a collection in its
  /// own order.
  @Test func `the library's order leaves a collection alone`() {
    let options = ListOptions(order: .oldestFirst)
    let listed = options.apply(to: dated, filter: .collection(UUID()), query: "")
    #expect(listed.map(\.number) == [2616, 9110, 7231])
  }

  @Test func `a searched collection stays in order of relevance`() {
    let options = ListOptions(collectionSort: .oldestFirst)
    let listed = options.apply(to: dated, filter: .collection(UUID()), query: "http")
    #expect(listed.map(\.number) == [2616, 9110, 7231])
  }

  @Test func `only an unsearched collection in its own order can be rearranged`() {
    let collection = LibraryFilter.collection(UUID())
    #expect(ListOptions().allowsMoving(in: collection, query: ""))
    #expect(!ListOptions().allowsMoving(in: collection, query: "quic"))
    #expect(!ListOptions(collectionSort: .newestFirst).allowsMoving(in: collection, query: ""))
    #expect(!ListOptions().allowsMoving(in: .all, query: ""))
  }
```

Append to `LibraryFilterScriptNameTests` in `ScriptingTests.swift` (read it first for its `groups` fixture and `filter(_:)` helper):

```swift
  private let http3 = CollectionSnapshot.Entry(id: UUID(), name: "HTTP/3", color: .blue, members: [])
  private let secondHTTP3 = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .green, members: [])
  private let shadowing = CollectionSnapshot.Entry(
    id: UUID(), name: "Bookmarks", color: .red, members: [])

  @Test func `a user collection is named as the sidebar names it`() {
    let filter = LibraryFilter(
      scriptName: "http/3", workingGroups: groups, collections: [http3, secondHTTP3])
    #expect(filter == .collection(http3.id))
  }

  /// No existing script changes meaning because a collection took a name.
  @Test func `built-in names win over a collection's`() {
    let filter = LibraryFilter(scriptName: "Bookmarks", workingGroups: groups, collections: [shadowing])
    #expect(filter == .bookmarks)
  }
```

(If `groups` in that suite contains a working group named like one of these, rename the collection in the test; the point is precedence.)

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter "LibraryFilterTests|KeptFilterTests|ListOptionsTests|LibraryFilterScriptNameTests"`
Expected: build failure on `.collection`, `KeptFilter`, `collectionSort`.

- [ ] **Step 3: Implement**

`LibraryFilter.swift` — add the case after `series`:

```swift
  /// A collection the reader made (#349). Its name is the collection's and not the
  /// filter's to carry: `LibraryModel.title(for:)` answers it.
  case collection(UUID)
```

In `title`: `case .collection: ""` with the comment `// Never shown: every title goes through LibraryModel.title(for:).`
In `systemImage`: `case .collection: "folder"`.
In `includes(_:)`: add `.collection` to the `nil` arm: `case .recent, .bookmarks, .downloaded, .series, .collection: nil`.
`fixesStatus`/`fixesWorkingGroup` already answer false by `default`/`if case`.

Change the scripting initialiser's signature and add the collection branch last:

```swift
  public init?(
    scriptName: String, workingGroups: Set<String>, collections: [CollectionSnapshot.Entry] = []
  ) {
    // … existing body up to and including the working-group branch …
    } else if let collection = collections.first(where: {
      $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = .collection(collection.id)
    } else {
      return nil
    }
  }
```

and extend its doc comment: "…then a collection the reader made, the first in sidebar order among any of one name. A built-in name, a series or a working group wins a clash, so no script changes meaning because a collection took its name."

`YearSections.swift` — in `apply(to:query:)`'s switch: `case .recent, .bookmarks, .downloaded, .series, .collection: return false`.

`ListOptions.swift` — add after `Order`:

```swift
  /// How a collection's list is ordered (#349): the reader's own order, or by
  /// publication date. Separate from `order`, so a tab set to Oldest First for the
  /// library still opens a collection in its own order.
  public enum CollectionSort: Hashable, Sendable, CaseIterable {
    case manual
    case newestFirst
    case oldestFirst

    public var title: String {
      switch self {
      case .manual: "Manual"
      case .newestFirst: "Newest First"
      case .oldestFirst: "Oldest First"
      }
    }
  }
```

add `public var collectionSort: CollectionSort`, extend `init` with `collectionSort: CollectionSort = .manual`, and change `apply`:

```swift
  public func apply(
    to rows: [RFCMetadata], filter: LibraryFilter, query: String
  ) -> [RFCMetadata] {
    let shown = showsObsolete ? rows : rows.filter { !$0.isObsolete }
    if case .collection = filter { return sortedCollection(shown, query: query) }
    guard order == .oldestFirst, Self.canReorder(filter, query: query) else { return shown }
    return shown.reversed()
  }

  /// By publication date, then number: a collection is in the reader's order, so
  /// reversing it would not put the oldest first. A search stays in order of
  /// relevance.
  private func sortedCollection(_ rows: [RFCMetadata], query: String) -> [RFCMetadata] {
    guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return rows }
    switch collectionSort {
    case .manual: return rows
    case .newestFirst: return rows.sorted { ($0.date, $0.number) > ($1.date, $1.number) }
    case .oldestFirst: return rows.sorted { ($0.date, $0.number) < ($1.date, $1.number) }
    }
  }

  /// Whether rows can be dragged into a new order: only in a collection, in its own
  /// order, unsearched — a search's rows are in order of relevance, and their
  /// neighbours are not the collection's.
  public func allowsMoving(in filter: LibraryFilter, query: String) -> Bool {
    guard case .collection = filter else { return false }
    return collectionSort == .manual && query.trimmingCharacters(in: .whitespaces).isEmpty
  }
```

`KeptSelection.swift` — add:

```swift
  /// Replaces the kept value without selecting it, so a cleared selection stays
  /// cleared: a collapsed split view must not push a list because the value it
  /// kept went away.
  public mutating func replaceValue(_ newValue: Value) {
    value = newValue
  }
```

`KeptFilter.swift`:

```swift
import Foundation

/// The filter a tab goes on showing when collections change (#349): its own, unless
/// it is a collection that no longer exists — deleted in another tab or on another
/// device — which falls back to every RFC.
public enum KeptFilter {
  public static func filter(
    _ filter: LibraryFilter, keeping snapshot: CollectionSnapshot
  ) -> LibraryFilter {
    if case .collection(let identifier) = filter, snapshot[identifier] == nil { return .all }
    return filter
  }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit` — the whole suite, since `LibraryFilter`'s switches changed.
Expected: all pass. The App target will not compile until Task 7 (its `computeList` switch is exhaustive); do not build the app yet.

- [ ] **Step 5: Commit**

```bash
make fmt && make lint && make test
git add Packages/RFCReaderKit
git commit -m "Add the collection filter, its fallback, sort options and script names" -m "LibraryFilter.collection fixes no field and is never sectioned by year. KeptFilter falls back to every RFC when a collection is deleted elsewhere. A collection's list sorts by date rather than by reversing, and can be rearranged only in its own order, unsearched. Scripts reach a collection by name after every built-in name.

The App target builds again with the next commit.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 7: The app's minimum for collections

**Files:**
- Modify: `App/RFCReader/Model/LibraryModel.swift` (properties near `bookmarkedDocuments`; `init`; `ListKey`; `list(for:)`; `librarySearch`; `computeList`; new functions)
- Modify: `App/RFCReader/Model/NavigationModel.swift` (`keepFilter(in:)`, `collectionEditor`)
- Create: `App/RFCReader/Views/Components/CollectionColor+Color.swift`
- Create: `App/RFCReader/Views/Collections/CollectionEditorMode.swift`
- Modify title sites: `App/RFCReader/Window/ReaderWindowController.swift:235,272`, `App/RFCReader/Views/ContentView.swift:28`, `App/RFCReader/Views/RFCListView.swift:96,120,126`, `App/RFCReader/Views/SidebarView.swift:182`
- Modify: `App/RFCReader/Scripting/Scripting.swift:102-112`, `App/RFCReader/Scripting/RFCReader.sdef:53`

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: `LibraryModel.collections: CollectionSnapshot`; `LibraryModel.title(for: LibraryFilter) -> String`; `LibraryModel.count(of: CollectionSnapshot.Entry) -> Int?`; `LibraryModel.editCollections(_ change: (ModelContext) throws -> Void)`; `NavigationModel.keepFilter(in: CollectionSnapshot)`; `NavigationModel.collectionEditor: CollectionEditorMode?`; `enum CollectionEditorMode: Identifiable, Hashable { case create(adding: DocumentID?); case edit(UUID) }`; `extension CollectionColor { var color: Color }`.

No test bundle for the App target: everything decided here was tested in Tasks 1–6. This task is wiring; its check is that both apps build and behave exactly as before with no collections.

- [ ] **Step 1: `LibraryModel`**

Beside `bookmarkedNumbers`, add:

```swift
  /// Every collection and its members, fetched again on every save of the store and
  /// published only when it changed (#349). The sidebar, a collection's list, the
  /// Add to Collection menus, the Mac's menu bar and scripts all read it.
  private(set) var collections = CollectionSnapshot.empty
```

In `init`, call `refreshCollections()` after `refreshBookmarks()`, and inside the `didSave` observer call both:

```swift
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshBookmarks()
        self?.refreshCollections()
      }
    }
```

Add beside `refreshBookmarks()`:

```swift
  private func refreshCollections() {
    let snapshot = CollectionSnapshot.fetch(in: AppData.container.mainContext)
    // Only a change is news: most saves record a reading position.
    guard snapshot != collections else { return }
    collections = snapshot
    // A collection deleted in another tab, or on another device, is not left on
    // screen with no name and nothing in it.
    for scene in scenes.compactMap(\.model) {
      scene.keepFilter(in: snapshot)
    }
  }

  /// What a filter is called, wherever it is shown: a collection's name, or the
  /// filter's own title. Every title goes through here, so a collection is never
  /// shown by the empty title its filter carries.
  func title(for filter: LibraryFilter) -> String {
    if case .collection(let identifier) = filter {
      return collections[identifier]?.name ?? ""
    }
    return filter.title
  }

  /// How many of a collection's documents the index knows, for the sidebar. Nil
  /// until the index has loaded.
  func count(of entry: CollectionSnapshot.Entry) -> Int? {
    guard let index else { return nil }
    return entry.rfcNumbers.count(where: { index[$0] != nil })
  }

  /// Runs a change to collections on the app's context. A failure is logged rather
  /// than shown (#125): every change the interface offers is one the store accepts,
  /// and an empty name is refused before it gets here.
  func editCollections(_ change: (ModelContext) throws -> Void) {
    do {
      try change(AppData.container.mainContext)
    } catch {
      libraryLog.error(
        "changing a collection failed: \(String(describing: error), privacy: .public)")
    }
  }
```

In `ListKey` add `let members: [Int]` with the comment `/// A collection's members in order, so adding, removing or reordering changes the key.`

In `list(for:)`, add to the key:

```swift
      options: scene.listOptions,
      members: {
        if case .collection(let identifier) = filter {
          return collections[identifier]?.rfcNumbers ?? []
        }
        return []
      }()
```

(order the arguments to match the struct's member order; put `members` last in both). In `librarySearch`, pass `members: []`.

In `computeList`'s switch, add:

```swift
    case .collection: base = key.members.compactMap { index[$0] }
```

- [ ] **Step 2: `NavigationModel`**

After `var isShowingGoToSheet = false` add:

```swift
  /// The collection sheet on show, if any: creating one — perhaps to add a document
  /// to — or editing one (#349). On the model rather than a view's state so the
  /// sidebar, the Add to Collection menus and the Mac's File menu can all ask for
  /// it, and the one view that presents it is in the window.
  var collectionEditor: CollectionEditorMode?
```

and after `sidebarSelection`:

```swift
  /// Leaves a collection that no longer exists (#349). A cleared selection stays
  /// cleared, so a collapsed sidebar does not push a list; a shown one moves to the
  /// fallback.
  func keepFilter(in snapshot: CollectionSnapshot) {
    let kept = KeptFilter.filter(filter, keeping: snapshot)
    guard kept != filter else { return }
    if filterChoice.selection == nil {
      filterChoice.replaceValue(kept)
    } else {
      sidebarSelection = kept
    }
  }
```

- [ ] **Step 3: Colour and the editor mode**

`App/RFCReader/Views/Components/CollectionColor+Color.swift`:

```swift
import RFCReaderKit
import SwiftUI

extension CollectionColor {
  /// The system colour a collection's name stands for, adapting to dark mode and
  /// increased contrast.
  var color: Color {
    switch self {
    case .blue: .blue
    case .green: .green
    case .orange: .orange
    case .red: .red
    case .purple: .purple
    case .pink: .pink
    case .teal: .teal
    case .yellow: .yellow
    case .gray: .gray
    }
  }
}
```

`App/RFCReader/Views/Collections/CollectionEditorMode.swift`:

```swift
import Foundation
import RFCKit

/// What the collection sheet is for (#349).
enum CollectionEditorMode: Identifiable, Hashable {
  /// A new collection, and the document to add to it once made, when it was asked
  /// for from an Add to Collection menu.
  case create(adding: DocumentID?)
  /// Renaming and recolouring the collection with this identifier.
  case edit(UUID)

  var id: Self { self }
}
```

- [ ] **Step 4: Every title site**

Replace `navigation.filter.title` with `library.title(for: navigation.filter)` at:
- `ReaderWindowController.swift` in `observeTitle()` and `observeListTitle()` (both inside `withObservationTracking`, which now also tracks `collections`, so a rename shows at once);
- `ContentView.swift` in `windowTitle`;
- `RFCListView.swift` in the empty state, `.navigationTitle` and the `.searchable` prompt;
- `SidebarView.swift` in `row(_:)`: `Label(library.title(for: filter), systemImage: filter.systemImage)`.

Confirm none remain: `grep -rn "filter.title" App` must show only the Scripting getter (next step).

- [ ] **Step 5: Scripting**

In `Scripting.swift`:

```swift
    @objc var scriptCollection: String {
      get { controller.map { LibraryModel.shared.title(for: $0.navigation.filter) } ?? "" }
      set {
        let library = LibraryModel.shared
        let groups = Set(library.index?.rfcs.compactMap(\.workingGroup) ?? [])
        guard
          let filter = LibraryFilter(
            scriptName: newValue, workingGroups: groups,
            collections: library.collections.collections)
        else {
          ScriptError.report("There is no collection named “\(newValue)”.")
          return
        }
        controller?.navigation.sidebarSelection = filter
      }
    }
```

In `RFCReader.sdef`, extend the `collection` property's `description` with: ` A collection you made is named as the sidebar shows it; built-in names, series and working groups are matched first, and among collections of one name the first in the sidebar.`

- [ ] **Step 6: Build both apps and run everything**

```bash
make fmt && make check && make build-app && make ios-sim
```
Expected: all green. `make run` on the Mac: the sidebar, lists and titles look exactly as before.

- [ ] **Step 7: Commit**

```bash
git add App Packages
git commit -m "Wire collections into the library model, titles and scripts" -m "LibraryModel publishes the collection snapshot and keys a collection's list on its members, so a change to them is never served from the cache. Every title goes through title(for:), the scripting getter included. A tab whose collection is deleted elsewhere falls back to every RFC.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Step 2 of the spec: sidebar and a read-only collection list

### Task 8: The Collections section

**Files:**
- Create: `App/RFCReader/Views/Collections/CollectionEditorSheet.swift`
- Modify: `App/RFCReader/Views/SidebarView.swift`
- Modify: `App/RFCReader/Views/ContentView.swift` (iOS sheet)
- Modify: `App/RFCReader/Window/ReaderWindowController.swift` (`ReaderHost` sheet, macOS)
- Modify: `App/RFCReader/RFCReaderApp.swift` (File ▸ New Collection)

**Interfaces:**
- Consumes: `LibraryModel.collections`, `count(of:)`, `editCollections`, `title(for:)`; `NavigationModel.collectionEditor`; `CollectionEditorMode`; `CollectionStore`; `CollectionColor.color`.
- Produces: `CollectionEditorSheet(mode: CollectionEditorMode)`.

- [ ] **Step 1: The editor sheet**

```swift
import RFCKit
import RFCReaderKit
import SwiftUI

/// Creating a collection, or renaming and recolouring one (#349).
struct CollectionEditorSheet: View {
  let mode: CollectionEditorMode

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var color = CollectionColor.default
  @FocusState private var isNameFocused: Bool

  private var title: String {
    if case .edit = mode { "Edit Collection" } else { "New Collection" }
  }

  private var confirmation: String {
    if case .edit = mode { "Save" } else { "Create" }
  }

  /// The store refuses a name of only spaces; the button says so first.
  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        fields
        HStack {
          Spacer()
          Button("Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
          Button(confirmation, action: save)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
      }
      .padding(20)
      .frame(width: 360)
      .onAppear(perform: load)
    #else
      NavigationStack {
        Form { fields }
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
              Button(confirmation, action: save).disabled(!canSave)
            }
          }
      }
      .presentationDetents([.medium])
      .onAppear(perform: load)
    #endif
  }

  @ViewBuilder
  private var fields: some View {
    TextField("Name", text: $name)
      .focused($isNameFocused)
      .onSubmit { if canSave { save() } }
    HStack(spacing: 10) {
      ForEach(CollectionColor.allCases) { swatch in
        Button {
          color = swatch
        } label: {
          Circle()
            .fill(swatch.color)
            .frame(width: 24, height: 24)
            .overlay {
              if swatch == color {
                Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(swatch == color ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }

  private func load() {
    if case .edit(let identifier) = mode, let entry = library.collections[identifier] {
      name = entry.name
      color = entry.color
    }
    isNameFocused = true
  }

  private func save() {
    library.editCollections { context in
      switch mode {
      case .create(let document):
        let collection = try CollectionStore.create(named: name, color: color, in: context)
        if let document {
          try CollectionStore.add(document, to: collection.identifier, in: context)
        }
      case .edit(let identifier):
        try CollectionStore.rename(identifier, to: name, in: context)
        try CollectionStore.setColor(identifier, to: color, in: context)
      }
    }
    dismiss()
  }
}
```

- [ ] **Step 2: Present it where a sheet can be presented**

iOS, `ContentView.swift`, beside `.sheet(isPresented: $navigation.isShowingGoToSheet)`:

```swift
      .sheet(item: $navigation.collectionEditor) { mode in
        CollectionEditorSheet(mode: mode)
      }
```

macOS, `ReaderWindowController.swift` in `ReaderHost.body`, beside the Go to RFC sheet:

```swift
      .sheet(item: $navigation.collectionEditor) { mode in
        CollectionEditorSheet(mode: mode)
      }
```

Both are inside the `.environment(...)`/`host(_:)` injection, so the sheet's `@Environment(LibraryModel.self)` resolves.

- [ ] **Step 3: The sidebar section**

In `SidebarView`, add state:

```swift
  @AppStorage("sidebar.collectionsExpanded") private var collectionsExpanded = true
  /// The collection whose deletion is being confirmed.
  @State private var deleting: CollectionSnapshot.Entry?
```

In `places`, between the Library and Browse groups:

```swift
    if !library.collections.collections.isEmpty {
      group("Collections", isExpanded: $collectionsExpanded) {
        ForEach(library.collections.collections) { entry in
          collectionRow(entry)
        }
        .onMove(perform: moveCollections)
        #if !os(macOS)
          .onDelete { offsets in
            deleting = offsets.first.map { library.collections.collections[$0] }
          }
        #endif
      }
    }
```

Add the row, sharing the count and chevron with `row(_:)` — first factor the trailing part of `row(_:)` (everything after the `Label` inside its `HStack`, under `#if !os(macOS)`) into:

```swift
  /// The count and, collapsed, the chevron, after a row's label.
  @ViewBuilder
  private func accessories(count: Int?) -> some View {
    #if !os(macOS)
      Spacer()
      if let count {
        Text(count, format: .number)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      if horizontalSizeClass == .compact {
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    #endif
  }
```

so `row(_:)` becomes `HStack { Label(library.title(for: filter), systemImage: filter.systemImage); accessories(count: count(filter)) }.tag(filter)` (keeping its comments; on macOS `count(filter)` does not exist, so call `accessories(count: nil)` there — wrap as `#if os(macOS) accessories(count: nil) #else accessories(count: count(filter)) #endif`).

Then:

```swift
  private func collectionRow(_ entry: CollectionSnapshot.Entry) -> some View {
    let filter = LibraryFilter.collection(entry.id)
    return HStack {
      Label {
        Text(entry.name)
      } icon: {
        Image(systemName: "folder")
          // On a Mac a selected sidebar row turns its icons white, and an explicit
          // colour would override that: `.primary` there follows the row's
          // prominence.
          .foregroundStyle(
            isSelected(filter) ? AnyShapeStyle(.primary) : AnyShapeStyle(entry.color.color))
      }
      #if os(macOS)
        accessories(count: nil)
      #else
        accessories(count: library.count(of: entry))
      #endif
    }
    .tag(filter)
    .contextMenu {
      Button("Rename…") { navigation.collectionEditor = .edit(entry.id) }
      Menu("Colour") {
        ForEach(CollectionColor.allCases) { color in
          Button {
            library.editCollections { try CollectionStore.setColor(entry.id, to: color, in: $0) }
          } label: {
            if color == entry.color {
              Label(color.title, systemImage: "checkmark")
            } else {
              Text(color.title)
            }
          }
        }
      }
      Divider()
      Button("Delete…", role: .destructive) { deleting = entry }
    }
  }

  private func isSelected(_ filter: LibraryFilter) -> Bool {
    #if os(macOS)
      navigation.sidebarSelection == filter
    #else
      false
    #endif
  }

  private func moveCollections(from source: IndexSet, to destination: Int) {
    var entries = library.collections.collections
    guard let moved = source.first.map({ entries[$0] }) else { return }
    entries.move(fromOffsets: source, toOffset: destination)
    guard let index = entries.firstIndex(of: moved) else { return }
    let above = index > 0 ? entries[index - 1].id : nil
    let below = index + 1 < entries.count ? entries[index + 1].id : nil
    library.editCollections {
      try CollectionStore.moveCollection(moved.id, afterVisible: above, beforeVisible: below, in: $0)
    }
  }
```

On the `List`, after the existing modifiers, the deletion confirmation:

```swift
    .confirmationDialog(
      "Delete “\(deleting?.name ?? "")”?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible,
      presenting: deleting
    ) { entry in
      Button("Delete Collection", role: .destructive) {
        library.editCollections { try CollectionStore.delete(entry.id, in: $0) }
      }
    } message: { entry in
      Text(
        "The \(entry.members.count) documents in it stay in the library. Only the collection is removed."
      )
    }
```

- [ ] **Step 4: New Collection and Edit**

iOS, in the `#else` branch of `SidebarView.body`'s modifiers:

```swift
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            navigation.collectionEditor = .create(adding: nil)
          } label: {
            Label("New Collection", systemImage: "folder.badge.plus")
          }
        }
        if !library.collections.collections.isEmpty {
          ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
      }
```

macOS, in the `#if os(macOS)` branch, beside the search field inset:

```swift
      .safeAreaInset(edge: .bottom) {
        HStack {
          Button {
            navigation.collectionEditor = .create(adding: nil)
          } label: {
            Label("New Collection", systemImage: "folder.badge.plus")
          }
          .buttonStyle(.borderless)
          .labelStyle(.titleAndIcon)
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
```

`RFCReaderApp.swift`, in the macOS `CommandGroup(after: .newItem)` beside Go to RFC:

```swift
      #if os(macOS)
        Button("New Collection…") { navigation?.collectionEditor = .create(adding: nil) }
          .keyboardShortcut("n", modifiers: [.command, .shift])
          .disabled(navigation == nil)
      #endif
```

(⇧⌘N is free: `grep -n keyboardShortcut App/RFCReader/RFCReaderApp.swift` shows ⌘N, ⌘T, ⌘L, ⌘D, ⌃⌘S, ⌥⌘I, ⌘←, ⌘→, ⌘F, ⌘G.)

- [ ] **Step 5: Build and check on the devices**

```bash
make fmt && make lint && make build-app && make ios-sim
make run
make run-device IOS_DEVICE=Charon
```

Check, on both:
- New Collection creates a collection, Create is disabled for a blank name, and it appears under Library with its colour.
- Selecting it shows an empty list titled with its name (the window and tab title on the Mac too); Rename changes every title at once.
- Delete asks first; deleting the collection a second Mac tab shows moves that tab to All RFCs.
- Reordering collections by drag works; on iOS, Edit shows reorder and delete handles for collections only.
- **To verify (spec):** entering and leaving Edit on the iPhone neither pushes nor clears the sidebar selection. If it does, give the `List` a selection binding that ignores writes while editing:

```swift
  @Environment(\.editMode) private var editMode
  private var selection: Binding<LibraryFilter?> {
    let binding = Bindable(navigation).sidebarSelection
    return Binding(
      get: { binding.wrappedValue },
      set: { if editMode?.wrappedValue.isEditing != true { binding.wrappedValue = $0 } })
  }
```

and use `List(selection: selection)`.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "Add a Collections section to the sidebar" -m "Create, rename, recolour, delete after asking, and reorder, on both platforms: New Collection beside Edit on iOS, at the sidebar's foot and as File > New Collection on the Mac. Selecting a collection lists its documents in their order.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Step 3 of the spec: editing a collection's list

### Task 9: The Add picker and the empty state

**Files:**
- Create: `App/RFCReader/Views/Collections/CollectionPickerSheet.swift`
- Modify: `App/RFCReader/Views/RFCListView.swift`

**Interfaces:**
- Consumes: `LibraryModel.librarySearch`, `list(for:)`-style windowing via `ListWindow`, `collections`, `CollectionStore.toggle`, `RFCRow`.
- Produces: `CollectionPickerSheet(collection: UUID)`.

- [ ] **Step 1: The picker**

```swift
import RFCKit
import RFCReaderKit
import SwiftUI

/// The library, searchable, for adding documents to a collection (#349). Choosing
/// a result toggles it, and the sheet stays open for more.
struct CollectionPickerSheet: View {
  let collection: UUID

  @Environment(LibraryModel.self) private var library
  @Environment(\.dismiss) private var dismiss
  @Environment(\.undoManager) private var undoManager
  @State private var query = ""
  @State private var limit = ListWindow.page

  var body: some View {
    // Unsearched, the whole library newest first, as All RFCs lists it:
    // `librarySearch` goes through the same list computation with the `.all` filter.
    let rows = library.librarySearch(query)
    let members = Set(library.collections[collection]?.members ?? [])
    let trigger = ListWindow.triggerRow(limit: limit, total: rows.count).map { rows[$0].id }
    NavigationStack {
      List(rows.prefix(limit)) { rfc in
        Button {
          library.editCollections {
            try CollectionStore.toggle(rfc.id, in: collection, undoManager: undoManager, in: $0)
          }
        } label: {
          HStack {
            RFCRow(rfc: rfc, isBookmarked: false)
            Image(systemName: members.contains(rfc.id) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(members.contains(rfc.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(members.contains(rfc.id) ? .isSelected : [])
        .onAppear {
          guard rfc.id == trigger else { return }
          limit = ListWindow.extendedLimit(from: limit, total: rows.count)
        }
      }
      .searchable(text: $query, prompt: "Search RFCs")
      .onChange(of: query) { limit = ListWindow.page }
      .navigationTitle("Add to \(library.title(for: .collection(collection)))")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }
}
```

- [ ] **Step 2: Present it, and the empty state**

In `RFCListView` add:

```swift
  /// The collection the picker adds to, while it is on show.
  @State private var addingTo: PickerTarget?

  /// The collection the list shows, if it shows one.
  private var collection: UUID? {
    if case .collection(let identifier) = navigation.filter { identifier } else { nil }
  }
```

and at the end of the file:

```swift
/// A collection to add to, as a sheet's item.
private struct PickerTarget: Identifiable {
  let id: UUID
}
```

Then:
- iOS, in the list's `.toolbar`: `if let collection { ToolbarItem(placement: .primaryAction) { Button { addingTo = PickerTarget(id: collection) } label: { Label("Add", systemImage: "plus") } } }`
- macOS, on the `List` inside `#if os(macOS)`:

```swift
      .safeAreaInset(edge: .bottom) {
        if let collection {
          HStack {
            Button {
              addingTo = PickerTarget(id: collection)
            } label: {
              Label("Add RFCs…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
          }
          .padding(8)
        }
      }
```

- On the `List`, both platforms: `.sheet(item: $addingTo) { CollectionPickerSheet(collection: $0.id) }`. On the Mac the list is a hosted root handed `LibraryModel` by `host(_:)`, so the sheet's environment resolves.
- In the overlay, before the generic `ContentUnavailableView("No …")`, an empty, unsearched collection gets its own state:

```swift
        if navigation.searchText.trimmingCharacters(in: .whitespaces).isEmpty,
          let collection
        {
          ContentUnavailableView {
            Label("No Documents", systemImage: "folder")
          } description: {
            Text("Add RFCs from the reader, from any list, or here.")
          } actions: {
            Button("Add RFCs…") { addingTo = PickerTarget(id: collection) }
          }
        } else if navigation.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
          // the existing "No \(title)" view, unchanged
        } else {
          ContentUnavailableView.search(text: navigation.searchText)
        }
```

- [ ] **Step 3: Build and check**

```bash
make fmt && make lint && make build-app && make ios-sim && make run && make run-device IOS_DEVICE=Charon
```

- An empty collection says No Documents and offers Add RFCs….
- Add opens the picker; scrolling pages in more of the library; search narrows it; tapping marks and adds, tapping again removes; the list behind updates at once.
- Fill one collection with about eight RFCs for Task 10's checks.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Add documents to a collection from a picker over the library" -m "Searchable and paged like the list, each document marked when it is already in the collection; choosing one toggles it and the picker stays open. An empty collection says so and offers the picker.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 10: Reordering, removal and VoiceOver

**Files:**
- Modify: `App/RFCReader/Views/RFCListView.swift`

**Interfaces:**
- Consumes: `ListOptions.allowsMoving`; `CollectionStore.move`, `.remove`; `LibraryModel.editCollections`; `RFCListView.collection` (Task 9).
- Produces: `MacRowActions` (a Mac row's context menu), which Task 12 extends.

- [ ] **Step 1: Read the list's current structure**

Read `RFCListView.swift` in full: the `row` closure, the `#if os(macOS)` / `#else` `ForEach` branches, the overlay, and `RowActions`.

- [ ] **Step 2: Moves and removals**

Add to `RFCListView`:

```swift
  @Environment(\.undoManager) private var undoManager

  /// A drag in the visible rows, resolved by their documents rather than their
  /// offsets: the rows on screen may hide obsolete documents or be only the first
  /// pages (`CollectionOrder.neighbours`).
  private func move(from source: IndexSet, to destination: Int, in visible: [RFCMetadata]) {
    guard let collection, let moved = source.first.map({ visible[$0] }) else { return }
    var reordered = visible
    reordered.move(fromOffsets: source, toOffset: destination)
    guard let index = reordered.firstIndex(where: { $0.id == moved.id }) else { return }
    let above = index > 0 ? reordered[index - 1].id : nil
    let below = index + 1 < reordered.count ? reordered[index + 1].id : nil
    library.editCollections {
      try CollectionStore.move(
        moved.id, in: collection, afterVisible: above, beforeVisible: below, in: $0)
    }
  }

  private func remove(_ document: DocumentID) {
    guard let collection else { return }
    library.editCollections {
      try CollectionStore.remove(document, from: collection, undoManager: undoManager, in: $0)
    }
  }

  /// VoiceOver's Move Up and Move Down, one row at a time.
  private func step(_ rfc: RFCMetadata, by offset: Int, in visible: [RFCMetadata]) {
    guard let index = visible.firstIndex(where: { $0.id == rfc.id }) else { return }
    let target = index + offset
    guard visible.indices.contains(target) else { return }
    move(from: [index], to: offset > 0 ? target + 1 : target, in: visible)
  }
```

In `body`, compute once beside `rows`:

```swift
    let allowsMoving = navigation.listOptions.allowsMoving(
      in: navigation.filter, query: navigation.searchText)
    let visible = Array(window)
```

Change the unsectioned `ForEach(window) { row($0, true) }` (both platforms' branches) to:

```swift
        ForEach(window) { rfc in
          row(rfc, true)
            .accessibilityActions {
              if allowsMoving {
                Button("Move Up") { step(rfc, by: -1, in: visible) }
                Button("Move Down") { step(rfc, by: 1, in: visible) }
              }
            }
        }
        .onMove(perform: allowsMoving ? { move(from: $0, to: $1, in: visible) } : nil)
        .onDelete(perform: collection == nil ? nil : { offsets in
          offsets.map { visible[$0].id }.forEach(remove)
        })
```

A collection is never year-sectioned (Task 6), so this branch is the one it uses.

- [ ] **Step 3: Platform controls**

iOS, in the list's `.toolbar`, add Edit for a collection:

```swift
        if collection != nil {
          ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
```

macOS, on the `List` inside `#if os(macOS)`:

```swift
      .onDeleteCommand {
        if let selection = navigation.selection { remove(selection) }
      }
```

and a row context menu for Mac rows — add below `RowActions` in the file:

```swift
#if os(macOS)
  /// What a Mac list row offers on a right click (#349). Grows in Task 12.
  struct MacRowActions: ViewModifier {
    let rfc: RFCMetadata
    let collection: UUID?
    let remove: (DocumentID) -> Void

    func body(content: Content) -> some View {
      content.contextMenu {
        if collection != nil {
          Button("Remove from Collection") { remove(rfc.id) }
        }
      }
    }
  }
#endif
```

and in the `row` closure, beside the iOS `RowActions` line:

```swift
        #if os(macOS)
          .modifier(MacRowActions(rfc: rfc, collection: collection, remove: remove))
        #endif
```

- [ ] **Step 4: Build and check on the devices**

```bash
make fmt && make lint && make build-app && make ios-sim && make run && make run-device IOS_DEVICE=Charon
```

With the collection filled through the picker in Task 9:
- iOS: Edit, drag a row, the order sticks after leaving the list and coming back; swipe removes; shake to undo restores it in place.
- Mac: drag reorders; Delete removes the selected row; Edit ▸ Undo restores it in place; right click offers Remove from Collection.
- VoiceOver on iOS: the rotor's Actions offer Move Up and Move Down.
- Searching the collection disables reordering.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Rearrange and remove a collection's documents" -m "Drag to reorder in the collection's own order, resolved by the visible neighbours; remove by swipe, Delete or a right click, undoably, back to the same place. VoiceOver offers Move Up and Move Down.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 11: Sort options on both platforms

**Files:**
- Modify: `App/RFCReader/Views/RFCListView.swift` (`optionsMenu`)
- Modify: `App/RFCReader/RFCReaderApp.swift` (View menu, macOS)

**Interfaces:**
- Consumes: `ListOptions.CollectionSort`, `collectionSort`, `canReorder`.

- [ ] **Step 1: iOS**

In `optionsMenu`, replace the `if ListOptions.canReorder(...)` block with:

```swift
        if case .collection = navigation.filter {
          Picker("Sort", selection: $navigation.listOptions.collectionSort) {
            ForEach(ListOptions.CollectionSort.allCases, id: \.self) { sort in
              Text(sort.title)
            }
          }
        } else if ListOptions.canReorder(navigation.filter, query: navigation.searchText) {
          Picker("Sort", selection: $navigation.listOptions.order) {
            ForEach(ListOptions.Order.allCases, id: \.self) { order in
              Text(order.title)
            }
          }
        }
```

- [ ] **Step 2: macOS View menu**

In `RFCReaderApp.swift`'s macOS commands, add a group (the Mac had no view options at all before):

```swift
    #if os(macOS)
      CommandGroup(after: .toolbar) {
        if let navigation {
          ListViewOptions(navigation: navigation)
        }
      }
    #endif
```

and at the end of the file:

```swift
#if os(macOS)
  /// View ▸ Sort By and View ▸ Show Obsolete, for the key window's list (#349). The
  /// Mac had no way to reach the list's view options before.
  private struct ListViewOptions: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
      Section {
        if case .collection = navigation.filter {
          Picker("Sort By", selection: $navigation.listOptions.collectionSort) {
            ForEach(ListOptions.CollectionSort.allCases, id: \.self) { Text($0.title) }
          }
        } else {
          Picker("Sort By", selection: $navigation.listOptions.order) {
            ForEach(ListOptions.Order.allCases, id: \.self) { Text($0.title) }
          }
          .disabled(!ListOptions.canReorder(navigation.filter, query: navigation.searchText))
        }
        Toggle("Show Obsolete", isOn: $navigation.listOptions.showsObsolete)
      }
    }
  }
#endif
```

- [ ] **Step 3: Build and check**

```bash
make fmt && make lint && make build-app && make ios-sim && make run && make run-device IOS_DEVICE=Charon
```

- iOS: the `…` menu in a collection offers Manual/Newest First/Oldest First; in All RFCs the old Newest/Oldest picker is unchanged.
- Mac: View ▸ Sort By and Show Obsolete follow the key window's tab, and a tab set to Oldest First for All RFCs still opens a collection in Manual order.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Offer a collection's sort order, and the Mac's view options" -m "A collection sorts manually, newest first or oldest first. The Mac gets View > Sort By and View > Show Obsolete for every list, which it had no way to reach before.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Step 4 of the spec: adding from elsewhere

### Task 12: The Add to Collection menu everywhere

**Files:**
- Create: `App/RFCReader/Views/Collections/AddToCollectionItems.swift`
- Modify: `App/RFCReader/Views/DocumentView.swift` (iOS `bookmarkButton`)
- Modify: `App/RFCReader/Views/RFCListView.swift` (`RowActions`, `MacRowActions`)
- Modify: `App/RFCReader/Window/ReaderToolbar.swift` (`.rfcBookmark` item, `menuNeedsUpdate`)
- Modify: `App/RFCReader/RFCReaderApp.swift` (Edit menu section with Bookmark)

**Interfaces:**
- Consumes: `LibraryModel.collections`, `editCollections`; `CollectionStore.toggle`; `NavigationModel.collectionEditor`; `CollectionEditorMode.create(adding:)`.
- Produces: `AddToCollectionItems(document:library:navigation:undoManager:)`; `AddToCollectionSheet(document:)`.

- [ ] **Step 1: The shared menu items and sheet**

```swift
import RFCKit
import RFCReaderKit
import SwiftUI

/// Every collection, checked where the document is already in it, and New
/// Collection (#349). One set of items for every entry point: the reader, list
/// rows, and the Mac's menu bar.
///
/// Takes its models as properties rather than from the environment: the Mac's
/// menu bar has no environment to read them from.
struct AddToCollectionItems: View {
  let document: DocumentID
  let library: LibraryModel
  let navigation: NavigationModel
  var undoManager: UndoManager?
  /// Called after New Collection has asked for the editor, so a sheet showing
  /// these items can get out of the editor's way.
  var onNewCollection: (() -> Void)?

  var body: some View {
    let containing = library.collections.collections(containing: document)
    ForEach(library.collections.collections) { entry in
      Toggle(
        entry.name,
        isOn: Binding(
          get: { containing.contains(entry.id) },
          set: { _ in
            library.editCollections {
              try CollectionStore.toggle(document, in: entry.id, undoManager: undoManager, in: $0)
            }
          }))
    }
    if !library.collections.collections.isEmpty { Divider() }
    Button("New Collection…") {
      navigation.collectionEditor = .create(adding: document)
      onNewCollection?()
    }
  }
}

/// The same choice as a sheet, for a swipe action, which cannot open a menu.
struct AddToCollectionSheet: View {
  let document: DocumentID

  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(\.undoManager) private var undoManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        // The editor is presented by the window's root, so this sheet steps aside
        // for it.
        AddToCollectionItems(
          document: document, library: library, navigation: navigation,
          undoManager: undoManager, onNewCollection: { dismiss() })
      }
      .navigationTitle("Add to Collection")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
```

- [ ] **Step 2: iOS reader**

In `DocumentView`, replace `bookmarkButton`'s `Button` with a `Menu` with a primary action:

```swift
    private var bookmarkButton: some View {
      // Read once: a linear scan of the bookmarks, and the label wants it twice.
      let bookmarked = isBookmarked
      // A tap bookmarks, as before; a long press adds to a collection (#349).
      return Menu {
        AddToCollectionItems(
          document: id, library: library, navigation: navigation, undoManager: undoManager)
      } label: {
        Label(
          bookmarked ? "Remove Bookmark" : "Bookmark",
          systemImage: bookmarked ? "bookmark.fill" : "bookmark")
      } primaryAction: {
        toggleBookmark()
      }
      .keyboardShortcut("d", modifiers: .command)
    }
```

Add `@Environment(\.undoManager) private var undoManager` to `DocumentView` (under `#if !os(macOS)` beside the other iOS-only environment values).

**To verify (spec):** ⌘D on an iPad keyboard still bookmarks. If the shortcut does not reach the primary action, move it to a hidden button beside the menu in the same `ToolbarItem`:

```swift
      Button("Bookmark", action: toggleBookmark)
        .keyboardShortcut("d", modifiers: .command)
        .hidden()
```

- [ ] **Step 3: List rows**

iOS `RowActions`: add `@Environment(LibraryModel.self)`, `@Environment(NavigationModel.self)`, `@Environment(\.undoManager)` and `@State private var isChoosingCollection = false`; in `.contextMenu` after Bookmark:

```swift
          Menu("Add to Collection") {
            AddToCollectionItems(
              document: rfc.id, library: library, navigation: navigation, undoManager: undoManager)
          }
```

in `.swipeActions(edge: .leading)` after the Bookmark button:

```swift
          Button {
            isChoosingCollection = true
          } label: {
            Label("Add to Collection", systemImage: "folder.badge.plus")
          }
          .tint(.indigo)
```

and on `content`: `.sheet(isPresented: $isChoosingCollection) { AddToCollectionSheet(document: rfc.id) }`.

macOS `MacRowActions`: give it `library`, `navigation` and `undoManager` properties passed from the `row` closure, and in its `contextMenu` put, before the Remove item:

```swift
        Menu("Add to Collection") {
          AddToCollectionItems(
            document: rfc.id, library: library, navigation: navigation, undoManager: undoManager)
        }
```

- [ ] **Step 4: The Mac's menu bar**

In `RFCReaderApp.swift`'s `CommandGroup(after: .pasteboard)` section, after the Bookmark button:

```swift
          if let navigation, let document = navigation.selection {
            Menu("Add to Collection") {
              AddToCollectionItems(
                document: document, library: .shared, navigation: navigation,
                undoManager: active.controller?.window?.undoManager)
            }
          }
```

The key window's undo manager, so Edit ▸ Undo puts back a document removed from here, as it does for a removal in the list.

- [ ] **Step 5: The Mac's toolbar**

In `ReaderToolbar`, add `private let collectionMenu = NSMenu()` beside `citeMenu`, set its delegate beside theirs, and replace the `.rfcBookmark` case:

```swift
      case .rfcBookmark:
        // A click bookmarks; the indicator opens Add to Collection (#349).
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = "Bookmark"
        item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmark")
        item.showsIndicator = true
        item.target = self
        item.action = #selector(toggleBookmark)
        item.menu = collectionMenu
        return item
```

In `menuNeedsUpdate(_:)`, add:

```swift
      case collectionMenu:
        let library = LibraryModel.shared
        let containing = id.map { library.collections.collections(containing: $0) } ?? []
        for entry in library.collections.collections {
          let item = NSMenuItem(
            title: entry.name, action: #selector(toggleCollection), keyEquivalent: "")
          item.target = self
          item.representedObject = entry.id
          item.state = containing.contains(entry.id) ? .on : .off
          menu.addItem(item)
        }
        if !library.collections.collections.isEmpty { menu.addItem(.separator()) }
        add(to: menu, "New Collection…", #selector(newCollection))
```

and the actions:

```swift
    @objc private func toggleCollection(_ sender: NSMenuItem) {
      guard let document = id, let collection = sender.representedObject as? UUID else { return }
      LibraryModel.shared.editCollections {
        try CollectionStore.toggle(
          document, in: collection, undoManager: controller.window?.undoManager, in: $0)
      }
    }

    @objc private func newCollection() {
      navigation.collectionEditor = .create(adding: id)
    }
```

(`id` and `navigation` are the toolbar's existing private accessors; the toolbar reaches the library as `LibraryModel.shared`, as its `metadata` does.)

**To verify (spec):** a click on the item bookmarks and the indicator opens the menu; `validateToolbarItem` still swaps the glyph between `bookmark` and `bookmark.fill`. If a click opens the menu instead of bookmarking, keep the item a plain button (the old `button(identifier, "Bookmark", "bookmark", #selector(toggleBookmark))`), drop `collectionMenu`, and rely on the menu bar's and the row's Add to Collection; say so in the commit message.

- [ ] **Step 6: Build and check**

```bash
make fmt && make lint && make build-app && make ios-sim && make run && make run-device IOS_DEVICE=Charon
```

- iOS reader: tap Bookmark bookmarks; long press shows collections with checkmarks and New Collection…, which creates one with the document in it.
- iOS list: long press offers Add to Collection; the second leading swipe opens the sheet.
- Mac: right click on a row, Edit ▸ Add to Collection, and the toolbar's indicator all offer the same menu.
- A document added from the reader's menu appears at the end of the collection's list, and Task 10's reorder still places it.

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "Add to a collection from the reader and from any list" -m "One menu of collections, checked where the document is already in, and New Collection: a long press on the reader's Bookmark on iOS, a row's context menu and swipe, and on the Mac the menu bar, a right click and the toolbar's Bookmark indicator.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Step 5 of the spec: drag and drop

### Task 13: Drop rows onto a sidebar collection

**Files:**
- Modify: `App/RFCReader/Views/RFCListView.swift` (the `row` closure)
- Modify: `App/RFCReader/Views/SidebarView.swift` (`collectionRow`)

- [ ] **Step 1: Rows carry their document**

In the `row` closure, after `.tag(rfc.id)`:

```swift
        // An item provider rather than `.draggable`: it cooperates with `.onMove`,
        // which a collection's own list also uses (#349).
        .itemProvider { NSItemProvider(object: rfc.id.fileStem as NSString) }
```

- [ ] **Step 2: Collections accept them**

On `collectionRow`'s `HStack`, before `.tag(filter)`:

```swift
    .dropDestination(for: String.self) { keys, _ in
      let documents = keys.compactMap(DocumentID.init(fileStem:))
      guard !documents.isEmpty else { return false }
      library.editCollections { context in
        for document in documents {
          try CollectionStore.add(document, to: entry.id, in: context)
        }
      }
      return true
    }
```

- [ ] **Step 3: Build and check**

```bash
make fmt && make lint && make build-app && make ios-sim && make run
```

- Mac: drag a row from All RFCs onto a collection; it is added at the end; reordering inside a collection still works.
- iPad (or the iPhone in a regular-width landscape, if available): the same. If no iPad is available, say so in the commit message.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Drop documents onto a collection in the sidebar" -m "List rows carry their document through an item provider, which cooperates with a collection's own reordering; a collection in the sidebar accepts them, adding each at the end.

Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Close-out

### Task 14: Architecture record and the full check

**Files:**
- Modify: `docs/ARCHITECTURE.md` (the data-flow diagram line naming `Bookmark, ReadingPosition`; a new decision after the #152 decision)

- [ ] **Step 1: The decision record**

In the diagram line (`SwiftData ── Bookmark, ReadingPosition …`), add `DocumentCollection, DocumentCollectionItem`.

After the "Decision: the user data store is versioned, keyed on the document, and in CloudKit's shape" section, add:

```markdown
## Decision: collections are rows linked by identifier, ordered by position

*Decided September 2026 (issue #349).* A collection is a `DocumentCollection` and its members are `DocumentCollectionItem` rows naming it by identifier, in `SchemaV4`. Not a SwiftData relationship: with one, the collection's to-many side is what two devices both edit once sync is on; as independent rows, two devices adding to one collection each insert a row and nothing is lost.

Items are ordered by `(position, addedAt, documentKey)`. Positions are `Double`s, so a move takes the midpoint of its neighbours and writes one row; a gap too narrow to split, or two equal positions after offline appends, renumbers the collection first (`CollectionOrder`). A move made in a list that hides rows resolves by the visible neighbours' documents, never by offset. A reorder racing a renumber on another device may misplace one item; that is accepted.

Items whose collection is missing are not deleted. Under sync they may simply have arrived before it, and deleting them would sync back and empty the collection where it was made; nothing shows them, since every list and count is computed per existing collection. A sweep with a grace period belongs to the sync work.

Every change is made by `CollectionStore` and read through `CollectionSnapshot`, both in `RFCReaderKit` and tested there. A colour is stored by name from a fixed palette (`CollectionColor`), so it adapts to dark mode and an older device reads a name it does not know as the default.
```

- [ ] **Step 2: The full check**

```bash
make fmt && make check && make test-app && make build-app && make ios-sim
```
Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "Record the collections decision" -m "Refs #349

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
