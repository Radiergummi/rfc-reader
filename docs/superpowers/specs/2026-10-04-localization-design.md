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

### RFCReaderKit's models resolve in a locale they are given

RFCReaderKit's models keep their `String` fields. A model that has words in it takes a `locale: Locale = .interface` and resolves them through one helper:

```swift
extension String {
  /// `key` from RFCReaderKit's catalog, in `locale`'s language.
  init(kit key: String.LocalizationValue, locale: Locale) {
    var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    resource.locale = locale
    self.init(localized: resource)
  }
}
```

That covers `DocumentMenus` (its item titles), `Glossary`, `DocumentInfo`, `WorkingGroupSummary` (type and state names, link titles, the publications line), `RevisionsSummary` and `BookmarkNotice`. Text that is data stays as given beside the words: a collection's name, a group's area from datatracker, a citation style's name.

A resource's `locale` decides which language the lookup returns (measured: `de` resolves the German, `en` the English, whatever the process prefers). So tests pass `Locale(identifier: "en")` and keep their English expectations on a Mac whose first language is German, and a test can resolve German on purpose.

Considered and dropped: models holding `LocalizedStringResource` for the renderer to resolve. They mix words with data — a menu item's title is a collection's name or a word — so every such field would need a type for "a word or text as given", where the locale parameter needs nothing. Resolving with no pinned locale was dropped too: on a Mac whose first language is German, the English assertions fail.

`Locale.interface` is the language RFCReaderKit's catalog resolves to for this process (`Bundle.module.preferredLocalizations.first`), not `Locale.current`: a reader whose languages are French then German gets German, which the catalog has, where `Locale.current` would ask for French and fall back to English. List and date formatting inside a model use the same locale, so a German sentence never gets an English "and".

Whether the compiler records a key passed to the helper's `String.LocalizationValue` parameter is checked first; if it does not, the helper takes a `LocalizedStringResource` built at the call site instead.

### Notifications

`BookmarkNotice.body` is built in the locale it is given, like the models above. Its sentences stop being assembled from fragments:

- "Obsoleted by %@." and "Updated by %@." take a list formatted with `.formatted(.list(type: .and))`, replacing the hand-written `", "` / `" and "` join.
- The revision lines become one whole format per relation and stage, instead of a label, a draft name and a stage name with its first letter lowercased (which is wrong for a German noun).

### Undo names

`CollectionStore`'s `setActionName("Remove from Collection")` becomes `setActionName(String(kit: "Remove from Collection", locale: .current))`.

### Keys that are not language

`%@`, `%@ %@`, `%@ %@ %@`, `%@: %@` and `%lld×` come from `Text("\(a) \(b)")` and its kind. They become `Text(verbatim:)`, or a format whose words are in the key; `%lld×` becomes the number formatted and a verbatim `×`. `make strings` then drops them from the catalog.

### App Shortcuts

The `phrases:` of `RFCReaderShortcuts` (`Intents/OpenRFCIntent.swift`) are localized through `App/RFCReader/AppShortcuts.xcstrings`, not `Localizable.xcstrings`. Whether the compiler's `.stringsdata` already records them under an `AppShortcuts` table is checked first; `Tools/strings/sync.py` syncs that table into the new catalog, routing by table name if it is there and by source file if not.

### Stays English

- `PDFExport` (the outline's "Abstract"), `GrammarExport` and the requirements CSV are exports of the body.
- `PacketSummary` and `AccessibleReading` describe the body's figures to VoiceOver, and the body is English.
- RFCKit's designations — statuses ("Proposed Standard"), streams, series — are the IETF's own terms, and RFCKit stays without a catalog. The two places it has interface words, `CitationStyle.displayName` and the month names of `PublicationDate.formatted`, get localized counterparts in RFCReaderKit (`CitationStyle.title(in:)`, `PublicationDate.formatted(in:)`), which the chrome uses instead.

### Tests

Suites that assert English (`DocumentMenusTests`, `WorkingGroupSummaryTests`, `BookmarkEventsTests`, `DocumentInfoTests`, `SpotlightEntryTests`, and any other the change reaches) pass `locale: Locale(identifier: "en")`.

## 2. The guard (#785)

A `custom_rules` entry in `.swiftlint.yml`, `localized_ui_string`, scoped to `App/` and `Packages/RFCReaderKit/Sources`, whose regex matches a string literal passed to the APIs this codebase uses that take a plain `String`:

- `NSMenuItem(title: "`, `UIAction(title: "`, `UIMenu(title: "`
- `.label = "`, `.paletteLabel = "`, `.toolTip = "`
- `accessibilityDescription: "`
- `setActionName("`

Its message names the fix: `String(localized:)` in the app, `String(kit:locale:)` in RFCReaderKit. It runs under `make lint --strict` and in CI. It does not catch a plain `String` passed through a function first; RFCReaderKit's models resolving their own words cover the main such path.

CLAUDE.md's Localization section leads with the rule: no text a user sees is a plain `String`; it is a SwiftUI literal, a `LocalizedStringResource`, `String(localized:)`, or in RFCReaderKit `String(kit:locale:)`, its key reaches the catalog through `make strings`, and it gets its German translation in the same change.

## 3. German (#786)

- `de` in both `Localizable.xcstrings` and in `AppShortcuts.xcstrings`, every key translated, state `translated`; keys with `%lld` get German plural variants (`one`, `other`).
- Terminology: Apple's German for the platform's words (Sammlung, Lesezeichen, Teilen, Einstellungen); IETF terms stay English (RFC, Errata, Datatracker, Working Group, Internet-Draft).
- Translations are drafted in the pull request and reviewed there; later edits are made in Xcode's catalog editor. Keys still come only from the code.
- **Completeness check**: `Tools/strings/sync.py --check-translations de`, run by `make strings-check` after its diff, fails naming every key not marked `shouldTranslate: false` that lacks a `de` string unit in state `translated`, or a plural variant of one. Standard library only, reading the JSON.
- **Proof test**: an RFCReaderKit test builds a few models with `locale: Locale(identifier: "de")` and expects the German text, failing if `bundle: .module` stops finding the catalog.

## Verification

- `make fmt`, `make check`, `make test-app`, `make xcodeproj build-app`, `make strings-check` on each pull request.
- #751: one run under the accented pseudolanguage, looking for English left in the chrome, through the accessibility tree.
- #786: `make run` with `-AppleLanguages '(de)'`, and `make run-sim`, menus, toolbar, inspector and settings read through the accessibility tree; a screenshot of each in the pull request.
- What could not be checked (an App Shortcut phrase as Siri hears it, a notification's text when one fires) is said so in the pull request.
