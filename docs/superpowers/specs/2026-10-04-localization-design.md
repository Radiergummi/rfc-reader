# Localizing the chrome, and German

*October 2026. Issues #751, #785, #786; built on the string catalogs of #752.*

## Goal

Every text a user sees outside the reader body is in a string catalog, nothing lets a new plain `String` slip past that, and the app ships in German as the proof that the pipeline works end to end. The reader body and its exports stay English (decision "The app's chrome is localized, the reader body is not").

German is a shipping localization: once it merges, every new string needs a German translation, and the build check fails without one.

## Shape

Three pull requests, stacked on #752 (`string-catalogs`), bottom first:

1. **#751** — every user-visible string is in a catalog.
2. **#785** — a SwiftLint rule against raw strings, and the rule in CLAUDE.md. Needs 1: on the code before it, the rule flags every call it fixes.
3. **#786** — German, every key translated, and a completeness check.

## 1. Everything in a catalog (#751)

### The app target

A plain `String` shown to the user becomes `String(localized: "…")`: the toolbar (`Window/ReaderToolbar.swift`: item labels, palette labels, `accessibilityDescription`), `InfoView.swift`, the figure menus (`RFCTextViewCoordinator+FigureMenu.swift`, `+Figures.swift`, `+CopyCode.swift`), `ReaderTextView.swift`, `DeveloperCommands.swift`, and the `String` fields of the App Intents and their entities. A `comment:` is added only where the key alone is ambiguous.

### RFCReaderKit's models carry `LocalizedStringResource`

Text that RFCReaderKit hands to a renderer becomes `LocalizedStringResource("…", bundle: .module)` rather than a resolved `String`:

- `DocumentMenus.Item.title`, the names in `Glossary` and `DocumentInfo`;
- `WorkingGroupSummary`'s kind, area and state names, and its link titles;
- `RevisionsSummary`'s labels.

The renderers resolve them where they show them: SwiftUI with `Text(resource)` (`MenuSections`), AppKit and UIKit with `String(localized: resource)`.

Why not resolve to `String` when the model is built: which language a lookup returns follows the preferred languages of the process, so on a Mac set to German the tests' English expectations would fail, and no test could deliberately check German. A resource can be resolved in a pinned language.

`LocalizedStringResource` is `Equatable` and `Codable` but not `Hashable`, so `Item` keeps its `Hashable` conformance with a `hash(into:)` over the resource's key; equality stays synthesized.

### Notifications

`UNMutableNotificationContent` takes a `String`, so `BookmarkNotice.body` stays a `String`, built from resources in the current language. Its sentences stop being assembled from fragments:

- "Obsoleted by %@." and "Updated by %@." take a list formatted with `.formatted(.list(type: .and))`, replacing the hand-written `", "` / `" and "` join.
- The revision lines become one whole format per relation and stage, instead of a label, a draft name and a stage name with its first letter lowercased (which is wrong for a German noun).

### Undo names

`CollectionStore`'s `setActionName("Remove from Collection")` becomes `setActionName(String(localized: "Remove from Collection", bundle: .module))`.

### Keys that are not language

`%@`, `%@ %@`, `%@ %@ %@`, `%@: %@` and `%lld×` come from `Text("\(a) \(b)")` and its kind. They become `Text(verbatim:)`, or a format whose words are in the key; `%lld×` becomes the number formatted and a verbatim `×`. `make strings` then drops them from the catalog.

### App Shortcuts

The `phrases:` of `RFCReaderShortcuts` (`Intents/OpenRFCIntent.swift`) are localized through `App/RFCReader/AppShortcuts.xcstrings`, not `Localizable.xcstrings`. Whether the compiler's `.stringsdata` already records them under an `AppShortcuts` table is checked first; `Tools/strings/sync.py` syncs that table into the new catalog, routing by table name if it is there and by source file if not.

### Stays English

`PDFExport` (the outline's "Abstract") and `GrammarExport` are exports of the body.

### Tests

Suites that assert English titles (`DocumentMenusTests`, `WorkingGroupSummaryTests`, `BookmarkEventsTests`, `DocumentInfoTests`, `SpotlightEntryTests`, and any other the change reaches) compare resolved English through a test helper that sets `resource.locale` to English before resolving. The notice builder takes the locale to resolve in, defaulting to the current one, so its tests pin English.

## 2. The guard (#785)

A `custom_rules` entry in `.swiftlint.yml`, `localized_ui_string`, scoped to `App/` and `Packages/RFCReaderKit/Sources`, whose regex matches a string literal passed to the APIs this codebase uses that take a plain `String`:

- `NSMenuItem(title: "`, `UIAction(title: "`, `UIMenu(title: "`
- `.label = "`, `.paletteLabel = "`, `.toolTip = "`
- `accessibilityDescription: "`
- `setActionName("`

Its message names the fix, `String(localized:)`, with `bundle: .module` in RFCReaderKit. It runs under `make lint --strict` and in CI. It does not catch a plain `String` passed through a function first; RFCReaderKit's models carrying resources covers the main such path.

CLAUDE.md's Localization section leads with the rule: no text a user sees is a plain `String`; it is a SwiftUI literal, a `LocalizedStringResource` or `String(localized:)`, its key reaches the catalog through `make strings`, and it gets its German translation in the same change.

## 3. German (#786)

- `de` in both `Localizable.xcstrings` and in `AppShortcuts.xcstrings`, every key translated, state `translated`; keys with `%lld` get German plural variants (`one`, `other`).
- Terminology: Apple's German for the platform's words (Sammlung, Lesezeichen, Teilen, Einstellungen); IETF terms stay English (RFC, Errata, Datatracker, Working Group, Internet-Draft).
- Translations are drafted in the pull request and reviewed there; later edits are made in Xcode's catalog editor. Keys still come only from the code.
- **Completeness check**: `Tools/strings/sync.py --check-translations de`, run by `make strings-check` after its diff, fails naming every key not marked `shouldTranslate: false` that lacks a `de` string unit in state `translated`, or a plural variant of one. Standard library only, reading the JSON.
- **Proof test**: an RFCReaderKit test resolves a few resources with the locale German and expects the German text, failing if `bundle: .module` stops finding the catalog.

## Verification

- `make fmt`, `make check`, `make test-app`, `make xcodeproj build-app`, `make strings-check` on each pull request.
- #751: one run under the accented pseudolanguage, looking for English left in the chrome, through the accessibility tree.
- #786: `make run` with `-AppleLanguages '(de)'`, and `make run-sim`, menus, toolbar, inspector and settings read through the accessibility tree; a screenshot of each in the pull request.
- What could not be checked (an App Shortcut phrase as Siri hears it, a notification's text when one fires) is said so in the pull request.
