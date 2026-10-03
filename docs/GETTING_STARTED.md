# Getting started

You need a Mac with Xcode 26.4 or newer (the app targets iOS 26 and macOS 26), [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the project (`make xcodegen-install` puts the pinned release, 2.46.0, in `.build/xcodegen`, which is what CI uses; Homebrew's works too, and `make xcodeproj` warns when it is another version) and [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`; swift-format comes with the toolchain. RFCKit alone builds with any Swift 6.3 toolchain, including on Linux.

```sh
brew install xcodegen swiftlint
make check      # lint, build and test the three Swift packages: the gate before committing
make run        # generate the Xcode project, build the macOS app and launch it
```

Everything goes through the `Makefile`; `CLAUDE.md` has the table of its targets — the app-side test suite (`make test-app`), the iOS builds, formatting, and the corpus pipeline. `RFCReader.xcodeproj` is generated from `project.yml` (`make xcodeproj`) and is not committed: edit `project.yml`, never the project.

`project.yml` signs with the maintainer's team, so outside it `make run` fails at signing. Either set `bundleIdPrefix`, `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` there to your own, or build unsigned, as CI does: `make run CODE_SIGNING_ALLOWED=NO`.

The first launch downloads the 14 MB RFC index. An `rfc-index.xml` added to the app's resources is used until the download lands, so a build that bundles one works offline from the start:

```sh
curl -o App/RFCReader/rfc-index.xml https://www.rfc-editor.org/rfc-index.xml
```

## Things to try once it runs

- Press ⌘L, type `9110`, press Return.
- In RFC 9110 click any `[RFC7231]`; note the "Obsoleted by RFC 9110" banner on the old document, and click it to come back.
- Open RFC 1149 (text only) and choose *Original Text* from the ⋯ menu to compare the reflowed rendering with the file as published.
- Search `wg:httpbis status:current cache`.
- From Terminal: `open "rfc://9110#section-9.3.1"`. The same link in a code comment is one an editor can open; see "Links from code" in the [README](../README.md#links-from-code).
- Select `RFC 9110 §8.3` in any app and choose *Services ▸ Replace with RFC Link*.
- Ask Siri "Open an RFC in RFC Reader"; it asks which number. (App Shortcuts need one launch to register. Siri cannot hear the number in the phrase itself until there is an `RFCEntity`, #192.)

## Where to go next

`docs/VISION.md` has the feature tiers and the principles the UI is held to; `docs/ARCHITECTURE.md` describes the document model, the two parsers and the reader, and `docs/decisions/` has the dated decisions behind them; `docs/DATA_PIPELINE.md` covers the corpus packs. `CLAUDE.md` lists the standing constraints that are easy to break by accident, and how to work on the legacy text heuristics. Work in progress is tracked in the GitHub issues.

## The corpus pipeline

`make corpus` fetches, converts and writes the manifest for 20 legacy and 20 RFCXML documents; `make corpus CORPUS_LIMIT=` does all of them (about 450 MB, twenty minutes). `docs/DATA_PIPELINE.md` explains the stages and the packs they produce.

## Working on RFCKit from Linux or CI

The package has no Apple dependencies. `Foundation`, `FoundationXML` and `FoundationNetworking` are imported conditionally, and the tests run in a `swift:6.3` container (see `.github/workflows/ci.yml`).
