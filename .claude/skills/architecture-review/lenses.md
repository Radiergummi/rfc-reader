# Lenses

Three groups: **code** (1–10), **platform** (11–15) and **experience** (16–20). Each area applies the lenses `SKILL.md` assigns it. Apply each lens to your area. The questions are prompts, not a form to fill in: report only what you found evidence for, and skip a lens with nothing to say. Where a question names a type or file, it is an example of where to look, not a finding.

# Code

## 1. Structure and boundaries

- Does each type sit in the package the structural rule puts it in? A pure function of its inputs under `App/` belongs in RFCReaderKit; anything Apple-only in RFCKit breaks the Linux tests.
- Does a dependency point the wrong way: RFCKit reaching for presentation concerns (how a reference *reads*, which is the builder's per decision "The parsers do not decide how a reference reads"), RFCReaderKit reaching for app state?
- Is the public surface of each package what its consumers need, or has `public` spread to make tests or the app compile?
- Does a folder's name still describe what is in it? Loose files at a package root that belong together are a missing folder.

## 2. God objects and long files

- For each type over about 500 lines, or with high fan-in in the inventory: list its responsibilities (its stored properties grouped by what they serve, its extensions, the reasons it changed in `git log`). More than one reason to change is the finding; the line count is only the pointer.
- Name the seams it would split along and the type each part would become. A split that leaves every caller reaching into both halves is not a seam.
- Is the type process-wide state that most views reach into (`LibraryModel`)? What does a view need from it, and could it be handed less?
- A long file that is long because it is a table (lexer rules, a list of cases) is not a god object.

## 3. Duplication

- The same concept implemented more than once: an XML reader per format, a text view per platform or purpose, a build for the reader and one for print, eviction and persistence per store, a copy path per gesture, the same parsing of a date, an identifier or a URL in several places.
- `#if os(iOS)` / `#if os(macOS)` forks whose two branches do the same thing with different spellings, versus forks that are genuinely different platforms.
- Tests that set up the same fixture state in many suites without a helper.
- Say what the duplication has cost: a fix made in one copy and not the other (search `git log` for it), or behavior that diverged.

## 4. Home-grown versus established

For each home-grown candidate in the inventory (a lexer engine, an XML DOM, a cache, a debouncer, a collection algorithm, SQLite used through its C API, string distance or alignment, date or URL parsing, a diff), ask:

- What established option exists, in this order of preference: the Swift standard library and Foundation (both on Linux), Apple frameworks on the iOS/macOS 26 target, Apple's open-source packages (swift-collections, swift-algorithms, swift-async-algorithms, swift-system), then well-known third-party packages.
- Does it run where this code must run? RFCKit is tested on Linux; corpus-build runs there.
- What would it replace, line for line, and what would it not cover that the home-grown one does on purpose? Read the comments and the decision records: "Syntax highlighting is one regex lexer engine" and "The clients' sessions have no URL cache" are deliberate.
- What a dependency costs here: the project has almost none (only the benchmarks package depends on anything), a license entry in `THIRD_PARTY_NOTICES`, Linux support, and Swift 6 strict-concurrency cleanliness. A finding that proposes one says why it is worth that.

## 5. Use of the language and the platform

- Concurrency: each escape hatch in the inventory (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `assumeIsolated`, locks, `DispatchQueue`). Is the reason written down, and does it still hold? An actor used only as a lock; hops onto the main actor and back; work on the main actor that could be `@concurrent`.
- Actor reentrancy: state read before an `await` and trusted after it (a cache entry, a "loading" flag, the current document), so two overlapping calls both act.
- Cancellation: a `Task` created in a view or model whose cancellation nobody handles; work that keeps running after its window, tab or document is gone (VISION: "a download the reader has walked away from is canceled").
- Default isolation: the app target is main-actor by default, so what runs on the main actor by accident? Parsing, decoding, file I/O or hashing reached from a main-actor method without an `@concurrent` hop.
- State: `@Observable` versus `ObservableObject`; who owns each piece of state; state duplicated between a model and a view; SwiftData used for what it is good at.
- Types: classes where values would do; `any` where `some` or a generic would; stringly-typed identifiers where the code has a type for them.
- Errors: `try?` and empty `catch` that swallow a failure the user or a log should see.
- Text: `NSString` and `String` bridging on hot paths, `NSRegularExpression` compiled in a loop, `String.Index` walks that are quadratic (#722 was one), `AttributedString` versus `NSAttributedString` where TextKit needs the latter.
- APIs the deployment target now offers that a workaround predates.

## 6. Workarounds and assumptions

- Every comment that cites an OS bug, an `FB` number, an SDK version or a measurement: does the reason still hold on the iOS/macOS 26 target? Is there a test that would fail if the workaround were removed? A workaround with no test and no stated way to check it is ossified.
- `git log -L` or `git blame` on the oldest workarounds: was the code around them rewritten since, so that the workaround guards nothing?
- Assumptions baked into constants or control flow: corpus counts (8,457, 9,842), RFC number ranges, ASCII-only text, 72 columns, the index's format, network availability, one window or one process, the cache directory's layout. Which would break silently if it changed, and which would fail loudly?
- Decisions whose stated premise has since changed (a measurement the code has outgrown, a platform limitation since lifted).

## 7. Performance

- The hot paths: index load and search at launch, document fetch and cache, parse, build, layout, highlighting, print. For each in your area: its complexity in the document's size, what it allocates, what actor it runs on, what it retains and for how long (kept builds, whole documents, attributed strings).
- Work done twice: parsed again, built again, measured again. Work done eagerly that only a few documents need.
- Memory: the peak and the steady state with several large documents open, what is kept per tab and per window, and whether anything gives memory back under pressure (`UIApplication.didReceiveMemoryWarningNotification`, `DispatchSource.makeMemoryPressureSource`, `NSCache`). iOS terminates an app that ignores pressure; the reader then loses its place.
- Launch: what runs before the first frame (index load, store open, migrations, data pack checks), and whether any of it could wait. A cold launch to a readable document is the number that matters.
- Scrolling and hangs: work on the main actor during scroll or layout (hitches), and anything synchronous on the main actor that can take over 250 ms on a large document (a hang the system reports).
- Energy and network: polling, timers, background refreshes, and downloads nobody is waiting for.
- Size: the app bundle and its data packs, and what of it every user downloads whether they need it or not.
- Measure where you can: `make benchmark` covers the index and document parsers, search and the builder; `make trace` records signposts (macOS only); Instruments' Allocations, Leaks, Hangs, Animation Hitches and App Launch templates cover the rest. Name the benchmark, signpost or template. Anything unmeasured is a hypothesis and says which measurement would settle it, or that one is missing.

## 8. Concentrations of complexity

- Functions with deep nesting, long `switch`es over the block or inline kinds, or long parameter lists. Is the switch repeated in several places, so that a new case must be added to all of them?
- Where do bugs land? `git log --grep` for issue numbers and "fix" against the file; comments that cite issues. A file most fixes touch is a hotspot whatever its size.
- Change amplification: for a realistic change (a new block kind, a new decoration, a new platform), which files must change? A change that has to be made in the same shape in many places is the finding; name the abstraction that would make it one place.
- Hidden coupling: index arithmetic shared between two sides of a boundary, attribute keys whose meaning is agreed by convention between the builder and the drawing code, ordering dependencies between steps.

## 9. Testability

- What in the area cannot be tested where it is, and why. Does it have to be there?
- Tests that pin implementation (private shapes, exact attribute runs) where they could pin behavior, and so make every refactor a test rewrite.
- Guards named in `CLAUDE.md` (`BuilderCompletenessTests`, `StorageInstallTests`, `BuilderHandoverTests`) that no longer cover what the rule says they guard.
- What catches a regression in the App target, which has no test bundle by design: no UI tests, no snapshot tests? Name the bugs of the last months (`git log`) that only a test of the running app would have caught, and what the cheapest such test would be.
- A migration test from every shipped schema version to the current one, with a store written by the old version, not built in memory.

## 10. Documentation against code

- A claim in `ARCHITECTURE.md` or a decision record that the code no longer bears out.
- A doc comment that describes what the function used to do.
- Documentation that has turned into a changelog or a bug list where it should describe the code as it is.

# Platform

## 11. Privacy, security and App Review

- A privacy manifest (`PrivacyInfo.xcprivacy`) in the app and in each package that ships in it, declaring every required-reason API the code uses: `UserDefaults`, file timestamps (`contentModificationDate`, `creationDate`, `attributesOfItem`), disk space, system boot time, active keyboards. A use with no declared reason is rejected at upload.
- Entitlements (`project.yml` generates them): each one used, none wider than needed; the sandbox on macOS; what network, file and user-selected access the app asks for and why.
- Untrusted input: every document, index and feed arrives from the network. External entities, entity expansion, nesting depth and document size in the XML parsers; regular expressions that backtrack on a hostile line; URLs and `rfc://` links from outside the app (`RFCLink`), App Intents parameters and AppleScript commands as entry points that must validate.
- What leaves the device: requests that reveal what the person reads, to whom, and whether `VISION.md`'s "never their reading history to us" holds in code (analytics, crash reporters, third-party hosts).
- Private API or undocumented behavior the app relies on (private subviews, KVC on underscored keys, selectors by name): a rejection risk and a break in the next OS.
- The licensing question `docs/DATA_PIPELINE.md` leaves open, as it bears on shipping data packs through the App Store.

## 12. Localization and internationalization

- Is the interface localizable at all? SwiftUI takes a literal in `Text("…")`, `Button("…")` and the like as a `LocalizedStringKey`, so those are ready once a String Catalog (`.xcstrings`) exists. What is not: a `String` variable passed to `Text` (shown verbatim), strings built by concatenation or interpolation of words, `Text(verbatim:)` on interface text, and AppKit and UIKit titles set from plain `String`s without `String(localized:)`.
- Plurals and counts through the catalog's plural variations, not `count == 1 ?`; dates, numbers, lists and byte sizes through `FormatStyle`, not fixed formats.
- Right-to-left: leading/trailing rather than left/right in layout and in TextKit paragraph styles; icons that should mirror. RFC text stays left-to-right; the chrome around it does not.
- Text in images, accessibility labels and App Intents phrases, which need localizing too.
- Assumptions about the locale: case mapping of keywords (Turkish dotted i), sorting with `<` on strings shown to people, search that ignores diacritics or does not.
- The cost now versus later: how many interface strings there are (the inventory counts them) and what a second language would take (a change scenario).

## 13. Accessibility

- VoiceOver beyond diagrams: every control labeled, traits correct, custom controls exposed as one element with an action, reading order through the sidebar, list, reader and inspector; rotors in the reader for headings and links as well as diagrams.
- Dynamic Type: interface fonts from text styles, not fixed sizes (the inventory lists fixed ones); the reader's own size setting and how it relates to the system's; layouts that survive the accessibility sizes without truncating or overlapping.
- Full Keyboard Access on macOS and iPadOS: every action reachable without a pointer, focus visible and in a sensible order, no keyboard trap.
- Contrast and color: semantic colors, Increase Contrast, color never the only carrier of meaning (status, requirement levels, syntax highlighting).
- Motion and transparency: Reduce Motion and Reduce Transparency honored where the app animates or uses materials.
- Voice Control: visible labels that match what a person would say.
- Assess with VoiceOver and the Accessibility Inspector's audit on a Mac; from code alone, mark it unassessed.

## 14. Lifecycle, data durability and resilience

- Scenes and restoration: on iOS, does the app come back where the person was after the system terminated it in the background (`@SceneStorage`, `NSUserActivity`, the reading position)? On macOS, window restoration and tabs. Handoff between devices, which `VISION.md` lists.
- iPad: multiple windows of the app, Split View and Slide Over, Stage Manager sizes, external displays; anything that assumes one scene.
- Termination mid-work: a download, a store write, a migration or a data pack install interrupted by the app being killed; what is left on disk, and does the next launch recover?
- Persistence: `SwiftData` schema versions and the migration plan between them; what happens on a store that fails to open (crash, silent reset, or a recovery the person is told about); whether the schema already fits CloudKit's rules (optional or defaulted attributes, no unique constraints, optional relationships) before sync is built.
- Where files live: caches in `Caches` (purgeable), user data in `Application Support`, downloaded packs excluded from backup; file coordination where another process (an extension, Spotlight) reads them.
- Network: offline, captive portals, slow and metered connections (`NWPathMonitor`, `isConstrained`, `isExpensive`), server errors and format changes from rfc-editor.org; does each fail to a state the person understands and can recover from?

## 15. Observability and release engineering

- When something goes wrong on someone's device, how would the developer know? `Logger` with subsystems and categories and privacy annotations versus `print`; signposts on the paths that matter; MetricKit for hangs, crashes, launch and memory in the field; diagnostics a person can attach to a bug report.
- Errors: failures that are logged nowhere and shown to nobody.
- Release: build settings for Release (optimization, dead-code stripping, assertions), code that branches on an SDK version CI does not build with, signing and notarization for the Mac, versioning of the app and of its data packs, and whether a build is reproducible from a tag.

# Experience

These lenses judge the app as someone using it. They need the running app; from code alone, every claim about what a screen shows or how it behaves is `unassessed: needs a Mac`. Hold the app to `VISION.md`'s principles and "What the experience should feel like", and to Apple's Human Interface Guidelines for each platform. Taste is not a finding: a deviation is one when it costs the person time, understanding, or a task.

## 16. Task flows

Walk each of these on every platform, counting steps and noting every place the person must already know something the interface does not say:

1. Open an RFC by number, and by a word of its title.
2. Follow a reference to another RFC, to a section, and to a figure; peek before committing; come back to exactly where you were.
3. See whether the document is current, obsoleted, updated, or has errata, and get to its successor.
4. Find a phrase in the document, and search across the index.
5. Bookmark a document, put it in a collection, find it again next week.
6. Read without a network: what is available, and does the app say so?
7. Copy a figure, a grammar, a citation, a link to a section; print or export.
8. Change the reading size, appearance and reading mode.
9. Use it the first time, with nothing downloaded.

For each: where did it stall, take more steps than the platform's own apps would, or lose the person's place?

## 17. Interface design and HIG fidelity

- Standard components and the system's look before custom ones: a custom control, color, material or animation where a system one exists costs accessibility, consistency and the next OS's design for free (the inventory lists custom controls and literal colors). On the 26 releases, does the chrome adopt the system's materials and toolbar and sidebar treatments, or fight them?
- Layout: hierarchy and alignment, sidebar and inspector widths, the reading column and its margins on every size class; nothing clipped, overlapping or truncated without a way to see the whole.
- Typography: system text styles in the chrome, a reading face and measure that suit long technical text, monospaced text that stays aligned.
- Icons: SF Symbols, used with their meaning (a symbol that means something else elsewhere in the system misleads); consistent weights and rendering modes.
- Light, dark and tinted appearances, Increase Contrast, the accent color.
- Motion: purposeful, interruptible, and gone with Reduce Motion.

## 18. Discoverability

- Every action reachable from somewhere visible: on macOS, the menu bar is where people look, so every command has a menu item in the standard menu (File, Edit, View, Go, Window, Help), with the standard shortcut where one exists; a feature reachable only by a gesture, a modifier-click, a long press or an unlabeled icon is hidden.
- Context menus and swipe actions on lists and links that offer what the toolbar does; force-click and hover previews with a menu equivalent.
- Tooltips (`.help`) on toolbar items and icon buttons on macOS; the iPad's keyboard shortcut overlay (holding ⌘) listing the app's commands.
- Features `VISION.md` and the decisions describe that someone would not find without being told: reading modes, backlink chips, reading paths, quick open, search syntax. Would TipKit, a menu item, a placeholder or an empty state teach them?
- Search syntax and filters: does the field tell the person what it accepts?
- The Help menu: is there help, and does it answer what the person cannot discover?

## 19. Per-device idiom and consistency

- macOS: real menu bar commands, keyboard shortcuts, windows and tabs, the Settings window, the inspector, drag and drop, Services, the toolbar's customization, full-screen, the responder chain for Edit commands (Copy, Find, Select All) reaching the reader.
- iPhone: navigation that suits one column, reachability, bars that hide while reading (the decision), sheets and their detents, swipe-back that works everywhere.
- iPad: the sidebar and the split view, the pointer, a hardware keyboard with the same shortcuts as the Mac, Pencil, multiple windows.
- Consistency: the same feature named, placed and behaving the same on each platform, unless the platform's convention differs. A feature present on one platform and missing on another without a reason is a finding (join it with its code cause in the cross-cutting pass).

## 20. States, feedback and writing

- Every view has its states: empty, loading, partial, error, offline, nothing found. Each says what happened and what to do next (`ContentUnavailableView`), and none leaves a blank screen or a spinner that never ends.
- Feedback: progress for anything over a second, confirmation of what an action did, errors in words a reader understands rather than a type name or an HTTP code.
- Undo for anything that removes or changes the person's data (bookmarks, collections, highlights, notes) via `UndoManager`, rather than a confirmation alert, and confirmation only where undo is impossible.
- Writing: labels and messages short, specific and consistent (one term for one thing across menus, toolbar, settings and errors), title-style capitalization on macOS menus and buttons per the HIG, no jargon from the code (`anchor`, `fragment`, `pack`) unless the person needs it.
- Settings: only what people actually need to change, with defaults that make most of them unnecessary.

---

## Finding schema

```markdown
### <AREA>-<n>. <the claim, in one line>

- **Severity**: high | medium | low
- **Confidence**: confirmed | likely | hypothesis (and what would settle it) | unassessed: needs a Mac — what to run
- **Lens**: one of the twenty above
- **Where**: `path:line`, every location; a screenshot path for what was seen in the running app, with the platform, device and appearance
- **Evidence**: what the code or the app shows, and the numbers, with where each came from (inventory, a command, a benchmark, an Instruments template, a walkthrough)
- **Effect**: what it makes harder, slower or riskier to change, with the change scenario or issue that shows it; or what someone using the app cannot do, cannot find, or does wrong, and who (VoiceOver, keyboard, iPhone, a first launch)
- **Alternative**: the specific structure, API, package or HIG pattern; where it is available (Linux, the 26 target, Swift 6); what it would and would not replace
- **Cost and risk of the change**: S | M | L; what could break; which tests guard it
- **Size**: one commit (a focused fix a few files wide) | project (needs design or several steps), with one line why
- **Conflicts**: the `CLAUDE.md` constraint, decision record or `VISION.md` principle it touches and how the finding answers its reasoning, or "none"
```

And, once per area:

```markdown
## Considered, not a finding

- `path:line` — what looked wrong; why it is deliberate (the record, comment or test that says so)
```
