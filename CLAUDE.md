# CLAUDE.md

## Commands

- `make check` is the gate before committing. Corpus-backed tests are not in it: run `make test-corpus` for those.
- One test: `swift test --package-path Packages/RFCKit -Xswiftc -warnings-as-errors --filter "<phrase from its name>"`. Keep the flag, or switching with `make test` rebuilds everything.
- Without signing certificates, pass `CODE_SIGNING_ALLOWED=NO` to the app builds, as CI does.
- `RFCReader.xcodeproj`, and the Info.plist and entitlements files, are generated from `project.yml` and gitignored. Edit `project.yml`.

## Invariants that are on purpose

Read `docs/ARCHITECTURE.md` (above all "TextKit 2 traps") and the records in `docs/decisions/` before changing the document model or the reader.

- RFCKit is tested on Linux in CI: no SwiftUI or Apple-only API, and `FoundationXML`/`FoundationNetworking` only behind `#if canImport(…)`. A Mac build will not catch this.
- The App target has no test bundle. Anything that is a pure function of its inputs goes in `RFCReaderKit`; the App target keeps only UIKit/AppKit object wiring and drawing.
- The reader body is one `NSTextContentStorage` per document. New block kinds go in `DocumentTextBuilder`, never as hosted SwiftUI views.
- The column width is computed by `DocumentView` with `ReaderLayout`. Do not add a callback from the text view that reports it: that made every document build twice.
- `DocumentTextBuilder` is not main-actor bound. Paragraph styles in a build must be immutable copies: Foundation shares equal attribute dictionaries across builds.
- On macOS, a TextKit 2 text view needs a `dismantleNSView` that sets `textContainer?.textView = nil`, or AppKit keeps the whole document alive.
- On macOS the windows are AppKit's (`ReaderWindowController`), not a `WindowGroup`. Every `NSHostingController` must be handed `LibraryModel`, `NavigationModel`, `ReaderState` and the SwiftData container explicitly: an `@Environment` lookup there crashes at run time with no compile warning. `@FocusedValue` does not work there either; menu commands go through `ActiveReaderWindow`.
- `safeAreaRegions = []` on the reader's hosted root and `ReaderScrollView` refusing the trailing inset are both needed; removing either re-wraps the document when the contents panel opens.
- Anchors are stable strings, never indices: deep links, the table of contents and reading positions key off them.
- Both XML parsers ignore a parser error reported after the root element closes (a swift-corelibs-foundation quirk). A test pins it; it is not a bug.
- A comment that cites a cost names the benchmark or signpost that measures it, not the number (#607).

## Tests and RFC text

- **Never commit RFC text**: no new fixtures, no excerpts or trimmed copies of committed ones, no override snapshots. Licensing is open with the IETF Trust. A test may locate text with a few words (a rule name, a term), never a sentence. Anything else is fetched into the gitignored `corpus/` at run time.
- A test that calls `parse` feeds it a real RFC: a fixture already committed in `Packages/RFCKit/Tests/RFCKitTests/Fixtures/` (through `Fixtures`) or a corpus document (through `CorpusText`). Only a guard-level test of a pure function may take hand-written lines, written in RFC shape, not quoted.
- `LegacyTextParser` changes risk regressions across 8,457 documents. Write the test first: guard-level, then committed fixture, then a `Corpus-backed: <topic>` suite. A new corpus document goes in the Makefile's `CORPUS_TEST_DOCUMENTS` (or `CORPUS_TEST_XML_DOCUMENTS`).
- Fix the heuristic when a class of documents is wrong. When exactly one is, patch it in `corpus/overrides/rfcNNNN.xml` (rules in its README). For a wide change, run `make corpus CORPUS_LIMIT=` and compare `corpus/report.json` with the previous run.

## Localization

- The code is the source of the keys: change the string in Swift, run `make strings`, and commit the catalogs. Never add or remove a key in a `.xcstrings` by hand. Every new key needs its German translation, state `translated`, in the same change.
- In RFCReaderKit, models take `locale: Locale = .interface` and use `String(kit:locale:)`; tests pass `locale: .english`.
- The reader body and its exports stay English (`DocumentTextBuilder`, `PDFExport`, `GrammarExport`, the requirements CSV, figure descriptions), as do RFCKit's designations and script-facing names.
- The `localized_ui_string` lint rule misses `"""` literals, literals behind `?:` or `??`, and strings passed through a function. Check those by hand.
- `App/RFCReader/InfoPlist.xcstrings` is the exception: no build extracts Info.plist, so a new user-facing value in `project.yml`'s `info:` gets its key and English there by hand.
