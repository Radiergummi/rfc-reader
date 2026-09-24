.PHONY: lint fmt build test check test-app xcodeproj build-app build-ios run install corpus corpus-tool corpus-fetch corpus-convert corpus-manifest

# The two Swift packages. RFCKit holds everything the app and the pipeline share
# -- parsers, index, search, citations -- and builds anywhere a Swift 6 toolchain
# does, including Linux. corpus-build is the offline pipeline that turns the
# legacy plain-text RFCs into RFCXML packs (docs/DATA_PIPELINE.md).
RFCKIT       := Packages/RFCKit
RFCREADERKIT := Packages/RFCReaderKit
CORPUS_BUILD := Tools/corpus-build
CORPUS_BIN   := $(CORPUS_BUILD)/.build/release/corpus-build

PROJECT := RFCReader.xcodeproj
SCHEME  := RFCReader

## Lint all Swift sources
# --strict because .swiftlint.yml is tuned to the tree as it stands: every rule
# left enabled holds today, so a warning is something this change introduced
# rather than backlog to scroll past.
lint:
	swiftlint lint --strict

## Apply SwiftLint's autocorrections in place
fmt:
	swiftlint --fix

## Build the Swift packages
build:
	swift build --package-path $(RFCKIT)
	swift build --package-path $(CORPUS_BUILD)

## Run the RFCKit test suite
# The fast loop: no simulator, no Xcode project, well under a second.
test:
	swift test --package-path $(RFCKIT)

## Run all checks (lint + packages + tests)
# Deliberately without build-app: that one needs Xcode and a Mac, while
# everything here runs in the swift:6.1 container CI uses.
check: lint build test

## Run the app-side test suite (RFCReaderKit)
# Not part of `check`: this package imports UIKit/AppKit, so it needs an Apple
# SDK and cannot run in the swift:6.1 container the Linux job uses.
test-app:
	swift test --package-path $(RFCREADERKIT)

## Generate the Xcode project from project.yml
# Phony: XcodeGen's `sources:` entries are folder-based, so a source file added
# or removed under App/RFCReader has to be picked up even when project.yml
# itself is unchanged. A timestamp rule on project.yml alone missed that and
# left build-app failing with a confusing "cannot find X in scope". xcodegen
# runs in about a second, so regenerating unconditionally costs nothing next
# to the xcodebuild it precedes.
xcodeproj:
	xcodegen generate

# project.yml ships without a DEVELOPMENT_TEAM, and xcodebuild refuses to sign
# without one. Compiling is what the two app targets are for, so signing is off
# unless a team is passed:
#
#   make build-app DEVELOPMENT_TEAM=ABCDE12345
#
DEVELOPMENT_TEAM ?=
SIGNING := $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),CODE_SIGNING_ALLOWED=NO)

# Debug for everything but `install`, which puts a Release build in /Applications.
CONFIGURATION ?= Debug

# Where xcodebuild left RFCReader.app. Asked for rather than spelled out: the
# DerivedData directory carries a hash of the project's own path, so it differs
# per checkout. Recursively expanded (`=`, not `:=`) so only the targets that
# need it pay for the xcodebuild call.
app_path = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -configuration $(CONFIGURATION) -showBuildSettings 2>/dev/null \
	  | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)/$(SCHEME).app

## Build the app for macOS
build-app: xcodeproj
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -configuration $(CONFIGURATION) -quiet $(SIGNING)

## Build the app for the iOS Simulator
build-ios: xcodeproj
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS Simulator' -configuration $(CONFIGURATION) -quiet $(SIGNING)

## Build and launch the macOS app
# Unsigned is enough to run locally: the linker ad-hoc signs the bundle, which
# satisfies the sandbox entitlements on this machine. A running copy is quit
# first, or `open` would just bring the old build back to the front.
run: build-app
	@app='$(app_path)'; \
	  test -d "$$app" || { echo "no app at $$app -- did the build fail?"; exit 1; }; \
	  pkill -x $(SCHEME) >/dev/null 2>&1 || true; \
	  echo "launching $$app"; \
	  open "$$app"

## Install a Release build into /Applications
# Ad-hoc signed unless a DEVELOPMENT_TEAM is passed, which is fine for a local
# install -- a locally built bundle carries no quarantine flag, so Gatekeeper
# does not object. Pass a team to get something you can hand to anyone else.
install: CONFIGURATION := Release
install: build-app
	@app='$(app_path)'; \
	  test -d "$$app" || { echo "no app at $$app -- did the build fail?"; exit 1; }; \
	  pkill -x $(SCHEME) >/dev/null 2>&1 || true; \
	  rm -rf '/Applications/$(SCHEME).app'; \
	  cp -R "$$app" /Applications/; \
	  echo "installed /Applications/$(SCHEME).app"

## Build the corpus pipeline in release mode
# Phony rather than a rule on $(CORPUS_BIN): swift build tracks its own sources
# and is a no-op when they have not changed, which make cannot say without
# restating the package's file list here.
corpus-tool:
	swift build -c release --package-path $(CORPUS_BUILD)

# Twenty documents by default, enough to exercise the pipeline in a minute. The
# full set is 8,464 legacy RFCs, roughly 450 MB and twenty minutes:
#
#   make corpus CORPUS_LIMIT= CORPUS_VERSION=2026.09
#
# The `.noindex` suffixes are load-bearing, not decoration. macOS skips any
# directory whose name ends in `.noindex`; without it Spotlight indexes the
# 450 MB of text and 460 MB of XML as the pipeline writes them, and a full run
# measured 2,294 of 8,457 documents in 2h16m with corespotlightd at 252% -- the
# conversion queued behind the indexing of its own output (issue #38). The
# alternative is each developer adding corpus/ to their own privacy list, which
# fixes one machine; this fixes it for everyone who clones the repo.
CORPUS         ?= corpus
CORPUS_LIMIT   ?= 20
CORPUS_VERSION ?= dev

## Fetch the legacy plain-text RFCs
corpus-fetch: corpus-tool
	$(CORPUS_BIN) fetch --out $(CORPUS) $(if $(CORPUS_LIMIT),--limit $(CORPUS_LIMIT))

## Convert the fetched text to RFCXML v3, writing a conversion report
corpus-convert: corpus-tool
	$(CORPUS_BIN) convert --in $(CORPUS)/text.noindex --out $(CORPUS)/xml.noindex \
	  --overrides $(CORPUS)/overrides --report $(CORPUS)/report.json \
	  --diagnostics $(CORPUS)/prose.json

## Write the pack manifest for the converted documents
corpus-manifest: corpus-tool
	$(CORPUS_BIN) manifest --dir $(CORPUS)/xml.noindex --out $(CORPUS)/manifest.json \
	  --version $(CORPUS_VERSION)

## Run the whole corpus pipeline: fetch, convert, manifest
# Review corpus/report.json afterwards; it is what says whether a conversion
# regressed.
corpus: corpus-fetch corpus-convert corpus-manifest
