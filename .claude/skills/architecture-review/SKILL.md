---
name: architecture-review
description: Review the whole app critically, read-only, as a staff platform engineer and a designer would - the code's structure, patterns and assumptions, how well it uses the platform, and the experience it gives - and bring the maintainer one ranked report of verified findings. Covers god objects and long files, duplication, home-grown code an established library or platform API covers, misused Swift or platform features, ossified workarounds, wrong assumptions, performance, memory and launch, concentrations of complexity; privacy, App Review readiness, localization, accessibility, lifecycle and data durability, observability; and task flows, interface design, HIG fidelity, discoverability and per-device idiom. Not a diff review (that is code-review and rules-reviewer). Use when asked for "an architecture review", "a structural review", "a UX review", "a HIG review" or "/architecture-review [area...] [--issues]".
---

# Architecture review

You orchestrate: you take the inventory, one subagent per area reviews it, and every finding is verified before it reaches the report. The review changes no code, commits nothing and posts nothing to GitHub unless it was given `--issues` (step 7).

Arguments: area names from the table in step 3 narrow the review to those areas (the cross-cutting pass in step 5 still runs over them); `--issues` files the accepted findings once the maintainer has seen the report.

The review has three halves, and [lenses.md](lenses.md) has the questions for each: **code** (lenses 1–10: structure, duplication, language use, performance, complexity), **platform** (11–15: privacy and App Review, localization, accessibility, lifecycle and durability, observability and release), and **experience** (16–20: task flows, interface design and the HIG, discoverability, per-device idiom, states and writing).

What makes a finding worth the maintainer's time is its **effect**: what it makes slower, riskier or more expensive to change, or what it makes harder, slower or impossible for someone using the app, shown with a file, a number, a screenshot or an issue. Size, age, unfamiliarity or taste alone is not a finding. The legacy text heuristics are complex because 8,457 plain-text documents are; complexity the domain needs is reported only where it has leaked out of the place that owns it.

## 1. Read the record first

This repository writes down why it is the way it is. A review that has not read it re-proposes what was measured and rejected.

- `CLAUDE.md`: the structural rule and the standing constraints.
- `docs/ARCHITECTURE.md` in full, `docs/VISION.md` (the feature tiers, the guiding principles and "What the experience should feel like", which the experience lenses hold the app to), `docs/DATA_PIPELINE.md`.
- The title of every record in `docs/decisions/`, and the full text of each one whose subject an area touches. Give each subagent the list of records for its area. Several are about interaction (previews on hover and force-click, hiding the bars on iPhone, reading modes, backlink chips): the experience areas read those.
- The open issues, so a finding cites the issue that already tracks it instead of rediscovering it: `gh issue list --state open --limit 500 --json number,title,labels` (in a cloud session, the GitHub MCP tools' `list_issues`). Write them to the scratchpad and hand the file to every subagent. Issues labeled `area: ux` and `area: accessibility` go to the experience areas in particular.

**A decision is not immune, but it is not ignorant either.** A finding that contradicts a decision record, a `CLAUDE.md` constraint or a `VISION.md` principle names it, engages with its reasoning and the measurements it cites, and says what has changed since: the platform, the code around it, the numbers. Such a finding goes in the report's "Challenged decisions", never among the ordinary findings, and never proposes an alternative the record already measured and rejected unless something it measured has changed.

## 2. Know what this machine can assess

Several lenses need evidence only a Mac produces: Instruments and `make trace`, the Accessibility Inspector and VoiceOver, a running app to look at and use, the privacy report Xcode builds from an archive. Decide up front which of these this run has (`uname`, `xcrun --version`, `xcrun simctl list devices available`) and tell every subagent.

**Never guess what could not be observed.** A finding that needs a Mac and was reviewed without one is written from the code, says so in its confidence (`unassessed: needs a Mac — <what to run>`), and goes to the report's "Unassessed here" section, not among the ranked findings. On Linux the experience areas still run, from the view code (menus, shortcuts, toolbars, context menus, states, strings), and their visual and interaction claims all land there.

## 3. Take the inventory

Mechanical, by you, before any agent starts; it is what keeps the findings to numbers rather than impressions. [inventory.sh](inventory.sh) takes it, read-only, in a few seconds; in a shallow clone, `git fetch --unshallow` first so the churn counts are real:

```sh
sh .claude/skills/architecture-review/inventory.sh > "$SCRATCHPAD/inventory.md"
```

Read the output before you hand it on: the function lengths, fan-in and platform signals are approximations from `awk` and `grep`, good enough to point at a file and not to quote unchecked. It covers:

- size: lines per module, the longest files and functions, the types extended across most files;
- shape: the import graph per module, the public surface of each package, `#if os(…)` forks per file;
- concurrency escape hatches: `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `MainActor.assumeIsolated`, `DispatchQueue`, `Task.detached`, locks;
- workaround markers: `workaround`, `hack`, `FB` numbers, `radar`, `TODO`, `FIXME`, `swiftlint:disable`, `#available`, and comments that cite an OS version;
- home-grown candidates: a type that re-implements something the standard library, Foundation, an Apple framework or a well-known package does;
- churn: files changed most often (all history, or since `CHURN_SINCE`), and how often a fix touched them. Size × churn is the hotspot list;
- fan-in: how many files reference each central type (`RFCDocument`, `LibraryModel`, `DocumentTextBuilder`, …);
- tests per source module, and source files no test references;
- platform signals: privacy manifest, required-reason APIs, entitlements, string catalogs and unlocalized literals, logging and MetricKit, memory-pressure handling, state restoration, undo, UI tests, schema versions;
- interface signals: keyboard shortcuts, menu commands, `.help` tooltips, context menus, swipe actions, empty states, accessibility modifiers, fixed font sizes and literal colors, custom controls.

## 4. One subagent per area, at most five at a time

| Area | What it covers | Lenses |
|---|---|---|
| `model` | RFCKit `Document/`: `RFCDocument`, both parsers, the serializer, `SectionAlignment`, artwork and packet diagrams | 1–10, 11 (untrusted input) |
| `kit` | the rest of RFCKit: `Models/`, `Index/`, `Client/`, `Registry/`, `Search/`, `Highlighting/`, `Citation/`, `Corpus/` | 1–10, 11, 12 (formatting), 14 (network failure) |
| `rendering` | RFCReaderKit `Rendering/`, `Geometry/`, `Layout/`, printing and PDF export, accessibility | 1–10, 12, 13 |
| `stores` | RFCReaderKit `Cache/`, `UserData/`, `Library/`, `Navigation/`, `Offline/`, `ReadingPath/` and the loose files at its root | 1–10, 11, 14 |
| `app` | `App/RFCReader/Model/` and `Views/`: `LibraryModel`, `NavigationModel`, `ReaderState`, the reader's text views and coordinator, the iOS/macOS split | 1–15 |
| `shell` | `App/RFCReader/Window/`, `Commands/`, `Scripting/`, `Intents/`, `RFCReaderApp.swift`, and RFCReaderKit `Chrome/` | 1–15 |
| `build` | `Tools/` (corpus-build, benchmarks, trace), the `Makefile`, `project.yml`, `.github/workflows/`, lint and format configuration | 1–10, 11 (entitlements, signing), 15 |
| `experience-mac` | the running macOS app, its menus, windows, toolbar, inspector, settings, Services, scripting | 13, 16–20 |
| `experience-ios` | the running app on iPhone and on iPad, in portrait and landscape, with a hardware keyboard on iPad | 13, 16–20 |

An area over about 8,000 lines of source (the inventory's first table; `app` is over it) is split in two along a folder boundary. Write the prompt below to the scratchpad once per area and start each agent with `subagent_type: general-purpose` (not `Explore`, which locates code rather than reviewing it), pointing at its file. For an experience area, add the second block.

<prompt>
Review one area of rfc-reader, read-only: AREA (SCOPE). Do not edit, commit or post anything.

Read first: CLAUDE.md; docs/ARCHITECTURE.md; docs/VISION.md; these decision records: RECORDS; the inventory at INVENTORY; the open issues at ISSUES; the lenses at .claude/skills/architecture-review/lenses.md. Then read every source file in your area in full; skim tests only to see what they pin.

Apply lenses LENSES of lenses.md to your area. This machine can assess: CAPABILITIES. For each problem, write a finding in the schema at the end of lenses.md, to FINDINGS. Rules:
- Every finding cites file:line, or a screenshot path, and evidence you saw yourself. A number comes from the inventory or a command you ran; say which.
- Say what it costs: what change it makes harder, what bug it caused or will cause (an issue number where one exists), what it makes slower, or what someone using the app cannot do, cannot find, or does wrong because of it.
- An alternative names the exact API, type, package or HIG pattern, and whether it is available on Linux (RFCKit is tested there), on the iOS/macOS 26 deployment target, and under Swift 6 strict concurrency.
- A finding that contradicts CLAUDE.md, a decision record or a VISION.md principle says so in "Conflicts" and engages the reasoning; one a record already measured and rejected is dropped unless what it measured has changed.
- A performance claim is "measured" only with a benchmark from `make benchmark`, a signpost from `make trace`, an Instruments run or a command you ran; otherwise it is a hypothesis and names the measurement that would settle it.
- What needs a Mac and this machine is not one: write it from the code, mark it `unassessed: needs a Mac — <what to run>`. Never describe what a screen looks like or how an interaction feels without having seen it.
- Do not quote RFC text in a finding. A locator of a few words is enough.
- Something that looks wrong but is deliberate (a comment, a decision or a test says why) goes under "Considered, not a finding" with the reason, in one line.
- Prefer five well-evidenced findings to twenty impressions. Size or taste alone is not a finding.

Report: the path of FINDINGS, the number of findings per severity, and anything in your area you could not assess and why.
</prompt>

<experience-prompt>
You review the app as someone using it, on PLATFORM. Build and launch it: `make run` on macOS; `make run-sim IOS_SIMULATOR='<device>'` for an iPhone and again for an iPad from `xcrun simctl list devices available` (both with `CODE_SIGNING_ALLOWED=NO`). Open documents with the app's own URL scheme, `open 'rfc://9110#section-4.2'` or `xcrun simctl openurl booted 'rfc://9110'`; on macOS the AppleScript dictionary (`App/RFCReader/Scripting/`) can drive more. Take a screenshot of every state you report on, into SCREENSHOTS (`screencapture -x` or `-l<window id>`; `xcrun simctl io booted screenshot`), and cite it. Check each screen in light and dark appearance, at the largest accessibility text size (`xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`), and with Increase Contrast and Reduce Motion where the platform lets you set them.

Walk the tasks in lens 16 first, counting the steps and noting every place you had to know something the interface did not tell you; then apply the other lenses to what you saw. Compare against Apple's Human Interface Guidelines for PLATFORM and against the system apps that do the same job (Books, Preview, Notes, Safari's Reader, Xcode's documentation viewer): a deviation from them is a finding only when it costs the person something, and the finding says what.
</experience-prompt>

While they run, do the cross-cutting pass yourself (step 5).

## 5. Cross-cutting pass

What no single area sees:

- **Layering.** The import graph against the structural rule: RFCKit free of Apple-only frameworks, the app free of XML and the 72-column format, nothing testable in the App target, nothing in RFCReaderKit that only the app needs.
- **Duplication across areas.** The same concept implemented twice: two XML readers, two text views, a reader build and a print build, the iOS and macOS paths of one feature, several caches or stores with their own eviction and persistence, several ways the same text is copied (#720 was three).
- **Change scenarios.** Take three or four changes the next tiers of `docs/VISION.md` imply (a new block kind, full-text search landing, a new platform such as visionOS, iCloud sync of user data, a second language for the interface) and count the files and types each must touch. A scenario that touches many places, or places in all three packages, names the concentration that causes it. This is the strongest evidence a structural finding can have.
- **The data path end to end.** Index fetch → document fetch and cache → parse → build → install → layout, and for each hop: which actor it runs on, what is copied, what is retained and by whom, what is computed twice, and what happens when it fails or the app is terminated during it.
- **Code against experience.** Where an experience finding has its cause in structure (a feature missing on iPad because it lives in a macOS-only file, a state with no empty view because the model cannot express it), join the two into one finding with both locations.
- **Principles against the product.** Each guiding principle in `VISION.md` against what the app does; "Native on every platform" against the AppKit window layer is one to engage with, not to assume either way.
- **Documentation against code.** Claims in `ARCHITECTURE.md` that the code no longer bears out; decisions superseded in code but not marked; documentation that has become a changelog where it should describe.

Write these findings to the same schema, as area `cross`.

## 6. Verify, then rank

Every finding is verified before it is reported. For each area's findings file, start one fresh `general-purpose` agent (not the one that wrote it) with the file and this instruction: *"Try to refute each finding. Open the cited lines and screenshots and check the evidence; check whether a decision record, a `CLAUDE.md` constraint, a `VISION.md` principle, a comment or an open issue already covers it; check that the proposed alternative exists, runs on Linux where RFCKit needs it, is what the current Human Interface Guidelines recommend where it claims so, and would not break a standing rule; re-run any command whose number is cited. Mark each finding confirmed, downgraded (with the new severity or confidence) or refuted (with the reason)."* Check the cross-cutting findings the same way yourself.

Drop the refuted ones, but keep a line for each under "Considered, not a finding", so the next review does not spend time on them again. Merge duplicates across areas into one finding with every location.

Rank by severity, then by how much a fix would unlock (a finding that several others depend on goes first). Severity:

- **high**: causes bugs, data loss or user-visible slowness now; would get a build rejected by App Review or fail a privacy requirement; keeps someone using VoiceOver, Full Keyboard Access or the largest text sizes from a core task; leaves a Tier 0 task in `VISION.md` undiscoverable; or blocks a feature `VISION.md` plans;
- **medium**: makes a class of change measurably more expensive or riskier (the change scenarios show it), or makes a task slower or more error-prone than the platform's own apps make it;
- **low**: a local cleanup with no effect past its file, or a deviation from the HIG with a small cost.

## 7. Report

Write the report to the path you were given, by default `architecture-review-YYYY-MM-DD.md` in the scratchpad, with the screenshots beside it; it is not committed unless the maintainer asks. Shape:

1. **Summary**: the three to five things that matter most, one or two sentences each; the date, the commit reviewed (`git rev-parse --short HEAD`), and what this machine could assess.
2. **Map**: modules with their size, the hotspot table (size × churn), the fan-in of the central types, the change-scenario counts, and the task-flow table (task, steps on each platform, where it stalled).
3. **Findings**, ranked, in the schema of `lenses.md`, grouped code, platform, experience within each severity.
4. **Challenged decisions**: each with the record or principle, its reasoning, what has changed, and what would settle it.
5. **Unassessed here**: what needs a Mac or a device, one line each with what to run.
6. **Considered, not a finding**: one line each, with the reason.
7. **Questions for the maintainer**: what the review could not decide, with the options and a recommendation. Matters of product taste go here, not among the findings.
8. **Suggested order**: which findings to take first and why, including the ones that unblock others.

Relay the summary and the path to the user; do not paste the whole report.

With `--issues`, and only after the maintainer has seen the report and said which findings to file: one issue per accepted finding, titled as the claim, the finding as its body, labeled from `.github/labels.yml`: `enhancement` (or `bug` for one that causes a defect now), the `area:` labels it touches (`area: ux`, `area: accessibility` and `area: performance` included), and `platform:` only when it is specific to one. Never invent a label; that file is the list. Search the open issues for one that already covers it first, and comment there instead. Never apply `agent-ready`; that label is the maintainer's.
