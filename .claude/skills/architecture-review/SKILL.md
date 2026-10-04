---
name: architecture-review
description: Review the whole code base's architecture, read-only - module structure, patterns, concerns and the assumptions behind them - and bring the maintainer one ranked report of verified findings - god objects and long files, duplication, home-grown code an established library or platform API covers, suboptimal use of Swift or the platform, ossified workarounds, wrong assumptions, performance bottlenecks and concentrations of complexity with downstream effects. Not a diff review (that is code-review and rules-reviewer). Use when asked for "an architecture review", "a structural review of the code base", or "/architecture-review [area...] [--issues]".
---

# Architecture review

You orchestrate: you take the inventory, one subagent per area reviews it, and every finding is verified before it reaches the report. The review changes no code, commits nothing and posts nothing to GitHub unless it was given `--issues` (step 6).

Arguments: area names from the table in step 3 narrow the review to those areas (the cross-cutting pass in step 4 still runs over them); `--issues` files the accepted findings once the maintainer has seen the report.

What makes a finding worth the maintainer's time is its **downstream effect**: what it makes slower, riskier or more expensive to change, shown in this code base with a file, a number or an issue. Size, age or unfamiliarity alone is not a finding. The legacy text heuristics are complex because 8,457 plain-text documents are; complexity the domain needs is reported only where it has leaked out of the place that owns it.

## 1. Read the record first

This repository writes down why it is the way it is. A review that has not read it re-proposes what was measured and rejected.

- `CLAUDE.md`: the structural rule and the standing constraints.
- `docs/ARCHITECTURE.md` in full, `docs/VISION.md` (the feature tiers and the UI principles), `docs/DATA_PIPELINE.md`.
- The title of every record in `docs/decisions/`, and the full text of each one whose subject an area touches. Give each subagent the list of records for its area.
- The open issues, so a finding cites the issue that already tracks it instead of rediscovering it: `gh issue list --state open --limit 500 --json number,title,labels` (in a cloud session, the GitHub MCP tools' `list_issues`). Write them to the scratchpad and hand the file to every subagent.

**A decision is not immune, but it is not ignorant either.** A finding that contradicts a decision record or a `CLAUDE.md` constraint names it, engages with its reasoning and the measurements it cites, and says what has changed since: the platform, the code around it, the numbers. Such a finding goes in the report's "Challenged decisions", never among the ordinary findings, and never proposes an alternative the record already measured and rejected unless something it measured has changed.

## 2. Take the inventory

Mechanical, by you, before any agent starts; it is what keeps the findings to numbers rather than impressions. [inventory.sh](inventory.sh) takes it, read-only, in a few seconds; in a shallow clone, `git fetch --unshallow` first so the churn counts are real:

```sh
sh .claude/skills/architecture-review/inventory.sh > "$SCRATCHPAD/inventory.md"
```

Read the output before you hand it on: the function lengths and fan-in are approximations from `awk` and `grep`, good enough to point at a file and not to quote unchecked. It covers:

- size: lines per module, the longest files and functions, the types extended across most files;
- shape: the import graph per module, the public surface of each package, `#if os(…)` forks per file;
- concurrency escape hatches: `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `MainActor.assumeIsolated`, `DispatchQueue`, `Task.detached`, locks;
- workaround markers: `workaround`, `hack`, `FB` numbers, `radar`, `TODO`, `FIXME`, `swiftlint:disable`, `#available`, and comments that cite an OS version;
- home-grown candidates: a type that re-implements something the standard library, Foundation, an Apple framework or a well-known package does;
- churn: files changed most often (all history, or since `CHURN_SINCE`), and how often a fix touched them. Size × churn is the hotspot list;
- fan-in: how many files reference each central type (`RFCDocument`, `LibraryModel`, `DocumentTextBuilder`, …);
- tests per source module, and source files no test references.

## 3. One subagent per area, at most five at a time

| Area | What it covers |
|---|---|
| `model` | RFCKit `Document/`: `RFCDocument`, both parsers, the serializer, `SectionAlignment`, artwork and packet diagrams |
| `kit` | the rest of RFCKit: `Models/`, `Index/`, `Client/`, `Registry/`, `Search/`, `Highlighting/`, `Citation/`, `Corpus/` |
| `rendering` | RFCReaderKit `Rendering/`, `Geometry/`, `Layout/`, printing and PDF export, accessibility |
| `stores` | RFCReaderKit `Cache/`, `UserData/`, `Library/`, `Navigation/`, `Offline/`, `ReadingPath/` and the loose files at its root |
| `app` | `App/RFCReader/Model/` and `Views/`: `LibraryModel`, `NavigationModel`, `ReaderState`, the reader's text views and coordinator, the iOS/macOS split |
| `shell` | `App/RFCReader/Window/`, `Commands/`, `Scripting/`, `Intents/`, `RFCReaderApp.swift`, and RFCReaderKit `Chrome/` (menus, toolbar and window chrome they feed) |
| `build` | `Tools/` (corpus-build, benchmarks, trace), the `Makefile`, `project.yml`, `.github/workflows/`, lint and format configuration |

An area over about 8,000 lines of source (the inventory's first table; `app` is over it) is split in two along a folder boundary. Write the prompt below to the scratchpad once per area and start each agent with `subagent_type: general-purpose` (not `Explore`, which locates code rather than reviewing it), pointing at its file.

<prompt>
Review the architecture of one area of rfc-reader, read-only: AREA (FOLDERS). Do not edit, commit or post anything.

Read first: CLAUDE.md; docs/ARCHITECTURE.md; these decision records: RECORDS; the inventory at INVENTORY; the open issues at ISSUES; the lenses at .claude/skills/architecture-review/lenses.md. Then read every source file in your area in full; skim tests only to see what they pin.

Apply each lens in lenses.md to your area. For each problem, write a finding in the schema at the end of lenses.md, to FINDINGS. Rules:
- Every finding cites file:line and evidence you read yourself. A number comes from the inventory or a command you ran; say which.
- Say what it costs downstream: what change it makes harder, what bug it caused or will cause (an issue number where one exists), what it makes slower.
- An alternative names the exact API, type or package, and whether it is available on Linux (RFCKit is tested there), on the iOS/macOS 26 deployment target, and under Swift 6 strict concurrency.
- A finding that contradicts CLAUDE.md or a decision record says so in "Conflicts" and engages the record's reasoning; one the record already measured and rejected is dropped unless what it measured has changed.
- A performance claim is "measured" only with a benchmark from `make benchmark`, a signpost from `make trace` or a command you ran; otherwise it is a hypothesis and names the measurement that would settle it.
- Do not quote RFC text in a finding. A locator of a few words is enough.
- Something that looks wrong but is deliberate (a comment, a decision or a test says why) goes under "Considered, not a finding" with the reason, in one line.
- Prefer five well-evidenced findings to twenty impressions. Size alone is not a finding.

Report: the path of FINDINGS, the number of findings per severity, and anything in your area you could not assess and why.
</prompt>

While they run, do the cross-cutting pass yourself (step 4).

## 4. Cross-cutting pass

What no single area sees:

- **Layering.** The import graph against the structural rule: RFCKit free of Apple-only frameworks, the app free of XML and the 72-column format, nothing testable in the App target, nothing in RFCReaderKit that only the app needs.
- **Duplication across areas.** The same concept implemented twice: two XML readers, two text views, a reader build and a print build, the iOS and macOS paths of one feature, several caches or stores with their own eviction and persistence, several ways the same text is copied (#720 was three).
- **Change scenarios.** Take three or four changes the next tiers of `docs/VISION.md` imply (a new block kind, full-text search landing, a new platform such as visionOS, iCloud sync of user data) and count the files and types each must touch. A scenario that touches many places, or places in all three packages, names the concentration that causes it. This is the strongest evidence a structural finding can have.
- **The data path end to end.** Index fetch → document fetch and cache → parse → build → install → layout, and for each hop: which actor it runs on, what is copied, what is retained and by whom, what is computed twice.
- **Documentation against code.** Claims in `ARCHITECTURE.md` that the code no longer bears out; decisions superseded in code but not marked; documentation that has become a changelog where it should describe.

Write these findings to the same schema, as area `cross`.

## 5. Verify, then rank

Every finding is verified before it is reported. For each area's findings file, start one fresh `general-purpose` agent (not the one that wrote it) with the file and this instruction: *"Try to refute each finding. Open the cited lines and check the evidence; check whether a decision record, a `CLAUDE.md` constraint, a comment or an open issue already covers it; check that the proposed alternative exists, runs on Linux where RFCKit needs it, and would not break a standing rule; re-run any command whose number is cited. Mark each finding confirmed, downgraded (with the new severity or confidence) or refuted (with the reason)."* Check the cross-cutting findings the same way yourself.

Drop the refuted ones, but keep a line for each under "Considered, not a finding", so the next review does not spend time on them again. Merge duplicates across areas into one finding with every location.

Rank by severity, then by how much a fix would unlock (a finding that several others depend on goes first). Severity:

- **high**: causes bugs or user-visible slowness now, or blocks a feature `VISION.md` plans;
- **medium**: makes a class of change measurably more expensive or riskier (the change scenarios show it);
- **low**: a local cleanup with no effect past its file.

## 6. Report

Write the report to the path you were given, by default `architecture-review-YYYY-MM-DD.md` in the scratchpad; it is not committed unless the maintainer asks. Shape:

1. **Summary**: the three to five things that matter most, one or two sentences each, and the date and commit reviewed (`git rev-parse --short HEAD`).
2. **Map**: modules with their size, the hotspot table (size × churn), the fan-in of the central types, and the change-scenario counts.
3. **Findings**, ranked, in the schema of `lenses.md`.
4. **Challenged decisions**: each with the record, its reasoning, what has changed, and what would settle it.
5. **Considered, not a finding**: one line each, with the reason.
6. **Questions for the maintainer**: what the review could not decide, with the options and a recommendation.
7. **Suggested order**: which findings to take first and why, including the ones that unblock others.

Relay the summary and the path to the user; do not paste the whole report.

With `--issues`, and only after the maintainer has seen the report and said which findings to file: one issue per accepted finding, titled as the claim, the finding as its body, labeled from `.github/labels.yml`: `enhancement` (or `bug` for one that causes a defect now), the `area:` labels it touches, and `platform:` only when it is specific to one. Never invent a label; that file is the list. Search the open issues for one that already covers it first, and comment there instead. Never apply `agent-ready`; that label is the maintainer's.
