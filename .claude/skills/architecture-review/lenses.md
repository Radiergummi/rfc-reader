# Lenses

Apply each lens to your area. The questions are prompts, not a form to fill in: report only what you found evidence for, and skip a lens with nothing to say. Where a question names a type or file, it is an example of where to look, not a finding.

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

- Concurrency: each escape hatch in the inventory (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `assumeIsolated`, locks, `DispatchQueue`). Is the reason written down, and does it still hold? An actor used only as a lock; hops onto the main actor and back; work on the main actor that could be `@concurrent`; a `Task` whose cancellation nobody handles.
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
- Measure where you can: `make benchmark` covers the index and document parsers, search and the builder; `make trace` records signposts (macOS only). Name the benchmark or signpost. Anything unmeasured is a hypothesis and says which benchmark would settle it, or that one is missing.

## 8. Concentrations of complexity

- Functions with deep nesting, long `switch`es over the block or inline kinds, or long parameter lists. Is the switch repeated in several places, so that a new case must be added to all of them?
- Where do bugs land? `git log --grep` for issue numbers and "fix" against the file; comments that cite issues. A file most fixes touch is a hotspot whatever its size.
- Change amplification: for a realistic change (a new block kind, a new decoration, a new platform), which files must change? A change that has to be made in the same shape in many places is the finding; name the abstraction that would make it one place.
- Hidden coupling: index arithmetic shared between two sides of a boundary, attribute keys whose meaning is agreed by convention between the builder and the drawing code, ordering dependencies between steps.

## 9. Testability

- What in the area cannot be tested where it is, and why. Does it have to be there?
- Tests that pin implementation (private shapes, exact attribute runs) where they could pin behavior, and so make every refactor a test rewrite.
- Guards named in `CLAUDE.md` (`BuilderCompletenessTests`, `StorageInstallTests`, `BuilderHandoverTests`) that no longer cover what the rule says they guard.

## 10. Documentation against code

- A claim in `ARCHITECTURE.md` or a decision record that the code no longer bears out.
- A doc comment that describes what the function used to do.
- Documentation that has turned into a changelog or a bug list where it should describe the code as it is.

---

## Finding schema

```markdown
### <AREA>-<n>. <the claim, in one line>

- **Severity**: high | medium | low
- **Confidence**: confirmed | likely | hypothesis (and what would settle it)
- **Lens**: one of the ten above
- **Where**: `path:line`, every location
- **Evidence**: what the code shows, and the numbers, with where each came from (inventory, a command, a benchmark)
- **Downstream effect**: what it makes harder, slower or riskier; the change scenario or issue that shows it
- **Alternative**: the specific structure, API or package; where it is available (Linux, the 26 target, Swift 6); what it would and would not replace
- **Cost and risk of the change**: S | M | L; what could break; which tests guard it
- **Conflicts**: the `CLAUDE.md` constraint or decision record it touches and how the finding answers its reasoning, or "none"
```

And, once per findings file:

```markdown
## Considered, not a finding

- `path:line` — what looked wrong; why it is deliberate (the record, comment or test that says so)
```
