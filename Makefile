.PHONY: lint fmt build test check xcodeproj build-app build-ios corpus corpus-tool corpus-fetch corpus-convert corpus-manifest

# The two Swift packages. RFCKit holds everything the app and the pipeline share
# -- parsers, index, search, citations -- and builds anywhere a Swift 6 toolchain
# does, including Linux. corpus-build is the offline pipeline that turns the
# legacy plain-text RFCs into RFCXML packs (docs/DATA_PIPELINE.md).
RFCKIT       := Packages/RFCKit
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

## Generate the Xcode project from project.yml
# Not phony: project.yml is the source of truth and the project it produces is
# gitignored, so the generate only reruns when the spec is newer than the
# project. `touch` because xcodegen leaves the directory's own mtime alone when
# nothing inside it changed.
$(PROJECT): project.yml
	xcodegen generate
	@touch $@

xcodeproj: $(PROJECT)

# project.yml ships without a DEVELOPMENT_TEAM, and xcodebuild refuses to sign
# without one. Compiling is what the two app targets are for, so signing is off
# unless a team is passed:
#
#   make build-app DEVELOPMENT_TEAM=ABCDE12345
#
DEVELOPMENT_TEAM ?=
SIGNING := $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),CODE_SIGNING_ALLOWED=NO)

## Build the app for macOS
build-app: $(PROJECT)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -quiet $(SIGNING)

## Build the app for the iOS Simulator
build-ios: $(PROJECT)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS Simulator' -quiet $(SIGNING)

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
CORPUS         ?= corpus
CORPUS_LIMIT   ?= 20
CORPUS_VERSION ?= dev

## Fetch the legacy plain-text RFCs
corpus-fetch: corpus-tool
	$(CORPUS_BIN) fetch --out $(CORPUS) $(if $(CORPUS_LIMIT),--limit $(CORPUS_LIMIT))

## Convert the fetched text to RFCXML v3, writing a conversion report
corpus-convert: corpus-tool
	$(CORPUS_BIN) convert --in $(CORPUS)/text --out $(CORPUS)/xml \
	  --overrides $(CORPUS)/overrides --report $(CORPUS)/report.json

## Write the pack manifest for the converted documents
corpus-manifest: corpus-tool
	$(CORPUS_BIN) manifest --dir $(CORPUS)/xml --out $(CORPUS)/manifest.json \
	  --version $(CORPUS_VERSION)

## Run the whole corpus pipeline: fetch, convert, manifest
# Review corpus/report.json afterwards; it is what says whether a conversion
# regressed.
corpus: corpus-fetch corpus-convert corpus-manifest
