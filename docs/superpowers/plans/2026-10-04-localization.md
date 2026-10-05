# Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every text a user sees outside the reader body is in a string catalog (#751), a lint rule keeps it that way (#785), and the app ships in German (#786).

**Architecture:** The app target resolves with `String(localized:)`. RFCReaderKit's models keep `String` fields and resolve their words through `String(kit:locale:)` in a locale they are given, `Locale.interface` by default, so tests pin English. Catalogs are synced from the compiler's `.stringsdata` by `make strings` (#752); German adds a completeness check to `make strings-check`.

**Tech Stack:** Swift 6, Swift Testing, String Catalogs (`.xcstrings`), `xcstringstool`, SwiftLint `custom_rules`, Python 3.9 standard library.

**Spec:** `docs/superpowers/specs/2026-10-04-localization-design.md`

## Global Constraints

- Three pull requests stacked on `string-catalogs` (#752): `issue/751-localize-remaining-strings` → `issue/785-raw-string-lint` → `issue/786-german`. Each is based on the one below.
- The reader body and its exports stay English: nothing under `Rendering/DocumentTextBuilder*`, `PDFExport`, `GrammarExport`, the requirements CSV in `RequirementList`, `PacketSummary`, `AccessibleReading`.
- RFCKit gets no catalog and no localization; it must stay buildable on Linux.
- Keys come only from the code; never add or remove a key in an `.xcstrings` by hand. Translations and English plural variants are catalog content and may be edited.
- RFCReaderKit models take `locale: Locale = .interface`; tests pass `locale: .english` (a test-only constant, Task 1).
- American spelling in code, comments and English strings.
- Tests: Swift Testing, raw-identifier names (``@Test func `…`()``).
- Every commit signed; if Secretive is locked: `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`. Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Lines ≤ 200 characters; `make fmt` before every commit that touches Swift.

## Review Focus

1. **A reader whose first language the app lacks** (French, then German): the chrome must be German, not English. Pinned by Task 1's `Locale.interface` test, which checks it follows `Bundle.module.preferredLocalizations` rather than `Locale.current`.
2. **A German list joined in English**: a notice in German must say "RFC 1 und RFC 2". Pinned in Task 16's proof test through `BookmarkNotice.notices(…, locale: de)`.
3. **A count of one**: "1 RFC", "1 document" must not read "1 RFCs", in English or German. Pinned in Task 5 (English plural variants) and Task 16 (German).
4. **A user's own text that looks like a key** (a collection named "Errata"): it must show as typed, never translated. Pinned in Task 2 (English) and in Task 16 (German), each asserting a collection named "Errata" keeps its name.
5. **A string added later without German**: `make strings-check` must fail and name it. Pinned in Task 15 by running the check against a deliberately untranslated key.

---

# Pull request 1: #751 — everything in a catalog

### Task 0: Claim #751

**Files:** none.

- [ ] **Step 1:** In the worktree `.claude/worktrees/issue-751` (branch `issue/751-localize-remaining-strings`, already holding the spec and this plan), push: `git push -u origin issue/751-localize-remaining-strings`.
- [ ] **Step 2:** Open the draft: `gh pr create --draft --base string-catalogs --title "Localize the text no string catalog can find yet" --body "Closes #751. Stacked on #752.\n\nWork has started; the plan is docs/superpowers/plans/2026-10-04-localization.md."` (use a heredoc for real newlines). Add `agent-pr` to #751: `gh issue edit 751 --add-label agent-pr`.

### Task 1: The helper, `Locale.interface`, and proof the compiler finds the keys

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Localization.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/LocalizationTests.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData/CollectionStore.swift:124,148`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/FigureMenu.swift:10-11`

**Interfaces:**
- Produces: `String.init(kit: String.LocalizationValue, locale: Locale)`; `Locale.interface: Locale` (public); in tests, `Locale.english` (`Locale(identifier: "en")`) and `Locale.german` (`Locale(identifier: "de")`).

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing

@testable import RFCReaderKit

extension Locale {
  /// What tests resolve in, whatever the machine running them prefers.
  static let english = Locale(identifier: "en")
  static let german = Locale(identifier: "de")
}

@Suite("Localization")
struct LocalizationTests {
  @Test func `a key resolves to its English text in English`() {
    #expect(String(kit: "Remove from Collection", locale: .english) == "Remove from Collection")
  }

  @Test func `the interface language is the one the catalog resolves to, not the region's`() {
    let resolved = Bundle.module.preferredLocalizations.first ?? "en"
    #expect(Locale.interface.language.languageCode?.identifier == Locale(identifier: resolved).language.languageCode?.identifier)
  }
}
```

- [ ] **Step 2: Run them, expect a compile failure** (`String(kit:locale:)` and `Locale.interface` don't exist).

Run: `swift test --package-path Packages/RFCReaderKit --filter LocalizationTests`
Expected: FAIL, "no exact matches in call to initializer" / "type 'Locale' has no member 'interface'".

- [ ] **Step 3: Write `Localization.swift`**

```swift
import Foundation

extension String {
  /// `key` from RFCReaderKit's catalog, in `locale`'s language.
  ///
  /// The models resolve their words in a locale they are given rather than in the
  /// process's, so a test can pin English on a Mac whose first language is German,
  /// and resolve German on purpose (decision "The app's chrome is localized, the
  /// reader body is not").
  init(kit key: String.LocalizationValue, locale: Locale) {
    var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    resource.locale = locale
    self.init(localized: resource)
  }
}

extension Locale {
  /// The language the chrome is shown in: the one RFCReaderKit's catalog resolves to
  /// for this process. Not `Locale.current`, whose language can be one the app does
  /// not have — French first and German second gives German here, and English there.
  public static var interface: Locale {
    Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
  }
}
```

- [ ] **Step 4: Convert two call sites, as the extraction probe.** In `CollectionStore.swift` lines 124 and 148: `undoManager?.setActionName(String(kit: "Remove from Collection", locale: .interface))`. In `FigureMenu.swift`, read the property that returns `"Show as Text"` / `"Show as Figure"`, give it a `locale: Locale = .interface` parameter (making it a function if it is a property), and return `String(kit: "Show as Text", locale: locale)` and `String(kit: "Show as Figure", locale: locale)`. Fix its callers the compiler names; pass `locale: .english` in its tests.

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path Packages/RFCReaderKit --filter "LocalizationTests|FigureMenu"`
Expected: PASS.

- [ ] **Step 6: Check the compiler records keys passed to the helper**

Run: `make strings && git diff --stat -- '*.xcstrings' && grep -c '"Show as Text"' Packages/RFCReaderKit/Sources/RFCReaderKit/Resources/Localizable.xcstrings`
Expected: RFCReaderKit's catalog gains "Show as Text" and "Show as Figure" (count 1).

If it does **not** (count 0): change the helper's parameter to `_ resource: LocalizedStringResource` and set `resource.bundle = .atURL(Bundle.module.bundleURL)` inside, so call sites read `String(kit: "Show as Text", locale: locale)` unchanged (a literal converts to `LocalizedStringResource`, which the compiler records). Re-run Steps 5–6. Record which form worked in the commit message.

- [ ] **Step 7: Commit**

```bash
make fmt
git add Packages/RFCReaderKit App/RFCReader/Localizable.xcstrings
git commit -m "RFCReaderKit resolves its words in a locale it is given (#751)

String(kit:locale:) looks a key up in RFCReaderKit's catalog in a pinned
language, so tests keep English on a German Mac. Locale.interface is the
language the catalog resolves to for this process.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 2: Menus — `DocumentMenus`, `DocumentActions`, citation style names

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/CitationStyle+Title.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/DocumentMenus.swift:72-108`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/DocumentActions.swift:33,39`
- Modify: callers in `App/RFCReader/Window/ReaderToolbar.swift:339-347` and wherever the compiler points (SwiftUI menus)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Chrome/DocumentMenusTests.swift`, `Chrome/DocumentActionsTests.swift`

**Interfaces:**
- Consumes: `String(kit:locale:)`, `Locale.interface`, test `Locale.english`.
- Produces: `DocumentMenus.cite(locale: Locale = .interface)`, `DocumentMenus.more(showsOriginal:errata:precedingDraft:locale: Locale = .interface)`, `DocumentMenus.addToCollection(_:in:locale: Locale = .interface)`, `CitationStyle.title(in locale: Locale = .interface) -> String`.

- [ ] **Step 1: Update the tests first.** In `DocumentMenusTests`, every call gains `locale: .english` (`DocumentMenus.cite(locale: .english)`, `DocumentMenus.more(showsOriginal: false, errata: nil, precedingDraft: nil, locale: .english)`, `DocumentMenus.addToCollection(…, locale: .english)`). Add:

```swift
  @Test func `a collection's item is titled with its name as typed`() {
    // A name that is also a key elsewhere must not be looked up.
    let snapshot = CollectionSnapshot(collections: [.init(name: "Errata")], memberships: [:])
    let items = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .english)
    #expect(items[0].map(\.title) == ["Errata"])
  }
```

(Build the `CollectionSnapshot` the way the existing collection tests in this file do; adapt the initializer to theirs.)

In `DocumentActionsTests`, pass `locale: .english` to the bookmark label functions.

- [ ] **Step 2: Run, expect compile failure** (`extra argument 'locale'`).

Run: `swift test --package-path Packages/RFCReaderKit --filter "DocumentMenus|DocumentActions"`

- [ ] **Step 3: Implement.** In `DocumentMenus`, add `locale: Locale = .interface` to `cite`, `more`, `addToCollection`, and wrap each literal title: `Item(String(kit: "Copy Link to Current Section", locale: locale), .copySectionLink)`, likewise "Open on rfc-editor.org", "Errata", "Datatracker", "Preceding Draft", "Original Text", "New Collection…". `cite` uses `$0.title(in: locale)` instead of `$0.displayName`. `collection.name` stays as it is. Create `CitationStyle+Title.swift`:

```swift
import Foundation
import RFCKit

extension CitationStyle {
  /// The style's name in the menu. RFCKit's `displayName` stays English: RFCKit has
  /// no catalog.
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .short: String(kit: "Short", locale: locale)
    case .full: String(kit: "Full citation", locale: locale)
    case .markdown: String(kit: "Markdown link", locale: locale)
    case .bibtex: String(kit: "BibTeX", locale: locale)
    case .url: String(kit: "URL", locale: locale)
    }
  }
}
```

Replace every other use of `CitationStyle.displayName` in `App/` and RFCReaderKit's chrome with `title()` (`grep -rn 'displayName' App Packages/RFCReaderKit/Sources | grep -i style`). In `DocumentActions.swift` lines 33 and 39, the functions returning "Bookmarked"/"Not bookmarked" and "Remove Bookmark"/"Bookmark" gain `locale: Locale = .interface` and use `String(kit:locale:)`.

- [ ] **Step 4: Run tests, expect PASS.** Same command as Step 2.
- [ ] **Step 5: Build the app**: `make xcodeproj build-app` — Expected: success (callers fixed).
- [ ] **Step 6: Commit** (`make fmt`, then `git commit -m "Menus resolve their titles in the interface language (#751)" …` with the trailer).

### Task 3: Library and reader chrome enums

**Files (modify each, with its tests):**
- `Library/LibraryFilter.swift:25-30` — "All RFCs", "Recently Read", "Bookmarks", "Available Offline", "Internet Standards", "Best Current Practices"
- `Library/ListOptions.swift:12-13,28-30` — "Newest First", "Oldest First", "Manual"
- `Library/ListRowLabel.swift:13,18,22,46` — "Obsolete", "Working group %@", "Bookmarked"
- `UserData/CollectionColor.swift:21-29` — the nine color names
- `Rendering/ReadingMode.swift:19-21` — "Normal", "Outline", "Focus"
- `Navigation/ReturnOffer.swift:15-19` — "Back to Top", "Back", "Back to %@"
- `Navigation/QuickOpenResults.swift:49` — "Not in the index", "The index is still loading"
- `LoadState.swift:179-189` — the six failure explanations
- `Chrome/PublishedOriginalPage.swift:47,66,71` — the three explanations
- `ReadingPath/ReadingPath.swift:157` — "Reading Path: %@"
- `IntentAnswer.swift:11-13` — the requirement-count sentences
- `Chrome/AuthorCard.swift:46` — `jobTitle = "Editor"`
- Tests: `Library/LibraryFilterTests.swift`, `Library/ListOptionsTests.swift`, `Library/LibraryRowTests.swift`, `Navigation/ReturnOfferTests.swift`, `Navigation/QuickOpenResultsTests.swift`, `LoadStateTests.swift`, `IntentAnswerTests.swift`, `ReadingPath/*`, `Chrome/AuthorCardTests.swift`

**Interfaces:**
- Produces: each property above that returns one of these strings becomes `func title(in locale: Locale = .interface) -> String` (or keeps its name and gains `in locale:`/`locale:` the same way, if it is already a function). Keep the member's existing name; only add the parameter.

- [ ] **Step 1: Update the tests** to pass `in: .english` / `locale: .english` at every call that reads one of these strings. Where a test compares a whole list of titles, map with `{ $0.title(in: .english) }`.
- [ ] **Step 2: Run, expect compile failure**: `swift test --package-path Packages/RFCReaderKit --filter "LibraryFilter|ListOptions|LibraryRow|ReturnOffer|QuickOpen|LoadState|IntentAnswer|ReadingPath|AuthorCard"`.
- [ ] **Step 3: Implement**, one pattern throughout. Example, `ReadingMode`:

```swift
  public func title(in locale: Locale = .interface) -> String {
    switch self {
    case .normal: String(kit: "Normal", locale: locale)
    case .outline: String(kit: "Outline", locale: locale)
    case .focus: String(kit: "Focus", locale: locale)
    }
  }
```

Interpolations keep their values in the key: `String(kit: "Back to \(PlaceName.abbreviated(sectionPlace))", locale: locale)` becomes key `Back to %@`. `IntentAnswer`'s three-way switch on count becomes one key with plural variants:

```swift
    count == 0
      ? String(kit: "There are no BCP 14 requirements in \(place).", locale: locale)
      : String(kit: "There are \(count) requirements in \(place).", locale: locale)
```

(the `one` variant, "There is one requirement in %@.", is added to the catalog in Task 5 Step 3).

- [ ] **Step 4: Fix the callers.** `make xcodeproj build-app` and the iOS build (`make ios-sim CODE_SIGNING_ALLOWED=NO`) name each one; add `()` (SwiftUI shows the result with `Text(verbatim:)` where the result is a `String` passed to `Text`, so it is not looked up a second time: `Text(verbatim: filter.title())`).
- [ ] **Step 5: Run tests and both builds**, expect PASS.
- [ ] **Step 6: Commit** — "Library and reader chrome resolve their words in the interface language (#751)".

### Task 4: The inspector — `DocumentInfo` and `Glossary`

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/PublicationDate+Formatted.swift`
- Modify: `Chrome/DocumentInfo.swift` (lines 46, 115-120, 129-138, 156-159, 178, 189-200, 224-233, 242-253, 264-268), `Chrome/Glossary.swift` (every `title:` and `summary:`, lines ~105-320)
- Modify: `App/RFCReader/Views/Rendering/InfoView.swift:77` and its other plain strings
- Test: `Chrome/DocumentInfoTests.swift`, `SpotlightEntryTests.swift`, and a Glossary test if one exists

**Interfaces:**
- Produces: `DocumentInfo` initializer/builder gains `locale: Locale = .interface`; `Glossary`'s entry builders gain `locale: Locale = .interface`; `PublicationDate.formatted(in locale: Locale = .interface) -> String`.

- [ ] **Step 1: Tests first**: pass `locale: .english` to every `DocumentInfo` and `Glossary` construction in the tests; expectations unchanged.
- [ ] **Step 2: Run, expect compile failure**: `swift test --package-path Packages/RFCReaderKit --filter "DocumentInfo|Glossary|SpotlightEntry"`.
- [ ] **Step 3: Implement.** Wrap every word literal listed above in `String(kit:locale:)`, threading `locale` through the static helpers (`section`, `facts`, `relationships`, `links`, `formats`, `details`, `areaName`, `formatName`). Stay verbatim: SF Symbol names (`"globe"`, `"doc.text"`, …), `"DOI"`, `"HTML"`, `"XML"`, `"PDF"`, `"PostScript"` (names, not words — leave them as plain strings), status/stream/series `displayName`s from RFCKit. `"Part of \(series.displayName)"` becomes key `Part of %@`. The date: create

```swift
import Foundation
import RFCKit

extension PublicationDate {
  /// "June 2022", or "2022" when the month is unknown, in `locale`'s language.
  /// RFCKit's `formatted` stays English: RFCKit has no catalog.
  public func formatted(in locale: Locale = .interface) -> String {
    guard let month,
      let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month))
    else { return String(year) }
    return date.formatted(.dateTime.month(.wide).year().locale(locale))
  }
}
```

and use it at `DocumentInfo.swift:224` instead of `metadata.date.formatted`. `Glossary` titles that are IETF designations ("IETF Stream", "RFC Series", "Internet-Draft", "Working Group", "Errata") still go through `String(kit:)`: the German translation decides whether they stay English.
- [ ] **Step 4: Run tests, expect PASS** (the date test, if any, still reads "June 2022" in English).
- [ ] **Step 5:** `make xcodeproj build-app`, fix `InfoView` callers; `InfoView.swift:77`'s `title: "Obsolete"` becomes `title: String(localized: "Obsolete")`.
- [ ] **Step 6: Commit** — "The inspector resolves its words in the interface language (#751)".

### Task 5: Working groups and revisions, with plural variants

**Files:**
- Modify: `Library/WorkingGroupSummary.swift:33-104`, `RevisionsSummary.swift:73-125`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Resources/Localizable.xcstrings` (English plural variants only, after `make strings`)
- Test: `Library/WorkingGroupSummaryTests.swift`, `RevisionsSummaryTests.swift`

**Interfaces:**
- Produces: `WorkingGroupSummary.init(acronym:group:rfcs:locale: Locale = .interface)`; `RevisionsSummary.stageName(_:stream:locale:)`, `RevisionsSummary.stagePhrase(_:stream:locale:)` (mid-sentence form), `RevisionsSummary.relationLabel(_:locale:)`.

- [ ] **Step 1: Tests first.** Pass `locale: .english` to every `WorkingGroupSummary(…)` and to `RevisionsSummary`'s helpers. Add the count-of-one case if missing:

```swift
  @Test func `one RFC is counted in the singular`() {
    let summary = WorkingGroupSummary(acronym: "tls", group: nil, rfcs: [rfc(2003)], locale: .english)
    #expect(summary.publications == "1 RFC, 2003")
  }
```

(build `rfc(_:)` the way the suite's existing tests build metadata.)
- [ ] **Step 2: Run, expect compile failure**: `swift test --package-path Packages/RFCReaderKit --filter "WorkingGroupSummary|RevisionsSummary"`.
- [ ] **Step 3: Implement `WorkingGroupSummary`.** `typeName`, `stateName` and the link titles go through `String(kit:locale:)` ("BoF", "IAB", "IRTF" included; `slug.capitalized` and the area stay as given). `publications` becomes:

```swift
  private static func publications(_ rfcs: [RFCMetadata], locale: Locale) -> String? {
    let years = rfcs.map(\.date.year)
    guard let first = years.min(), let latest = years.max() else { return nil }
    let count = String(kit: "\(rfcs.count) RFCs", locale: locale)
    // Obsolete as the list's Show Obsolete means it, counted whatever that hides.
    let obsolete = rfcs.count(where: \.isObsolete)
    let span = first == latest ? "\(first)" : "\(first)–\(latest)"
    if obsolete == 0 {
      return [count, span].joined(separator: ", ")
    }
    let state =
      obsolete < rfcs.count
      ? String(kit: "\(obsolete) obsolete", locale: locale)
      : rfcs.count == 1
        ? String(kit: "obsolete", locale: locale) : String(kit: "all obsolete", locale: locale)
    return [count, state, span].joined(separator: ", ")
  }
```

- [ ] **Step 4: Implement `RevisionsSummary`.** `relationLabel`, `stageName` and the fragments (`"and \(n) more"`, `", as of \($0)"`, `"intended \(status)"`, `", revision of \($0)"`, `"\(relation) \(revision.draft), revision \(number)"`, `" from \(dormant)"`) go through `String(kit:locale:)` using the summary's existing `locale`. Add `stagePhrase(_:stream:locale:)`, the same switch as `stageName` with lowercase-initial English keys ("in the RFC Editor queue", "approved for publication", "under IESG review", "in IETF Last Call", "submitted for publication", "in working group last call", "under review", "in the working group"); it replaces `lowercasingFirst(stageName(…))` at both call sites (`grep -rn lowercasingFirst Packages`), and `lowercasingFirst` is deleted if nothing else uses it.
- [ ] **Step 5: Sync and add English plural variants.** Run `make strings`. Then, in RFCReaderKit's catalog, give `%lld RFCs` English variations — `one`: `%lld RFC`, `other`: `%lld RFCs` — and in the same way `There are %lld requirements in %@.` (`one`: `There is one requirement in %@.`). Edit with Python so the JSON stays as `xcstringstool` writes it:

```bash
python3 - <<'EOF'
import json
p = "Packages/RFCReaderKit/Sources/RFCReaderKit/Resources/Localizable.xcstrings"
d = json.load(open(p))
def plural(key, one, other):
    d["strings"][key]["localizations"] = {"en": {"variations": {"plural": {
        "one": {"stringUnit": {"state": "translated", "value": one}},
        "other": {"stringUnit": {"state": "translated", "value": other}}}}}}
plural("%lld RFCs", "%lld RFC", "%lld RFCs")
plural("There are %lld requirements in %@.", "There is one requirement in %@.", "There are %lld requirements in %@.")
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False, separators=(",", " : "))
EOF
make strings && git diff --stat -- '*.xcstrings'
```

Expected: the second `make strings` leaves the file as the script wrote it (if `xcstringstool` reformats it, keep its formatting).
- [ ] **Step 6: Run tests, expect PASS**, including "1 RFC, 2003" and IntentAnswer's one-requirement case.
- [ ] **Step 7: Commit** — "Working groups and revisions resolve their words, counting in the plural (#751)".

### Task 6: Notifications

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/BookmarkEvents.swift:155-195`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BookmarkEventsTests.swift`

**Interfaces:**
- Consumes: `RevisionsSummary.relationLabel(_:locale:)`, `RevisionsSummary.stagePhrase(_:stream:locale:)` (Task 5).
- Produces: `BookmarkNotice.notices(for:index:locale: Locale = .interface)`.

- [ ] **Step 1: Tests first.** Pass `locale: .english` to every `notices(…)` call. The three-document list changes to the Oxford comma that `.list(type: .and)` writes in English: update the expectation from `"RFC 9996, RFC 9997 and RFC 9998"` to `"RFC 9996, RFC 9997, and RFC 9998"`. The revision line keeps its English: `"Being replaced by draft-x, in the working group."`-shaped expectations stay as they are.
- [ ] **Step 2: Run, expect failure**: `swift test --package-path Packages/RFCReaderKit --filter BookmarkEvents`.
- [ ] **Step 3: Implement**:

```swift
  private static func line(_ event: BookmarkEvent, locale: Locale) -> String {
    switch event {
    case .obsoleted(_, let documents):
      String(kit: "Obsoleted by \(list(documents, locale: locale)).", locale: locale)
    case .updated(_, let documents):
      String(kit: "Updated by \(list(documents, locale: locale)).", locale: locale)
    case .revisionStarted(_, let draft, let relation, let stage, let stream):
      String(
        kit: "\(RevisionsSummary.relationLabel(relation, locale: locale)) \(draft), \(RevisionsSummary.stagePhrase(stage, stream: stream, locale: locale)).",
        locale: locale)
    case .revisionQueued(_, let draft, let relation):
      String(
        kit: "\(RevisionsSummary.relationLabel(relation, locale: locale)) \(draft), in the RFC Editor queue.",
        locale: locale)
    case .errataListed:
      String(kit: "Now has errata.", locale: locale)
    }
  }

  /// "RFC 9997", "RFC 9997 and RFC 9998", "RFC 9996, RFC 9997, and RFC 9998".
  private static func list(_ documents: [DocumentID], locale: Locale) -> String {
    documents.map(\.displayName).formatted(.list(type: .and).locale(locale))
  }
```

Thread `locale` from `notices(for:index:locale:)` into `line`. Callers in the app keep the default.
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Commit** — "Notifications are whole sentences in the interface language (#751)".

### Task 7: The app target's AppKit and UIKit strings

**Files (modify):**
- `App/RFCReader/Window/ReaderToolbar.swift:129,228,235,249,261,273-274,281,287-288,356,360` and every other `label`/`paletteLabel`/`toolTip` in it
- `App/RFCReader/Views/Rendering/ReaderTextView.swift:358,365`
- `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+FigureMenu.swift`, `+Figures.swift`, `+CopyCode.swift`
- `App/RFCReader/Views/SidebarSearchField.swift:20`
- `App/RFCReader/Commands/DeveloperCommands.swift:32-36`
- `App/RFCReader/Model/AppData.swift:76`

- [ ] **Step 1: List them all**: `grep -rnE '(label|paletteLabel|toolTip|placeholderString|messageText|informativeText) = "|accessibilityDescription: "|NSMenuItem\(\s*title: "|UIAction\(\s*title: "|UIMenu\(\s*title: "|setActionName\("' App Packages/RFCReaderKit/Sources` — this is the regex Task 11 turns into the lint rule; after this task it must print nothing.
- [ ] **Step 2: Convert each** to `String(localized: "…")`, e.g. `item.label = String(localized: "Cite")`, `NSImage(systemSymbolName: "quote.opening", accessibilityDescription: String(localized: "Cite"))`, `alert.messageText = String(localized: "Installed Data Pack \(pack.manifest.version)")`. Where a key alone is ambiguous, add a comment: `String(localized: "Document", comment: "Toolbar item that shows the document's title")`.
- [ ] **Step 3: Verify**: the grep of Step 1 prints nothing; `make xcodeproj build-app` and `make ios-sim CODE_SIGNING_ALLOWED=NO` succeed.
- [ ] **Step 4: Commit** — "The app's AppKit and UIKit titles are looked up (#751)".

### Task 8: Keys that are not language

**Files:** whatever produces `%@`, `%@ %@`, `%@ %@ %@`, `%@: %@`, `%lld×` — find them with `xcrun xcstringstool print App/RFCReader/Localizable.xcstrings` (it shows each key's source) or `grep -rnE 'Text\("\\\(' App`; also `Intents/SectionEntity.swift:41`, `RegistryEntryEntity.swift:50`, `RFCEntity.swift:41`.

- [ ] **Step 1:** For a `Text("\(a) \(b)")`, write `Text(verbatim: "\(a) \(b)")`. For `DisplayRepresentation(title: "\(title)", subtitle: "\(documentName)")`, use `DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), subtitle: LocalizedStringResource(stringLiteral: documentName))` only if the compiler still records `%@`; otherwise leave it (an App Intents title interpolating data is a `%@` the system needs as a resource). For `"\(count)×"`, write `Text(count, format: .number) + Text(verbatim: "×")`.
- [ ] **Step 2:** `make strings`, then `python3 -c "import json;d=json.load(open('App/RFCReader/Localizable.xcstrings'));print([k for k,v in d['strings'].items() if not any(c.isalpha() for c in k.replace('%lld','').replace('%@','')) and v.get('extractionState')!='stale'])"` — Expected: `[]`, or only App Intents keys Step 1 had to keep. Delete keys marked `"extractionState" : "stale"` that `make strings` left behind: `xcrun xcstringstool sync` marks them stale but does not remove them; remove them with Python as in Task 5 Step 5 (`del d["strings"][key]`) — a stale key is a key the code no longer has, so this is the code's decision, not a hand edit. Run `make strings` again; no diff.
- [ ] **Step 3: Commit** — "Text that is not language is verbatim, not a key (#751)".

### Task 9: App Shortcuts' own catalog

**Files:**
- Create: `App/RFCReader/AppShortcuts.xcstrings`
- Modify: `Tools/strings/sync.py`, `project.yml` only if XcodeGen does not pick up the new file on its own

- [ ] **Step 1: Find where the phrases land.** `make strings`, then `grep -rl 'in \${applicationName}\|applicationName' $(find ~/Library/Developer/Xcode/DerivedData -path '*RFCReader.build/Debug/*' -name '*.stringsdata' | head -200) | head`, and print one: `plutil -p <file>` (or `python3 -c 'import json,sys;print(json.load(open(sys.argv[1])))'` if it is JSON). Expected: the phrases under a table named `AppShortcuts`.
- [ ] **Step 2: Create the empty catalog**:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

- [ ] **Step 3: Route by table in `sync.py`.** `xcstringstool sync` adds to a catalog only the strings of the table the catalog is named after, so adding `("App/RFCReader/AppShortcuts.xcstrings", "RFCReader", "App/RFCReader")` to `CATALOGS` may be enough. Try that first; if the phrases appear in `AppShortcuts.xcstrings` and not in `Localizable.xcstrings`, that is the whole change. If `Localizable.xcstrings` also gains them, pass `--table` (check `xcrun xcstringstool sync --help`) per catalog.
- [ ] **Step 4: Verify**: `make strings` twice — the phrases are in `AppShortcuts.xcstrings`, nowhere else, and the second run changes nothing. `make xcodeproj build-app` succeeds.
- [ ] **Step 5: Commit** — "App Shortcut phrases get their own catalog (#751)".

### Task 10: Verify #751 and hand it over

- [ ] **Step 1:** `make fmt && make check && make test-app && make xcodeproj build-app && make strings-check` — all pass.
- [ ] **Step 2: Pseudolanguage pass.** Launch with accented pseudo-localization: `open -n build/…/RFC\ Reader.app --args -AppleLanguages '(en)' -NSDoubleLocalizedStrings YES -NSAccentuateLocalizedStrings YES` (find the built app path from `make run`'s output). Read the menu bar, the toolbar, the sidebar and the inspector through the accessibility tree (memory: verify the Mac app with AppleScript / AX reads, no synthetic keystrokes). Every chrome string is accented and doubled; list any that is not and fix it in the task that owns it.
- [ ] **Step 3:** `/code-review` on `git diff string-catalogs...HEAD`; fix what holds up.
- [ ] **Step 4:** Rewrite the pull request body (Why / What / Verified / Not verified), push, `gh pr ready`.

---

# Pull request 2: #785 — the guard

### Task 11: The SwiftLint rule

**Files:**
- Modify: `.swiftlint.yml`

- [ ] **Step 0:** `gh stack`-free stacking: `git switch -c issue/785-raw-string-lint` from the top of #751's branch; empty signed commit "Start on #785"; push; `gh pr create --draft --base issue/751-localize-remaining-strings` with `Closes #785`; `gh issue edit 785 --add-label agent-pr`.
- [ ] **Step 1: Write the failing probe**:

```bash
cat > App/RFCReader/LintProbe.swift <<'EOF'
import AppKit

func probe(item: NSToolbarItem, menu: NSMenu) {
  item.label = "Cite"
  menu.addItem(NSMenuItem(title: "Print…", action: nil, keyEquivalent: ""))
}
EOF
swiftlint lint --strict App/RFCReader/LintProbe.swift; echo "exit $?"
```

Expected: exit 0 (nothing catches it yet).
- [ ] **Step 2: Add the rule** to `.swiftlint.yml`:

```yaml
custom_rules:
  # A string a user sees is looked up in a catalog (decision "The app's chrome is
  # localized, the reader body is not"). The compiler records a SwiftUI literal or a
  # LocalizedStringResource on its own; these AppKit and UIKit APIs take a plain
  # String, which it never records, so a literal here stays English in every language.
  localized_ui_string:
    name: Localized UI string
    included:
      - App/.*\.swift
      - Packages/RFCReaderKit/Sources/.*\.swift
    regex: '(?:NSMenuItem\(\s*title|UIAction\(\s*title|UIMenu\(\s*title|accessibilityDescription)\s*:\s*"|\.(?:label|paletteLabel|toolTip|placeholderString|messageText|informativeText)\s*=\s*"|setActionName\(\s*"'
    excluded_match_kinds:
      - comment
      - doccomment
    message: 'Look the string up: String(localized: "…") in the app, String(kit: "…", locale: locale) in RFCReaderKit.'
    severity: error
```

- [ ] **Step 3: Run the probe**: `swiftlint lint --strict App/RFCReader/LintProbe.swift; echo "exit $?"` — Expected: two `localized_ui_string` errors, exit ≠ 0. Then `rm App/RFCReader/LintProbe.swift`.
- [ ] **Step 4: Run on the tree**: `make lint` — Expected: clean (Task 7 converted everything). Any hit is a string Task 7 missed: convert it.
- [ ] **Step 5: Commit** — "Lint against plain strings passed to AppKit and UIKit titles (#785)".

### Task 12: The rule in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`, section "## Localization" (added by #752)

- [ ] **Step 1: Replace the section's bullets** with:

```markdown
**No text a user sees is a plain `String`.** It is a SwiftUI literal (`Text("…")`, `Button("…")`), a `LocalizedStringResource`, `String(localized: "…")` in the app target, or `String(kit: "…", locale: locale)` in RFCReaderKit — never a string literal handed to AppKit or UIKit, a model field, or a notification as it is. The `localized_ui_string` SwiftLint rule catches the common AppKit/UIKit cases; it cannot see a `String` passed through a function first, so this rule holds where the linter is blind.

- **The code is the source of the keys.** Add, change or remove a string in the Swift, run `make strings`, and commit the catalogs it changed. Never add or delete a key in an `.xcstrings` by hand; `make strings-check` fails in CI when a catalog and the code disagree.
- Translations, and English plural variants, are edited in the catalog (Xcode's editor or a script), never in the code.
- **RFCReaderKit's models resolve their own words** in a `locale: Locale = .interface` parameter, through `String(kit:locale:)`. Tests pass `locale: .english`, so they hold on a Mac whose first language is not English. Text that is data — a collection's name, a group's area, an RFC's title — stays as given beside the words.
- Interpolate a count, not a sentence fragment: `"\(count) RFCs"` becomes a `%lld` key with plural variants. A list goes through `.formatted(.list(type: .and).locale(locale))`. Never assemble a sentence from translated pieces or change a translated piece's case. Text that is not language, such as an identifier or `"\(a) \(b)"`, is `Text(verbatim:)`, so it never becomes a key.
- The reader body and its exports stay English: `DocumentTextBuilder`, `PDFExport`, `GrammarExport`, the requirements CSV, the VoiceOver descriptions of figures. So do RFCKit's designations (statuses, streams, series); RFCKit has no catalog.
- Look a string up with `grep` on the catalog, or `xcrun xcstringstool print`.
```

(Keep the section's opening paragraph from #752 above it.)
- [ ] **Step 2: Commit** — "CLAUDE.md: no text a user sees is a plain String (#785)".
- [ ] **Step 3: Verify and hand over**: `make check`; `/code-review` on `git diff issue/751-localize-remaining-strings...HEAD`; body; push; `gh pr ready`.

---

# Pull request 3: #786 — German

### Task 13: The completeness check

**Files:**
- Modify: `Tools/strings/sync.py`, `Makefile` (`strings-check`)

- [ ] **Step 0:** Branch `issue/786-german` from the top of #785's branch; empty signed commit; push; draft pull request `--base issue/785-raw-string-lint`, `Closes #786`; `agent-pr` on #786.
- [ ] **Step 1: Add the check to `sync.py`.** The catalogs move to a list the check also reads (`CATALOG_PATHS = [c[0] for c in CATALOGS]`, plus `App/RFCReader/AppShortcuts.xcstrings` if Task 9 routed it separately). Add:

```python
def untranslated(catalog: Path, language: str) -> list[str]:
    """Keys of `catalog` that have no `language` translation in state translated."""
    strings = json.loads(catalog.read_text())["strings"]
    missing = []
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        localization = entry.get("localizations", {}).get(language)
        if localization is None or not all(
            unit.get("state") == "translated" for unit in string_units(localization)
        ):
            missing.append(key)
    return missing


def string_units(localization: dict) -> list[dict]:
    """A localization's string units: its own, or every variant's."""
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    units = []
    for variants in localization.get("variations", {}).values():
        for variant in variants.values():
            units += string_units(variant)
    return units
```

and in `main`, a mutually exclusive mode: `parser.add_argument("--check-translations", metavar="LANGUAGE")`; `--objroot` becomes required only without it. In check mode, print `catalog: key` for each missing key and `raise SystemExit(1)` if any; otherwise sync as before. Add `import json`; update the module docstring's usage lines.
- [ ] **Step 2: Wire it into the Makefile's `strings-check`**, after the diff:

```make
strings-check: strings
	@git diff --exit-code -- '*.xcstrings' || \
	  { echo "The string catalogs are out of date: run make strings and commit them." >&2; exit 1; }
	@Tools/strings/sync.py --check-translations de
```

- [ ] **Step 3: Watch it fail**: `Tools/strings/sync.py --check-translations de; echo "exit $?"` — Expected: every key listed, exit 1 (no German yet).
- [ ] **Step 4: Add the rule to CLAUDE.md's Localization section**, after the "code is the source of the keys" bullet:

```markdown
- **Every key ships translated.** A new key gets its German translation in the same change, in state `translated`; `make strings-check` fails on a key without one, naming it.
```

- [ ] **Step 5: Commit** — "make strings-check fails on a key without German (#786)".

### Task 14: German translations

**Files:**
- Modify: `App/RFCReader/Localizable.xcstrings`, `Packages/RFCReaderKit/Sources/RFCReaderKit/Resources/Localizable.xcstrings`, `App/RFCReader/AppShortcuts.xcstrings`

- [ ] **Step 1: Export the keys to translate**, with comments and English values, to the scratchpad: `Tools/strings/sync.py --check-translations de > $SCRATCH/keys.txt`, and for each catalog `xcrun xcstringstool print <catalog>` for context.
- [ ] **Step 2: Draft the German** into `$SCRATCH/de.json`, one object per catalog path, mapping key → string, or key → `{"one": "…", "other": "…"}` for a plural key. Terminology:
  - Apple's German: Collection → Sammlung, Bookmark → Lesezeichen, Share → Teilen, Settings → Einstellungen, Search → Suchen, Print… → Drucken …, Export… → Exportieren …, Copy → Kopieren, Back → Zurück.
  - IETF terms stay English: RFC, Errata, Datatracker, Working Group, Internet-Draft, BCP, STD, FYI, IESG, IETF Last Call, BoF; the statuses are RFCKit's and not in the catalogs.
  - Placeholders keep their order and type (`%@`, `%lld`); positional `%1$@` only where German reorders.
  - Ellipsis `…` and typographic quotes „…" as Apple's German uses them.
  - "Obsoleted by %@." → "Ersetzt durch %@."; "Updated by %@." → "Aktualisiert durch %@."; "Original Text" → "Originaltext"; "Open on rfc-editor.org" → "Auf rfc-editor.org öffnen"; "Remove from Collection" → "Aus Sammlung entfernen" (Task 16's test depends on these).
- [ ] **Step 3: Apply them**:

```bash
python3 - "$SCRATCH/de.json" <<'EOF'
import json, sys
def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}
for path, translations in json.load(open(sys.argv[1])).items():
    d = json.load(open(path))
    for key, value in translations.items():
        localization = (
            {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
            if isinstance(value, dict) else unit(value))
        d["strings"][key].setdefault("localizations", {})["de"] = localization
    json.dump(d, open(path, "w"), indent=2, ensure_ascii=False, separators=(",", " : "))
EOF
make strings
```

- [ ] **Step 4: Check**: `Tools/strings/sync.py --check-translations de; echo "exit $?"` — Expected: exit 0. `git diff --stat` shows only the three catalogs.
- [ ] **Step 5: Commit** — "German, every key translated (#786)". The pull request body will ask the maintainer to review the strings.

### Task 15: The check catches a forgotten translation

- [ ] **Step 1:** Temporarily add `let _ = String(localized: "Probe without German")` to any app file; `make strings-check; echo "exit $?"` — Expected: fails, naming `Probe without German`. Revert the line; `make strings` again; `git status` clean.

### Task 16: Proof the German is found at run time

**Files:**
- Modify: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/LocalizationTests.swift`

- [ ] **Step 1: Write the tests**:

```swift
  @Test func `RFCReaderKit finds its German catalog`() {
    #expect(String(kit: "Remove from Collection", locale: .german) == "Aus Sammlung entfernen")
    let more = DocumentMenus.more(showsOriginal: false, errata: nil, precedingDraft: nil, locale: .german)
    #expect(more.map { $0.map(\.title) } == [["Originaltext"], ["Auf rfc-editor.org öffnen", "Datatracker"]])
  }

  @Test func `a German notice lists its RFCs in German`() {
    let notice = BookmarkNotice.notices(
      for: [.obsoleted(.rfc(9990), [.rfc(9991), .rfc(9992)])], index: nil, locale: .german
    ).first
    #expect(notice?.body == "Ersetzt durch RFC 9991 und RFC 9992.")
  }

  @Test func `a collection's name is never translated`() {
    let snapshot = CollectionSnapshot(collections: [.init(name: "Errata")], memberships: [:])
    let items = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .german)
    #expect(items[0].map(\.title) == ["Errata"])
  }

  @Test func `one RFC is counted in the singular in German`() {
    #expect(String(kit: "\(1) RFCs", locale: .german) == "1 RFC")
    #expect(String(kit: "\(3) RFCs", locale: .german) == "3 RFCs")
  }
```

(Adapt `BookmarkEvent`'s case construction and `CollectionSnapshot`'s initializer to their real signatures, as their existing tests do.)
- [ ] **Step 2: Run**: `swift test --package-path Packages/RFCReaderKit --filter LocalizationTests` — Expected: PASS. If the first test fails with the English text, SwiftPM did not compile the German into the module bundle: check `ls Packages/RFCReaderKit/.build/*/debug/RFCReaderKit_RFCReaderKit.bundle*` for a `de.lproj`.
- [ ] **Step 3: Commit** — "Prove RFCReaderKit's German is found at run time (#786)".

### Task 17: Verify German in the app and hand over

- [ ] **Step 1:** `make fmt && make check && make test-app && make xcodeproj build-app && make strings-check` — all pass.
- [ ] **Step 2: macOS**: launch the built app with `--args -AppleLanguages '(de)'`; read the menu bar, toolbar (labels and menus), sidebar, inspector and settings through the accessibility tree; screenshot each with `screencapture -l <windowid>`. Any English that is not an IETF term or data is a bug to fix in the task that owns it.
- [ ] **Step 3: iOS**: `xcrun simctl boot` the simulator, `xcrun simctl spawn booted defaults write -g AppleLanguages '("de")'`, `make run-sim CODE_SIGNING_ALLOWED=NO`, `xcrun simctl io booted screenshot de.png`; look at it.
- [ ] **Step 4: Not verifiable here, say so in the body**: App Shortcut phrases as Siri hears them; a notification's text when one fires.
- [ ] **Step 5:** `/code-review` on `git diff issue/785-raw-string-lint...HEAD`; fix what holds up. Body (Why / What / Verified / Not verified / "please review the German strings"); push; `gh pr ready`.
