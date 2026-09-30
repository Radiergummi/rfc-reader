.PHONY: lint fmt build test check test-app test-corpus xcodegen-install xcodeproj build-app ios-sim ios-app run-device run-device-check run install trace benchmark corpus corpus-tool corpus-fetch corpus-fetch-xml corpus-convert corpus-schema-control corpus-overrides-check corpus-manifest corpus-queries corpus-score revisions

# The three Swift packages. RFCKit holds everything the app and the pipeline share
# -- parsers, index, search, citations -- and builds anywhere a Swift 6.3 toolchain
# does, including Linux. RFCReaderKit is the app's testable half, and imports
# UIKit/AppKit, so it needs an Apple SDK. corpus-build is the offline pipeline that
# turns the legacy plain-text RFCs into RFCXML packs (docs/DATA_PIPELINE.md).
RFCKIT       := Packages/RFCKit
RFCREADERKIT := Packages/RFCReaderKit
CORPUS_BUILD := Tools/corpus-build
BENCHMARKS   := Tools/benchmarks
CORPUS_BIN   := $(CORPUS_BUILD)/.build/release/corpus-build

# Whether this machine has an Apple SDK, so RFCReaderKit can build here.
DARWIN := $(filter Darwin,$(shell uname -s))

# The corpus working directory (see the corpus targets below). Set here rather
# than with them because `test-corpus` names files in it as prerequisites, and
# make expands a prerequisite where it reads the rule.
CORPUS ?= corpus

# What every download below sends, as corpus-build's fetch does
# (`RetryingTransport.userAgent`): a bulk fetch the RFC Editor can tell apart. curl
# retries what can pass -- a timeout, a 429, a 5xx -- three times with backoff.
CURL := curl -fsS --retry 3 -A 'rfc-reader corpus-build (+https://github.com/Radiergummi/rfc-reader)'

# Every Swift source we own. Found rather than handed to swift-format's
# --recursive, which would also walk the SwiftPM build directories and format
# the files they generate.
SWIFT_SOURCES = $(shell find App Packages Tools -name '*.swift' -not -path '*/.build/*')

PROJECT := RFCReader.xcodeproj
SCHEME  := RFCReader

# The XcodeGen release the project is generated with, and its zip's SHA-256
# (#165). CI installs exactly this through `xcodegen-install`; `xcodeproj` runs
# that install when there is one, the xcodegen on the PATH otherwise, and warns
# when the one it runs is another version.
XCODEGEN_VERSION := 2.46.0
XCODEGEN_SHA256  := 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
XCODEGEN_DIR     ?= .build/xcodegen
XCODEGEN          = $(or $(wildcard $(XCODEGEN_DIR)/xcodegen/bin/xcodegen),xcodegen)

## Lint all Swift sources
# --strict because .swiftlint.yml is tuned to the tree as it stands: every rule
# left enabled holds today, so a warning is something this change introduced
# rather than backlog to scroll past. swift-format checks layout against its
# own defaults (.swift-format), which is what `make fmt` produces.
#
# Both tools are whatever is installed here: SwiftLint from Homebrew, swift-format
# from the selected Xcode. CI pins its own -- SwiftLint 0.65.1 in its container,
# swift-format from the swift:6.3 image -- so a local lint that disagrees with CI
# is a version difference first. swift-format 6.3 and Xcode 27's format this tree
# byte for byte alike; an older Xcode's may not.
lint:
	swiftlint lint --strict
	swift format lint --strict --parallel $(SWIFT_SOURCES)

## Format all Swift sources in place
# swift-format runs last: it owns layout, and SwiftLint's corrections are
# not all layout-neutral.
fmt:
	swiftlint --fix
	swift format --in-place --parallel $(SWIFT_SOURCES)

## Build the Swift packages
# RFCReaderKit only on a Mac; elsewhere it cannot build.
build:
	swift build --package-path $(RFCKIT)
	swift build --package-path $(CORPUS_BUILD)
ifneq ($(DARWIN),)
	swift build --package-path $(RFCREADERKIT)
endif

## Run the RFCKit and corpus-build test suites
# The fast loop: no simulator, no Xcode project.
test:
	swift test --package-path $(RFCKIT)
	swift test --package-path $(CORPUS_BUILD)

## Run all checks (lint + packages + tests)
# The gate before committing. On a Mac it also builds and tests RFCReaderKit, as
# CI's macOS job does; elsewhere it cannot, and is weaker than CI by that package.
# CI does not call this: it runs the same commands as separate jobs, each in its
# own pinned environment (see `lint` above, and .github/workflows/ci.yml).
# Deliberately without build-app, which needs Xcode.
ifneq ($(DARWIN),)
check: lint build test test-app
else
check: lint build test
endif

## Run the app-side test suite (RFCReaderKit)
# Not part of `test`: this package imports UIKit/AppKit, so it needs an Apple
# SDK and cannot run in the swift:6.3 container the Linux job uses. `check` runs
# it on a Mac.
test-app:
	swift test --package-path $(RFCREADERKIT)

# The legacy RFCs the corpus-backed suites read. A finding about what the parser
# makes of a whole document is tested on that document, and no more RFC text is
# committed as fixtures, so these are fetched instead.
CORPUS_TEST_DOCUMENTS := rfc1012 rfc1043 rfc1122 rfc1140 rfc1142 rfc1178 rfc1198 rfc1343 rfc1415 rfc1441 rfc1581 rfc1958 rfc206 rfc2196 rfc2223 rfc2300 rfc2326 rfc2569 rfc2910 rfc355 rfc5193 rfc5545 rfc6186 rfc6614 rfc6654 rfc674 rfc707 rfc708 rfc722 rfc7231 rfc775 rfc783 rfc791 rfc793 rfc798 rfc8011 rfc817 rfc8259
# The RFCs authored in RFCXML they read, for what no committed XML fixture shows.
CORPUS_TEST_XML_DOCUMENTS := rfc9110 rfc9114

## Run the corpus-backed RFCKit suites, fetching the documents they read
# Not part of `check`: it needs the network the first time. The suites read
# RFC_CORPUS_TEXT and RFC_CORPUS_XML, and are skipped wherever they are unset, as in
# `make test`; CI runs them weekly (.github/workflows/corpus-tests.yml). Filtered by
# their type names, all `CorpusBacked...`: --filter matches a test's identifier, not
# the `Corpus-backed: ...` name its suite displays.
#
# The lists above are kept by hand. A test that reads a document not on them fails
# saying so, from `CorpusText`, rather than on a missing file.
test-corpus: $(CORPUS_TEST_DOCUMENTS:%=$(CORPUS)/text.noindex/%.txt) \
  $(CORPUS_TEST_XML_DOCUMENTS:%=$(CORPUS)/xml.noindex/%.xml)
	RFC_CORPUS_TEXT=$(abspath $(CORPUS)/text.noindex) RFC_CORPUS_XML=$(abspath $(CORPUS)/xml.noindex) \
	  swift test --package-path $(RFCKIT) --filter CorpusBacked

## Run the benchmarks, fetching the documents they read
# Release builds of the parsers, the search and the document builder, over real
# RFCs (Tools/benchmarks). Not part of `check`: the numbers are this machine's,
# and the first run needs the network. A change is measured against a baseline
# saved before it:
#
#   make benchmark BENCHMARK_ARGS='baseline update before'
#   make benchmark BENCHMARK_ARGS='baseline compare before'
#   make benchmark BENCHMARK_ARGS='--filter "Index.*"'
#
BENCHMARK_CORPUS := $(CORPUS)/benchmarks
BENCHMARK_INPUTS := rfc-index.xml rfc9110.xml rfc9000.xml rfc5661.txt rfc793.txt
BENCHMARK_ARGS ?=
benchmark: $(BENCHMARK_INPUTS:%=$(BENCHMARK_CORPUS)/%)
	RFC_CORPUS=$(abspath $(BENCHMARK_CORPUS)) \
	  swift package --package-path $(BENCHMARKS) --disable-sandbox benchmark $(BENCHMARK_ARGS)

# The benchmarks' inputs have a directory of their own, fetched once and then
# left alone: a baseline compares only while its inputs stay the same, and the
# corpus pipeline refetches its rfc-index.xml and converts whatever lies in
# text.noindex. Written to a partial file first, like the legacy RFCs below.
$(BENCHMARK_CORPUS)/rfc-index.xml:
	@mkdir -p $(@D)
	curl -fsS -o $@.part https://www.rfc-editor.org/rfc-index.xml && mv $@.part $@

$(BENCHMARK_CORPUS)/%:
	@mkdir -p $(@D)
	curl -fsS -o $@.part https://www.rfc-editor.org/rfc/$* && mv $@.part $@

# One legacy RFC, fetched where `make corpus` would have put it. Written to a
# partial file first, so an interrupted download is not taken for the document.
$(CORPUS)/text.noindex/%.txt:
	@mkdir -p $(@D)
	$(CURL) -o $@.part https://www.rfc-editor.org/rfc/$*.txt && mv $@.part $@

# One RFC authored in RFCXML, fetched where `make corpus-fetch-xml` would have put it.
$(CORPUS)/xml.noindex/%.xml:
	@mkdir -p $(@D)
	$(CURL) -o $@.part https://www.rfc-editor.org/rfc/$*.xml && mv $@.part $@

## Download the pinned XcodeGen release into XCODEGEN_DIR, checking its SHA-256
# Its binary is then XCODEGEN_DIR/xcodegen/bin/xcodegen, which `xcodeproj` prefers
# to the PATH's. The zip is written under a partial name first, so a download
# that fails its check is never unpacked, and a previous install is removed
# before unpacking, so no file of another release is left beside this one.
xcodegen-install:
	@mkdir -p $(XCODEGEN_DIR)
	curl -fsSL --retry 3 -o $(XCODEGEN_DIR)/xcodegen.zip.part https://github.com/yonaskolb/XcodeGen/releases/download/$(XCODEGEN_VERSION)/xcodegen.zip
	echo "$(XCODEGEN_SHA256)  $(XCODEGEN_DIR)/xcodegen.zip.part" | shasum -a 256 -c -
	mv $(XCODEGEN_DIR)/xcodegen.zip.part $(XCODEGEN_DIR)/xcodegen.zip
	rm -rf $(XCODEGEN_DIR)/xcodegen
	unzip -q $(XCODEGEN_DIR)/xcodegen.zip -d $(XCODEGEN_DIR)
	$(XCODEGEN_DIR)/xcodegen/bin/xcodegen --version

## Generate the Xcode project from project.yml
# Phony: XcodeGen's `sources:` entries are folder-based, so a source file added
# or removed under App/RFCReader has to be picked up even when project.yml
# itself is unchanged. A timestamp rule on project.yml alone missed that and
# left build-app failing with a confusing "cannot find X in scope". xcodegen
# runs in about a second, so regenerating unconditionally costs nothing next
# to the xcodebuild it precedes.
#
# Another XcodeGen version is a warning, not a failure: the project is
# generated and gitignored, and a Homebrew upgrade should not stop a build.
xcodeproj:
	@if ! command -v $(XCODEGEN) >/dev/null; then \
	  echo "XcodeGen $(XCODEGEN_VERSION) is not installed: make xcodegen-install, or brew install xcodegen" >&2; \
	  exit 1; \
	fi; \
	installed=$$($(XCODEGEN) --version 2>/dev/null | sed 's/^Version: //'); \
	if [ "$$installed" != "$(XCODEGEN_VERSION)" ]; then \
	  echo "warning: $(XCODEGEN) reports version '$$installed'; this project is generated with $(XCODEGEN_VERSION)" >&2; \
	fi
	$(XCODEGEN) generate

# Signed with the team project.yml names, provisioning included: automatic signing
# may create the profile and register this Mac or the attached iPhone on the way.
# CI has neither certificates nor an account, and builds only to prove the app
# compiles, so it turns signing off:
#
#   make build-app CODE_SIGNING_ALLOWED=NO
#
CODE_SIGNING_ALLOWED ?= YES
SIGNING := CODE_SIGNING_ALLOWED=$(CODE_SIGNING_ALLOWED) \
	  $(if $(filter YES,$(CODE_SIGNING_ALLOWED)),-allowProvisioningUpdates -allowProvisioningDeviceRegistration)

# Debug for everything but `install`, which puts a Release build in /Applications.
CONFIGURATION ?= Debug

# The iPhone `run-device` installs on, by the name `xcrun devicectl list devices`
# shows. `ios-app` alone builds for any iOS device.
IOS_DEVICE      ?=
IOS_DESTINATION ?= generic/platform=iOS

# Where xcodebuild left RFCReader.app for a destination. Asked for rather than
# spelled out: the DerivedData directory carries a hash of the project's own
# path, so it differs per checkout. Recursively expanded (`=`, not `:=`) so only
# the targets that need it pay for the xcodebuild call.
built_app = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(1)' -configuration $(CONFIGURATION) -showBuildSettings 2>/dev/null \
	  | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)/$(SCHEME).app

## Build the app for macOS
build-app: xcodeproj
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -configuration $(CONFIGURATION) -quiet $(SIGNING)

## Build the app for the iOS Simulator
ios-sim: xcodeproj
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS Simulator' -configuration $(CONFIGURATION) -quiet $(SIGNING)

## Build the app for an iOS device
ios-app: xcodeproj
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(IOS_DESTINATION)' -configuration $(CONFIGURATION) -quiet $(SIGNING)

## Build, install and launch the app on an attached iPhone
# Built for that one device rather than for any, so automatic signing registers
# it with the team if it is not yet. The iPhone needs Developer Mode on, and has
# to be unlocked for the launch.
#
#   make run-device IOS_DEVICE=Charon
#
run-device: IOS_DESTINATION = platform=iOS,name=$(IOS_DEVICE)
run-device: run-device-check ios-app
	@app='$(call built_app,$(IOS_DESTINATION))'; \
	  test -d "$$app" || { echo "no app at $$app -- did the build fail?"; exit 1; }; \
	  xcrun devicectl device install app --device '$(IOS_DEVICE)' "$$app" && \
	  xcrun devicectl device process launch --terminate-existing --device '$(IOS_DEVICE)' \
	    "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$app/Info.plist")"

run-device-check:
	@test -n '$(IOS_DEVICE)' || { echo "set IOS_DEVICE to one of these:"; xcrun devicectl list devices; exit 1; }

## Build and launch the macOS app
# A running copy is quit first, or `open` would just bring the old build back to
# the front.
run: build-app
	@app='$(call built_app,platform=macOS)'; \
	  test -d "$$app" || { echo "no app at $$app -- did the build fail?"; exit 1; }; \
	  pkill -x $(SCHEME) >/dev/null 2>&1 || true; \
	  echo "launching $$app"; \
	  open "$$app"

## Install a Release build into /Applications
install: CONFIGURATION := Release
install: build-app
	@app='$(call built_app,platform=macOS)'; \
	  test -d "$$app" || { echo "no app at $$app -- did the build fail?"; exit 1; }; \
	  pkill -x $(SCHEME) >/dev/null 2>&1 || true; \
	  rm -rf '/Applications/$(SCHEME).app'; \
	  cp -R "$$app" /Applications/; \
	  echo "installed /Applications/$(SCHEME).app"

## Record a Time Profiler trace of a scripted session and print the signposts
# Release, because that is what ships and what the numbers should describe; a
# Debug build is often several times slower in Swift code, and misleads. The
# session opens three large documents and searches (`Tools/trace/trace.py` has
# it); name another with TRACE_SCENARIO. The trace is kept in traces/ for
# Instruments, where the same intervals sit in the Points of Interest lane.
#
# The app runs against its real sandbox container, so Recently Read, reading
# positions and window restoration are the real ones, and the session can
# change them. It ends the copy it launched with SIGTERM, as `make run` ends a
# running one, but leaves any other running copy alone.
#
#   make trace
#   make trace TRACE_SCENARIO='wait 6; open 9110; wait 5'
#
# The scenario reaches the script through the environment, not spliced into the
# recipe, so a quote in a search does not end the shell's string.
TRACE_SCENARIO ?=
export TRACE_SCENARIO
trace: CONFIGURATION := Release
trace: build-app
	@app='$(call built_app,platform=macOS)'; \
	  Tools/trace/trace.py --app "$$app" \
	    --output "traces/$$(date +%Y%m%d-%H%M%S)-$$(git rev-parse --short HEAD).trace" \
	    $(if $(TRACE_SCENARIO),--scenario "$$TRACE_SCENARIO")

## Build the corpus pipeline in release mode
# Phony rather than a rule on $(CORPUS_BIN): swift build tracks its own sources
# and is a no-op when they have not changed, which make cannot say without
# restating the package's file list here.
corpus-tool:
	swift build -c release --package-path $(CORPUS_BUILD)

# Twenty documents by default, enough to exercise the pipeline in a minute. The
# full set is the 8,457 legacy RFCs with a text file, roughly 450 MB and twenty
# minutes:
#
#   make corpus CORPUS_LIMIT= CORPUS_VERSION=2026.09
#
# The `.noindex` suffixes are load-bearing, not decoration. macOS skips any
# directory whose name ends in `.noindex`; without it Spotlight indexes the
# 450 MB of text and 460 MB of XML as the pipeline writes them, and a full run
# measured 2,294 of 8,457 documents in 2h16m with corespotlightd at 252% -- the
# conversion queued behind the indexing of its own output (issue #38). The
# alternative is each developer adding corpus/ to their own privacy list, which
# fixes one machine; this fixes it for everyone who clones the repo. CORPUS
# itself is set at the top of this file.
CORPUS_LIMIT   ?= 20
CORPUS_VERSION ?= dev

# xml2rfc's RELAX NG schema for RFCXML v3, pinned and committed as data
# (Tools/corpus-build/Schema/README.md). Checked with xmllint, which ships with
# macOS and is libxml2-utils on Linux.
CORPUS_SCHEMA := $(CORPUS_BUILD)/Schema/v3.rng

## Fetch the legacy plain-text RFCs
corpus-fetch: corpus-tool
	$(CORPUS_BIN) fetch --out $(CORPUS) $(if $(CORPUS_LIMIT),--limit $(CORPUS_LIMIT))

## Fetch the RFCs that were authored in RFCXML
# These need no conversion, so they land straight in the XML directory beside the
# converted ones. Without them the corpus is legacy-only, which is not merely a
# gap in coverage: the current form of most of HTTP and TLS is a modern XML RFC,
# so a search index built without them cannot rank by currency -- the document
# that supersedes a hit is simply absent (issue #37).
corpus-fetch-xml: corpus-tool
	$(CORPUS_BIN) fetch --out $(CORPUS) --format xml $(if $(CORPUS_LIMIT),--limit $(CORPUS_LIMIT))

## Convert the fetched text to RFCXML v3, writing a conversion report
# The report's `schema` field says, per document, why the output is not valid
# RFCXML; `[]` is a document that validates. A regression is one that stops, and it
# fails the step once the new report is written. That report is the next run's
# baseline, so rerunning passes: read the documents it names first.
corpus-convert: corpus-tool
	$(CORPUS_BIN) convert --in $(CORPUS)/text.noindex --out $(CORPUS)/xml.noindex \
	  --overrides $(CORPUS)/overrides --report $(CORPUS)/report.json --index $(CORPUS)/rfc-index.xml \
	  --diagnostics $(CORPUS)/prose.json --schema $(CORPUS_SCHEMA)

## Check the schema check: three RFCs as the RFC Editor published them must validate
# If one fails, the schema or the validator is wrong, and no count the convert step
# reports means anything until it is fixed; so `corpus` runs this before converting.
# The three are fetched into a directory of their own, not the XML directory: a
# limited run leaves them out of it, and one fetched there would join the manifest
# and the packs of a run that never asked for it.
SCHEMA_CONTROL_DOCUMENTS := $(addprefix $(CORPUS)/schema-control.noindex/,rfc8999.xml rfc9113.xml rfc9220.xml)

corpus-schema-control: $(SCHEMA_CONTROL_DOCUMENTS)
	xmllint --noout --relaxng $(CORPUS_SCHEMA) $(SCHEMA_CONTROL_DOCUMENTS)

# One RFC as published in RFCXML, for the schema control.
$(CORPUS)/schema-control.noindex/%.xml:
	@mkdir -p $(@D)
	$(CURL) -o $@.part https://www.rfc-editor.org/rfc/$*.xml && mv $@.part $@

## Check that each scripted override is still what its script makes
# An override corrected by a script (corpus/overrides/rfcNNNN.py) is a snapshot of
# the converter's output, so a converter change can leave it stale without anything
# failing. This reruns every script against the current converter and compares.
# Not part of `check`: it needs the source text, fetched here when it is missing,
# and Python 3.9 or later. On a difference, commit the script's output.
corpus-overrides-check: corpus-tool
	@status=0; for script in $(CORPUS)/overrides/rfc*.py; do \
	  stem=$$(basename "$$script" .py); source=$(CORPUS)/text.noindex/$$stem.txt; \
	  test -f "$$source" || { mkdir -p $(CORPUS)/text.noindex && \
	    $(CURL) -o "$$source" "https://www.rfc-editor.org/rfc/$$stem.txt"; } || exit 1; \
	  out=$$(mktemp); python3 "$$script" $(CORPUS_BIN) "$$source" "$$out" || exit 1; \
	  if cmp -s "$$out" $(CORPUS)/overrides/$$stem.xml; then echo "$$stem.xml: up to date"; \
	  else echo "$$stem.xml: stale -- rerun $$script"; status=1; fi; rm -f "$$out"; \
	done; exit $$status

## Score the legacy parser against the RFCs xml2rfc generated from XML
# From RFC 8650 on, an RFC's text is generated from its XML, so the XML says what
# the text's headings, artwork and source code are (#42). This fetches both, parses
# the text with LegacyTextParser, and writes per-kind precision and recall, with
# the worst documents first, to corpus/score.json -- beside report.json, so a diff
# of either between runs is about one thing. A regression floor on uniform xml2rfc
# output, not a measure of the legacy corpus. Not part of `check`: it needs the
# network the first time.
corpus-score: corpus-fetch-xml
	$(CORPUS_BIN) fetch --out $(CORPUS) --format modern-text --index $(CORPUS)/rfc-index.xml \
	  $(if $(CORPUS_LIMIT),--limit $(CORPUS_LIMIT))
	$(CORPUS_BIN) score --xml $(CORPUS)/xml.noindex --text $(CORPUS)/modern-text.noindex \
	  --out $(CORPUS)/score.json

## Write the pack manifest for the converted documents
corpus-manifest: corpus-tool
	$(CORPUS_BIN) manifest --dir $(CORPUS)/xml.noindex --out $(CORPUS)/manifest.json \
	  --version $(CORPUS_VERSION)

## Rebuild the cross-reference judgment set used to measure search ranking
# Not part of `corpus`: it reads the converted corpus rather than producing it, and
# the set only changes when the corpus or the filtering does. It is written into the
# gitignored corpus directory, never the tree, because its queries are RFC sentences.
# See Tools/corpus-build/Evaluation/README.md for which query set measures what.
corpus-queries: corpus-tool
	$(CORPUS_BIN) queries --in $(CORPUS)/xml.noindex --out $(CORPUS)/queries-xref.json

## Scan datatracker for adopted drafts revising an RFC, into corpus/revisions
revisions: corpus-tool
	$(CORPUS_BIN) revisions --out $(CORPUS)/revisions $(if $(wildcard $(CORPUS)/revisions/revisions-scan.json),--scan $(CORPUS)/revisions/revisions-scan.json)

## Run the whole corpus pipeline: fetch, convert, manifest
# Review corpus/report.json afterwards; it is what says whether a conversion
# regressed.
corpus: corpus-fetch corpus-fetch-xml corpus-schema-control corpus-convert corpus-manifest
