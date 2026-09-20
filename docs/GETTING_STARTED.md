# Getting started

You need a Mac with Xcode 26 or newer (the app targets iOS 26 and macOS 26). The Swift package alone builds with any Swift 6 toolchain, including on Linux.

## 1. Run the core package tests first

```sh
swift test --package-path Packages/RFCKit
```

Forty-plus tests should pass in well under a second. This is the fast loop: parsers, search, citations and link handling are all here and need no simulator.

## 2. Create the Xcode project

### Option A: XcodeGen (recommended, reproducible)

```sh
brew install xcodegen
xcodegen generate
open RFCReader.xcodeproj
```

Before generating, edit `project.yml`: set `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` to your own reverse-DNS names and uncomment `DEVELOPMENT_TEAM` with your team ID (Xcode ▸ Settings ▸ Accounts shows it). The generated `.xcodeproj`, `Info.plist` and entitlements file are git-ignored; `project.yml` is the source of truth. If you would rather commit a hand-maintained project, delete those three lines from `.gitignore`.

### Option B: by hand in Xcode

1. File ▸ New ▸ Project ▸ **Multiplatform ▸ App**. Product name `RFCReader`, interface SwiftUI, storage SwiftData, language Swift. Save it in the repository root.
2. Delete the generated `ContentView.swift`, `RFCReaderApp.swift` and `Item.swift`, then drag the `App/RFCReader` folder into the target (choose "Create folder references" or "Create groups", either works).
3. File ▸ Add Package Dependencies ▸ **Add Local…** ▸ pick `Packages/RFCKit` ▸ add the `RFCKit` library to the `RFCReader` target.
4. Target ▸ Info ▸ URL Types: add a type with scheme `rfc`.
5. Target ▸ Signing & Capabilities: App Sandbox with **Outgoing Connections (Client)** for macOS.
6. Build and run. The first launch downloads the 14 MB index; give it a few seconds.

## 3. Bundle an index snapshot (optional, recommended before shipping)

```sh
curl -o App/RFCReader/rfc-index.xml https://www.rfc-editor.org/rfc-index.xml
```

Add the file to the target's resources. `DocumentStore` picks it up when no downloaded index exists, so first launch works offline and the download becomes a background refresh.

## 4. Things to try once it runs

- Press ⌘L, type `9110`, press Return.
- In RFC 9110 tap any `[RFC7231]`; note the red "Obsoleted by RFC 9110" banner on the old document, and tap it to come back.
- Open RFC 1149 (text only) and toggle *Original Text* from the ⋯ menu to compare the reflowed rendering with the file as published.
- Search `wg:httpbis status:current cache`.
- From Terminal: `open "rfc://9110/section/9.3.1"`.
- Ask Siri "Open RFC 9000 in RFC Reader" (App Shortcuts need one launch to register).

## 5. Where to go next

`docs/VISION.md` has the feature tiers; `docs/ARCHITECTURE.md` explains the model the UI renders and the known gaps. Good first tasks, roughly in order of payoff:

1. Typography pass on `DocumentView` and `BlockView` (fonts, measure, spacing, dark mode).
2. Reference peek popover on cross-reference links.
3. Definition-list detection in `LegacyTextParser` (add a fixture that exercises it and a test first).
4. Spotlight indexing of the index in `LibraryModel.apply`.
5. iCloud sync: add the iCloud capability and a CloudKit container; SwiftData does the rest.

## Running the corpus pipeline

```sh
swift build -c release --package-path Tools/corpus-build
Tools/corpus-build/.build/release/corpus-build fetch --out corpus --limit 20
Tools/corpus-build/.build/release/corpus-build convert --in corpus/text --out corpus/xml --report corpus/report.json
Tools/corpus-build/.build/release/corpus-build manifest --dir corpus/xml --out corpus/manifest.json --version dev
```

Drop `--limit` for the full 8,464 legacy RFCs (about 450 MB, twenty minutes at the default concurrency). `docs/DATA_PIPELINE.md` explains the packs this produces.

## Working on RFCKit from Linux or CI

The package has no Apple dependencies. `Foundation`, `FoundationXML` and `FoundationNetworking` are imported conditionally, and the tests run in a `swift:6.1` container (see `.github/workflows/ci.yml`).
