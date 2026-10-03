# Syntax Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Highlight JSON, XML and HTTP message source blocks in the reader, on one shared regex lexer engine in RFCKit.

**Architecture:** RFCKit gains a `Lexer` engine (named states of ordered regex rules, each state compiled to one alternation) and three highlighters (JSON, XML, HTTP messages), all producing `[SyntaxToken]` with semantic `TokenKind`s that cover a block's text exactly once. RFCReaderKit registers a `SyntaxPresentation` in the existing artwork pipeline, which returns a new `Rendition.styled`; the builder colors each token from a static `SyntaxTheme.standard`, and a highlighted block stays outside the presentation choices and is not a figure. The licenses of the translated lexers are honored with a `THIRD_PARTY_NOTICES` file shown in the app.

**Tech Stack:** Swift 6.3 (strict concurrency), Foundation `NSRegularExpression` (ICU; corelibs on Linux), Swift Testing, TextKit 2 attributes, SwiftUI/AppKit for the acknowledgements UI, package-benchmark.

**Spec:** `docs/superpowers/specs/2026-10-02-syntax-highlighting-design.md`. Read it, and `CLAUDE.md`, before starting.

## Global Constraints

- RFCKit stays free of Apple-only APIs; it is tested on Linux. `NSRegularExpression`, `NSString` and `NSRange` are in corelibs Foundation and allowed.
- No RFC text is committed: tests use hand-written snippets in the shape of a format (guard-level) or documents read at run time through `CorpusText` from `RFC_CORPUS_XML`.
- Tests are Swift Testing, named with raw identifiers (``@Test func `a key is a name`()``).
- Corpus-backed suites are named `Corpus-backed: <topic>`, their type names start `CorpusBacked`, and every document they read is listed in the Makefile's `CORPUS_TEST_XML_DOCUMENTS`.
- `DocumentTextBuilder` is not main-actor bound; every attribute value it stores is immutable or made by that build.
- No hosted SwiftUI view and no attachment enters the reader body.
- American spelling in prose, identifiers and UI strings.
- swift-format defaults (`make fmt`); SwiftLint `--strict` clean (`make lint`); lines ≤ 200 characters.
- Highlighting is always on: no global switch, no per-block switch.
- Size cap: a block over 65,536 UTF-16 code units is not highlighted.
- Every token color reaches 4.5:1 against the verbatim card in light and dark.
- Commits are signed (the repo's git config does it; if signing fails because Secretive is locked, see the maintainer's GPG fallback) and end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Work on branch `syntax-highlighting`. Before every commit run `git branch --show-current` — another session may share the checkout.

## Review Focus

1. **A JSON string left open** (`{"a": "open` then more lines): the lines after it must still be highlighted, not swallowed as string. → Task 3.
2. **An XML attribute quote never closed, or a tag never closed** (`<a id="open` then `<b>`): the next element is still a tag. → Task 4.
3. **A `Content-Type` with parameters or a structured suffix** (`application/problem+json; charset=utf-8`): the body is lexed as JSON. → Task 5.
4. **Characters outside the BMP** (an emoji in a JSON string): token ranges are UTF-16 and land on the right characters. → Tasks 2 and 3.
5. **An empty or whitespace-only block**: no crash, and the tokens still cover it exactly. → Task 2.

---

## File Structure

**RFCKit** (`Packages/RFCKit/Sources/RFCKit/Highlighting/`, new directory):
- `SyntaxToken.swift` — `TokenKind`, `SyntaxToken`, `Highlighter` protocol, `TokenRun` (internal token accumulator).
- `Lexer.swift` — the engine: `Lexer`, `Lexer.Rule`, `Lexer.Transition`, `Lexer.DefinitionError`, `PatternShape`.
- `JSONLexer.swift` — JSON rule table.
- `XMLLexer.swift` — XML rule table.
- `HTTPMessageHighlighter.swift` — `HTTPLexer` (head rule table and start-line detection) and `HTTPMessageHighlighter` (message/head/body splitter).
- `Lexers.swift` — the registry: `Lexers.Language`, type → language, size cap, `highlight(_:as:)`.
- Modify `Document/ArtworkClassification.swift` — `ArtworkType.suffix`.

**RFCKit tests** (`Packages/RFCKit/Tests/RFCKitTests/`):
- `HighlightingSupport.swift`, `LexerTests.swift`, `JSONLexerTests.swift`, `XMLLexerTests.swift`, `HTTPMessageHighlighterTests.swift`, `LexersTests.swift`, `CorpusBackedHighlightingTests.swift`; modify `ArtworkClassifierTests.swift`.

**RFCReaderKit** (`Packages/RFCReaderKit/Sources/RFCReaderKit/`):
- Modify `Rendering/Renderers/Rendition.swift` — `Rendition.styled`, `StyledText`.
- Modify `Rendering/Renderers/ArtworkRenderers.swift` — `RendererEntry.suffixes`, suffix lookup, register `SyntaxPresentation.entry`.
- Create `Rendering/Renderers/SyntaxPresentation.swift`.
- Create `Rendering/SyntaxTheme.swift` — `SyntaxTheme`, `Contrast`.
- Modify `Rendering/Attributes.swift` — `VerbatimBox.Shown.highlighted`, `isFigure`.
- Modify `Rendering/DocumentTextBuilder+Verbatim.swift` — styled renditions.
- Modify `Rendering/AccessibleReading.swift` — a highlighted block is never a diagram.
- Create `Chrome/Acknowledgements.swift`.

**RFCReaderKit tests** (`Packages/RFCReaderKit/Tests/RFCReaderKitTests/`):
- Modify `Rendering/ArtworkRenderersTests.swift`; create `Rendering/SyntaxThemeTests.swift`, `Rendering/BuilderHighlightingTests.swift`, `Chrome/AcknowledgementsTests.swift`.

**App:** modify `App/RFCReader/RFCReaderApp.swift` (About panel credits), `App/RFCReader/Views/RFCListView.swift` (iOS menu item); create `App/RFCReader/Views/AcknowledgementsView.swift`.

**Elsewhere:** `THIRD_PARTY_NOTICES` (repo root), `Makefile`, `Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift`, `docs/decisions/2026-10-02-syntax-highlighting-is-one-regex-lexer-engine.md`, `docs/ARCHITECTURE.md`, `docs/VISION.md`, `docs/superpowers/specs/2026-09-30-artwork-renderers-design.md`, `docs/superpowers/specs/2026-10-02-syntax-highlighting-design.md`.

---

### Task 1: Builder benchmarks over code-heavy RFCs, and a baseline

The existing builder benchmarks (RFC 9110, 9000) have almost no highlighted blocks. Add RFC 8927 and RFC 8727 and record a baseline **before** any highlighting code exists.

**Files:**
- Modify: `Makefile` (the `BENCHMARK_INPUTS` line)
- Modify: `Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift` (the `Build: RFC` loop)

**Interfaces:**
- Produces: benchmarks named `Build: RFC 8927` and `Build: RFC 8727`, and a saved baseline named `before`.

- [ ] **Step 1: Add the inputs**

In `Makefile`, change

```make
BENCHMARK_INPUTS := rfc-index.xml rfc9110.xml rfc9000.xml rfc5661.txt rfc793.txt
```

to

```make
BENCHMARK_INPUTS := rfc-index.xml rfc9110.xml rfc9000.xml rfc8927.xml rfc8727.xml rfc5661.txt rfc793.txt
```

- [ ] **Step 2: Add the builds**

In `RFCBenchmarks.swift`, update the comment that lists the documents and the build loop:

```swift
  // The reader's column, 712 pt, as #357 measured the builds. RFC 8927 and RFC 8727
  // are mostly source code, so they are what syntax highlighting is measured on;
  // RFC 8727 holds the corpus's largest JSON block, 53 KB.
  let style = ReadingStyle(measure: ReaderLayout.idealMeasure)
  for number in [9110, 9000, 8927, 8727] {
```

(Leave the loop body as it is.)

- [ ] **Step 3: Record the baseline**

Run: `make benchmark BENCHMARK_ARGS='baseline update before --filter "Build.*"'`
Expected: it fetches the two new documents into `corpus/benchmarks/`, runs five `Build:` benchmarks and saves baseline `before`. Note the p50 wall-clock times of `Build: RFC 8927` and `Build: RFC 8727` for Task 11.

- [ ] **Step 4: Commit**

```bash
git branch --show-current   # syntax-highlighting
git add Makefile Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift
git commit -m "Benchmark the builds of RFC 8927 and RFC 8727, which are mostly code

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The lexer engine

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/SyntaxToken.swift`
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/Lexer.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/HighlightingSupport.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/LexerTests.swift`

**Interfaces:**
- Produces:
  - `public enum TokenKind: Sendable, Hashable, CaseIterable { case keyword, string, number, comment, name, attribute, punctuation, plain }`
  - `public struct SyntaxToken: Sendable, Hashable { public var range: NSRange; public var kind: TokenKind }`
  - `public protocol Highlighter: Sendable { func tokens(in text: String) -> [SyntaxToken] }`
  - `struct TokenRun { var tokens: [SyntaxToken]; mutating func append(_: NSRange, _: TokenKind); mutating func append(contentsOf: [SyntaxToken], offset: Int) }`
  - `public struct Lexer: Highlighter` with `init(states: [String: [Rule]], options: NSRegularExpression.Options = []) throws(DefinitionError)`, `static func defined(_ states: [String: [Rule]], options: NSRegularExpression.Options = []) -> Lexer`, `static func expression(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression`
  - `Lexer.Rule(_ pattern: String, _ kind: TokenKind, _ transition: Transition? = nil)`, `Lexer.Rule(_ pattern: String, groups: [TokenKind], _ transition: Transition? = nil)`
  - `Lexer.Transition`: `.push(String)`, `.pop(Int)`
  - Test helpers: `[SyntaxToken].cover(_ text: String) -> Bool`, `[SyntaxToken].kind(of fragment: String, in text: String) -> TokenKind?`, `[SyntaxToken].text(of kind: TokenKind, in text: String) -> [String]`

- [ ] **Step 1: Write the test helpers**

`Packages/RFCKit/Tests/RFCKitTests/HighlightingSupport.swift`:

```swift
import Foundation

@testable import RFCKit

extension Array where Element == SyntaxToken {
  /// Whether these tokens cover `text` exactly once, in order, with no empty token:
  /// the invariant every highlighter keeps.
  func cover(_ text: String) -> Bool {
    var position = 0
    for token in self {
      guard token.range.location == position, token.range.length > 0 else { return false }
      position = NSMaxRange(token.range)
    }
    return position == NSString(string: text).length
  }

  /// The kind of the one token that holds all of the first occurrence of `fragment`
  /// in `text`, or nil where no single token does.
  func kind(of fragment: String, in text: String) -> TokenKind? {
    let range = NSString(string: text).range(of: fragment)
    guard range.location != NSNotFound else { return nil }
    return first {
      $0.range.location <= range.location && NSMaxRange(range) <= NSMaxRange($0.range)
    }?.kind
  }

  /// The text of every token of `kind`, in order.
  func text(of kind: TokenKind, in text: String) -> [String] {
    let source = NSString(string: text)
    return filter { $0.kind == kind }.map { source.substring(with: $0.range) }
  }
}
```

- [ ] **Step 2: Write the failing engine tests**

`Packages/RFCKit/Tests/RFCKitTests/LexerTests.swift`. The lexers here are made up for the test; they are not any language.

```swift
import Foundation
import Testing

@testable import RFCKit

/// The engine's semantics, on lexers made up to show one rule each.
@Suite("Highlighting: the lexer engine")
struct LexerTests {
  private func lexer(
    _ states: [String: [Lexer.Rule]], options: NSRegularExpression.Options = []
  ) throws -> Lexer {
    try Lexer(states: states, options: options)
  }

  private let words: [String: [Lexer.Rule]] = [
    "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule("[0-9]++", .number)]
  ]

  @Test func `tokens cover the text exactly once`() throws {
    let text = "abc 12 de"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["abc", "de"])
    #expect(tokens.text(of: .number, in: text) == ["12"])
  }

  @Test func `what no rule matches is plain`() throws {
    let text = "abc ?! de"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .plain, in: text) == [" ?! "])
  }

  @Test func `an empty text has no tokens`() throws {
    #expect(try lexer(words).tokens(in: "").isEmpty)
  }

  @Test func `white space alone is covered as plain`() throws {
    let text = " \n\t "
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.allSatisfy { $0.kind == .plain })
  }

  @Test func `ranges are UTF-16 and land on the right characters`() throws {
    let text = "ab😀cd"
    let tokens = try lexer(words).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["ab", "cd"])
    #expect(tokens.text(of: .plain, in: text) == ["😀"])
  }

  @Test func `a push enters a state and a pop leaves it`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\("#, .punctuation, .push("inner"))],
      "inner": [Lexer.Rule("[a-z]++", .keyword), Lexer.Rule(#"\)"#, .punctuation, .pop(1))],
    ]
    let text = "a(b)c"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["a", "c"])
    #expect(tokens.text(of: .keyword, in: text) == ["b"])
  }

  @Test func `a pop deeper than the stack stops at the root`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\)"#, .punctuation, .pop(3))]
    ]
    let text = ")a"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "a", in: text) == .name)
  }

  @Test func `a pop of two leaves two states`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\{"#, .punctuation, .push("one"))],
      "one": [Lexer.Rule(#"\["#, .punctuation, .push("two"))],
      "two": [Lexer.Rule(#"\}"#, .punctuation, .pop(2)), Lexer.Rule("[a-z]++", .keyword)],
    ]
    let text = "{[x}y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.kind(of: "x", in: text) == .keyword)
    #expect(tokens.kind(of: "y", in: text) == .name)
  }

  @Test func `groups take their kinds and the rest of the match is plain`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule(#"([a-z]++)=([a-z]++);"#, groups: [.name, .string])]
    ]
    let text = "key=value;"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["key"])
    #expect(tokens.text(of: .string, in: text) == ["value"])
    #expect(tokens.text(of: .plain, in: text) == ["=", ";"])
  }

  @Test func `a lookbehind sees the characters before the match`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [
        Lexer.Rule("(?<=@)[a-z]++", .keyword), Lexer.Rule("@", .punctuation),
        Lexer.Rule("[a-z]++", .name),
      ]
    ]
    let text = "a@b"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.kind(of: "b", in: text) == .keyword)
  }

  @Test func `a caret matches only at the start of a line`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [
        Lexer.Rule("^#[^\n]*+", .comment), Lexer.Rule("#", .punctuation),
        Lexer.Rule("[a-z]++", .name),
      ]
    ]
    let text = "a #x\n#y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .comment, in: text) == ["#y"])
  }

  /// A state that has lost its place, as an unclosed tag has, gives up at the next
  /// newline after a character it could not match, so the next line is read from the
  /// root, as Pygments recovers.
  @Test func `after an unmatched character the next newline returns to the root`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .keyword), Lexer.Rule("<", .punctuation, .push("tag"))],
      "tag": [
        Lexer.Rule("[a-z]++", .name), Lexer.Rule(#"\s++"#, .plain),
        Lexer.Rule(">", .punctuation, .pop(1)),
      ],
    ]
    let text = "<a ! \nb"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "a", in: text) == .name)
    #expect(tokens.kind(of: "b", in: text) == .keyword)
  }

  @Test func `a lookahead may change state without consuming`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("[a-z]++", .plain), Lexer.Rule("(?=<)", .plain, .push("tag"))],
      "tag": [Lexer.Rule("<[a-z]++", .name), Lexer.Rule(">", .name, .pop(1))],
    ]
    let text = "x<a>y"
    let tokens = try lexer(states).tokens(in: text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["<a>"])
  }

  @Test func `states that only trade places cannot loop forever`() throws {
    let states: [String: [Lexer.Rule]] = [
      "root": [Lexer.Rule("(?=a)", .plain, .push("other"))],
      "other": [Lexer.Rule("(?=a)", .plain, .pop(1))],
    ]
    let text = "aa"
    #expect(try lexer(states).tokens(in: text).cover(text))
  }

  @Test func `a definition without a root state is refused`() {
    #expect(throws: Lexer.DefinitionError.noRootState) {
      try lexer(["other": [Lexer.Rule("a", .name)]])
    }
  }

  @Test func `a push to a state that does not exist is refused`() {
    #expect(throws: Lexer.DefinitionError.unknownState("missing")) {
      try lexer(["root": [Lexer.Rule("a", .name, .push("missing"))]])
    }
  }

  @Test func `a pattern that does not compile is refused`() {
    #expect(throws: Lexer.DefinitionError.invalidPattern("(")) {
      try lexer(["root": [Lexer.Rule("(", .name)]])
    }
  }

  @Test func `kinds for groups must match the groups`() {
    #expect(throws: Lexer.DefinitionError.groupCountMismatch("(a)(b)")) {
      try lexer(["root": [Lexer.Rule("(a)(b)", groups: [.name])]])
    }
  }

  @Test func `nested groups are refused`() {
    #expect(throws: Lexer.DefinitionError.nestedGroups("((a)b)")) {
      try lexer(["root": [Lexer.Rule("((a)b)", groups: [.name, .string])]])
    }
  }

  /// Each state is compiled to one alternation, which renumbers the groups.
  @Test func `a backreference is refused`() {
    #expect(throws: Lexer.DefinitionError.backreference(#"(a)\1"#)) {
      try lexer(["root": [Lexer.Rule(#"(a)\1"#, groups: [.name])]])
    }
  }

  @Test func `a rule that can match nothing must change state`() {
    #expect(throws: Lexer.DefinitionError.matchesEmptyWithoutTransition("a*")) {
      try lexer(["root": [Lexer.Rule("a*", .name)]])
    }
  }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter LexerTests`
Expected: build failure — `cannot find 'Lexer' in scope`.

- [ ] **Step 4: Write the token types**

`Packages/RFCKit/Sources/RFCKit/Highlighting/SyntaxToken.swift`:

```swift
import Foundation

/// What a token is, never how it looks: the reader's theme decides that.
public enum TokenKind: Sendable, Hashable, CaseIterable {
  case keyword
  case string
  case number
  case comment
  /// A JSON key, an XML tag, an HTTP field name.
  case name
  case attribute
  case punctuation
  case plain
}

/// A run of a block's text and what it is. The range is UTF-16, relative to the
/// text highlighted, as `NSAttributedString` counts.
public struct SyntaxToken: Sendable, Hashable {
  public var range: NSRange
  public var kind: TokenKind

  public init(range: NSRange, kind: TokenKind) {
    self.range = range
    self.kind = kind
  }
}

/// Turns a block's text into tokens that cover it exactly once, in order, with no
/// empty token. Never fails: what it cannot read is `plain`.
public protocol Highlighter: Sendable {
  func tokens(in text: String) -> [SyntaxToken]
}

/// Tokens as a highlighter collects them: empty runs are dropped and a run that
/// continues the one before it, of the same kind, is merged into it, so a block has
/// as few attribute runs as its colors need.
struct TokenRun {
  private(set) var tokens: [SyntaxToken] = []

  mutating func append(_ range: NSRange, _ kind: TokenKind) {
    guard range.length > 0 else { return }
    if let last = tokens.last, last.kind == kind, NSMaxRange(last.range) == range.location {
      tokens[tokens.count - 1].range.length += range.length
    } else {
      tokens.append(SyntaxToken(range: range, kind: kind))
    }
  }

  /// `other`'s tokens, moved `offset` code units on: a part of the text highlighted
  /// on its own, such as an HTTP message's body.
  mutating func append(contentsOf other: [SyntaxToken], offset: Int) {
    for token in other {
      append(NSRange(location: token.range.location + offset, length: token.range.length), token.kind)
    }
  }
}
```

- [ ] **Step 5: Write the engine**

`Packages/RFCKit/Sources/RFCKit/Highlighting/Lexer.swift`:

```swift
import Foundation

/// A regex state machine, as Pygments, Rouge and Chroma lex: named states, each an
/// ordered list of rules, starting in `root`. At each point the first rule of the
/// current state that matches there wins; it emits its kind, or a kind per capture
/// group, and may push a state or pop some.
///
/// Each state is compiled to one alternation, `(rule0)|(rule1)|…`, and searched
/// forward from the current position, so one search finds the next token and the
/// characters before it, which no rule matched. Those are `plain`, and lexing goes
/// on: the engine never fails, and a fragment — most of the code in RFCs — costs
/// nothing. A state other than the root that meets a character it cannot match has
/// lost its place, and at the next newline lexing starts again from the root, as
/// Pygments recovers, so one stray quote does not color the rest of a block.
///
/// Matching uses transparent and non-anchoring bounds, so a lookbehind or `\b` sees
/// the characters before the current position, and `^` matches only where a line
/// starts. Patterns compile with `anchorsMatchLines`, as Pygments' and Chroma's do.
public struct Lexer: Highlighter {
  public enum Transition: Sendable, Hashable {
    case push(String)
    /// Leaves this many states, never the root.
    case pop(Int)
  }

  public struct Rule: Sendable {
    public enum Emit: Sendable, Hashable {
      case kind(TokenKind)
      /// One kind per capture group, in order. Characters of the match outside
      /// every group are plain, and a group that matched nothing emits nothing.
      case groups([TokenKind])
    }

    public let pattern: String
    public let emit: Emit
    public let transition: Transition?

    public init(_ pattern: String, _ kind: TokenKind, _ transition: Transition? = nil) {
      self.pattern = pattern
      self.emit = .kind(kind)
      self.transition = transition
    }

    public init(_ pattern: String, groups: [TokenKind], _ transition: Transition? = nil) {
      self.pattern = pattern
      self.emit = .groups(groups)
      self.transition = transition
    }
  }

  public enum DefinitionError: Error, Hashable {
    case noRootState
    case unknownState(String)
    case invalidPattern(String)
    case groupCountMismatch(String)
    case nestedGroups(String)
    /// A state's rules are compiled into one alternation, which renumbers groups.
    case backreference(String)
    /// It could match nothing and stay where it is, forever.
    case matchesEmptyWithoutTransition(String)
  }

  /// A state, compiled: rule `i` is the capture group `groups[i]`, and its own
  /// groups follow it.
  struct CompiledState {
    let expression: NSRegularExpression
    let rules: [Rule]
    let groups: [Int]

    func rule(matching match: NSTextCheckingResult) -> (rule: Rule, group: Int)? {
      for (index, rule) in rules.enumerated()
      where match.range(at: groups[index]).location != NSNotFound {
        return (rule, groups[index])
      }
      return nil
    }
  }

  private let states: [String: CompiledState]
  private let root: CompiledState

  static let matching: NSRegularExpression.MatchingOptions = [
    .withTransparentBounds, .withoutAnchoringBounds,
  ]

  /// How many rules in a row may match nothing and only change state before a
  /// character is given up as plain: two states that hand over to each other on a
  /// lookahead would otherwise trade places forever.
  static let emptyStepLimit = 8

  public init(
    states definitions: [String: [Rule]], options: NSRegularExpression.Options = []
  ) throws(DefinitionError) {
    let options = options.union(.anchorsMatchLines)
    var compiled: [String: CompiledState] = [:]
    for (name, rules) in definitions {
      var groups: [Int] = []
      var next = 1
      for rule in rules {
        groups.append(next)
        next += 1 + (try Self.validate(rule, options: options, states: definitions))
      }
      let alternation = rules.map { "(\($0.pattern))" }.joined(separator: "|")
      let expression: NSRegularExpression
      do {
        expression = try NSRegularExpression(pattern: alternation, options: options)
      } catch {
        throw .invalidPattern(alternation)
      }
      compiled[name] = CompiledState(expression: expression, rules: rules, groups: groups)
    }
    guard let root = compiled["root"] else { throw .noRootState }
    self.states = compiled
    self.root = root
  }

  /// A lexer whose definition is part of the program: a definition error is a
  /// programmer's error, and the test that builds every lexer reports it with its
  /// reason first.
  static func defined(
    _ states: [String: [Rule]], options: NSRegularExpression.Options = []
  ) -> Lexer {
    do {
      return try Lexer(states: states, options: options)
    } catch {
      preconditionFailure("a lexer's definition is invalid: \(error)")
    }
  }

  /// A pattern that is part of the program, compiled once.
  static func expression(
    _ pattern: String, options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      preconditionFailure("\(pattern) does not compile: \(error)")
    }
  }

  /// Checks one rule, and returns how many capture groups it has.
  private static func validate(
    _ rule: Rule, options: NSRegularExpression.Options, states: [String: [Rule]]
  ) throws(DefinitionError) -> Int {
    let expression: NSRegularExpression
    do {
      expression = try NSRegularExpression(pattern: rule.pattern, options: options)
    } catch {
      throw .invalidPattern(rule.pattern)
    }
    if case .push(let target)? = rule.transition, states[target] == nil {
      throw .unknownState(target)
    }
    let shape = PatternShape(rule.pattern)
    if case .groups(let kinds) = rule.emit {
      guard kinds.count == expression.numberOfCaptureGroups else {
        throw .groupCountMismatch(rule.pattern)
      }
      if shape.hasNestedCaptureGroups { throw .nestedGroups(rule.pattern) }
    }
    if shape.hasBackreference { throw .backreference(rule.pattern) }
    let nothing = expression.firstMatch(in: "", range: NSRange(location: 0, length: 0))
    if rule.transition == nil, nothing != nil {
      throw .matchesEmptyWithoutTransition(rule.pattern)
    }
    return expression.numberOfCaptureGroups
  }

  public func tokens(in text: String) -> [SyntaxToken] {
    let source = NSString(string: text)
    let length = source.length
    var output = TokenRun()
    var stack = ["root"]
    var position = 0
    var recovering = false
    var emptySteps = 0
    while position < length {
      let state = states[stack[stack.count - 1]] ?? root
      let match = state.expression.firstMatch(
        in: text, options: Self.matching,
        range: NSRange(location: position, length: length - position))
      let found = match?.range.location ?? length
      if found > position {
        // No rule matched these: plain. Inside a state, the state has lost its
        // place, and at a newline among them lexing starts again from the root.
        var gap = NSRange(location: position, length: found - position)
        if stack.count > 1 {
          recovering = true
          let newline = source.range(of: "\n", options: .literal, range: gap)
          if newline.location != NSNotFound {
            gap.length = NSMaxRange(newline) - position
            stack = ["root"]
            recovering = false
          }
        }
        output.append(gap, .plain)
        position = NSMaxRange(gap)
        emptySteps = 0
        if position < found { continue }
      }
      guard let match, let matched = state.rule(matching: match) else { break }
      if match.range.length == 0,
        matched.rule.transition == nil || emptySteps >= Self.emptyStepLimit
      {
        // Nothing can move lexing on here: one character is plain.
        let character = source.rangeOfComposedCharacterSequence(at: position)
        output.append(character, .plain)
        position = NSMaxRange(character)
        emptySteps = 0
        if stack.count > 1 { recovering = true }
        continue
      }
      Self.emit(match, rule: matched.rule, group: matched.group, into: &output)
      if let transition = matched.rule.transition {
        Self.apply(transition, to: &stack)
      }
      emptySteps = match.range.length == 0 ? emptySteps + 1 : 0
      position = NSMaxRange(match.range)
      if stack.count == 1 {
        recovering = false
      } else if recovering,
        source.range(of: "\n", options: .literal, range: match.range).location != NSNotFound
      {
        stack = ["root"]
        recovering = false
      }
    }
    return output.tokens
  }

  private static func emit(
    _ match: NSTextCheckingResult, rule: Rule, group: Int, into output: inout TokenRun
  ) {
    switch rule.emit {
    case .kind(let kind):
      output.append(match.range, kind)
    case .groups(let kinds):
      var cursor = match.range.location
      for (index, kind) in kinds.enumerated() {
        let range = match.range(at: group + 1 + index)
        // A group that matched nothing, or one inside a lookaround that reaches
        // outside the match, covers none of the match's characters.
        guard range.location != NSNotFound, range.location >= cursor,
          NSMaxRange(range) <= NSMaxRange(match.range)
        else { continue }
        output.append(NSRange(location: cursor, length: range.location - cursor), .plain)
        output.append(range, kind)
        cursor = NSMaxRange(range)
      }
      output.append(
        NSRange(location: cursor, length: NSMaxRange(match.range) - cursor), .plain)
    }
  }

  private static func apply(_ transition: Transition, to stack: inout [String]) {
    switch transition {
    case .push(let state):
      stack.append(state)
    case .pop(let depth):
      stack.removeLast(min(max(depth, 0), stack.count - 1))
    }
  }
}

/// What a rule's pattern is made of, as far as the engine depends on it, read by
/// hand because `NSRegularExpression` does not say: whether a capture group is
/// nested in another, which `Rule.Emit.groups` cannot attribute, and whether it
/// refers back to a group by number, which the alternation renumbers.
struct PatternShape {
  private(set) var hasNestedCaptureGroups = false
  private(set) var hasBackreference = false

  init(_ pattern: String) {
    let characters = Array(pattern)
    var open: [Bool] = []  // whether each open group captures
    var inClass = false
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\\" {
        if !inClass, index + 1 < characters.count, let digit = characters[index + 1].wholeNumberValue,
          digit > 0
        {
          hasBackreference = true
        }
        index += 2
        continue
      }
      if inClass {
        if character == "]" { inClass = false }
      } else if character == "[" {
        inClass = true
      } else if character == "(" {
        let captures = !(index + 1 < characters.count && characters[index + 1] == "?")
        if captures, open.contains(true) { hasNestedCaptureGroups = true }
        open.append(captures)
      } else if character == ")" {
        _ = open.popLast()
      }
      index += 1
    }
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Packages/RFCKit --filter LexerTests`
Expected: PASS, every test.

If the compiler reports that `NSRegularExpression` is not `Sendable` (so `Lexer` cannot conform to `Highlighter: Sendable`), wrap it once, in `Lexer.swift`, the way `Pattern.swift` wraps `Regex`, and say why in its comment:

```swift
/// `NSRegularExpression` is immutable once compiled and documented as safe to match
/// from any number of threads; where an SDK does not mark it `Sendable`, this says so
/// once.
struct CompiledExpression: @unchecked Sendable {
  let expression: NSRegularExpression
}
```

and store `CompiledExpression` in `CompiledState`. Do not add it if the compiler does not ask for it.

- [ ] **Step 7: Check Linux, where the docker CLI is available**

Run: `docker run --rm -v "$PWD":/src -w /src swift:6.3 swift build --package-path Packages/RFCKit`
Expected: builds without a concurrency error. RFCKit used only Swift `Regex` until now, so this is the first use of corelibs' `NSRegularExpression` under strict concurrency. If docker is not available, say so in the task report; CI checks it on the pull request.

- [ ] **Step 8: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current   # syntax-highlighting
git add Packages/RFCKit/Sources/RFCKit/Highlighting Packages/RFCKit/Tests/RFCKitTests/HighlightingSupport.swift Packages/RFCKit/Tests/RFCKitTests/LexerTests.swift
git commit -m "A regex lexer engine for highlighting code, in RFCKit

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The JSON lexer

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/JSONLexer.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/JSONLexerTests.swift`

**Interfaces:**
- Consumes: `Lexer`, `Lexer.Rule`, `Lexer.defined` (Task 2).
- Produces: `enum JSONLexer { static let states: [String: [Lexer.Rule]]; static let lexer: Lexer }`

- [ ] **Step 1: Write the failing tests**

`Packages/RFCKit/Tests/RFCKitTests/JSONLexerTests.swift` (the snippets are hand-written in JSON's shape):

```swift
import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: JSON")
struct JSONLexerTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    JSONLexer.lexer.tokens(in: text)
  }

  @Test func `a key is a name and its value a string`() {
    let text = #"{"title": "Example", "count": 3, "open": true, "none": null}"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .name)
    #expect(tokens.kind(of: #""Example""#, in: text) == .string)
    #expect(tokens.kind(of: "3", in: text) == .number)
    #expect(tokens.kind(of: "true", in: text) == .keyword)
    #expect(tokens.kind(of: "null", in: text) == .keyword)
    #expect(tokens.kind(of: "{", in: text) == .punctuation)
    #expect(tokens.kind(of: ":", in: text) == .punctuation)
  }

  @Test func `members without their object are still keys and values`() {
    let text = "\"alg\": \"ES256\",\n\"kid\": \"k1\""
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == [#""alg""#, #""kid""#])
    #expect(tokens.text(of: .string, in: text) == [#""ES256""#, #""k1""#])
  }

  @Test func `a key whose colon is on the next line is a name`() {
    let text = "{\"key\"\n  : 1}"
    #expect(tokens(text).kind(of: #""key""#, in: text) == .name)
  }

  @Test func `an escaped quote does not end a string`() {
    let text = #"["say \"hi\"", 1]"#
    let tokens = tokens(text)
    #expect(tokens.text(of: .string, in: text) == [#""say \"hi\"""#])
  }

  @Test func `numbers in every form are one token`() {
    let text = "[-0.5e+10, 0, 12, 3.25, 1E3]"
    let tokens = tokens(text)
    #expect(tokens.text(of: .number, in: text) == ["-0.5e+10", "0", "12", "3.25", "1E3"])
  }

  @Test func `an elision is set apart and what follows it is still read`() {
    let text = "{\n  \"a\": 1,\n  ...\n  \"b\": 2\n}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "...", in: text) == .comment)
    #expect(tokens.kind(of: #""b""#, in: text) == .name)
  }

  /// Review focus 1: a string left open ends at its line, as JSON's strings do.
  @Test func `a string left open does not swallow the lines after it`() {
    let text = "{\"a\": \"open\n  \"b\": 2}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""b""#, in: text) == .name)
    #expect(tokens.kind(of: "2", in: text) == .number)
    #expect(tokens.text(of: .string, in: text).allSatisfy { !$0.contains("\n") })
  }

  /// Review focus 4.
  @Test func `a character outside the BMP keeps the ranges after it right`() {
    let text = #"{"emoji": "😀", "next": 1}"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""😀""#, in: text) == .string)
    #expect(tokens.kind(of: #""next""#, in: text) == .name)
  }

  @Test func `a long string left open is lexed in bounded time`() {
    let text = "\"" + String(repeating: "a", count: 20_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }

  @Test func `deeply nested brackets are lexed in bounded time`() {
    let text = String(repeating: "{[", count: 10_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter JSONLexerTests`
Expected: build failure — `cannot find 'JSONLexer' in scope`.

- [ ] **Step 3: Fetch the source and write the lexer**

Look at the upstream table this adapts (do not copy it into the repo):
`gh api 'repos/alecthomas/chroma/contents/lexers/embedded/json.xml?ref=e4159240b179' --jq .content | base64 -d`

`Packages/RFCKit/Sources/RFCKit/Highlighting/JSONLexer.swift`:

```swift
import Foundation

/// JSON as RFCs set it: often a fragment — members without their object, an array's
/// elements — and elided with `...`.
///
/// Adapted from Chroma's `lexers/embedded/json.xml` (github.com/alecthomas/chroma,
/// commit e4159240b179, MIT License), itself converted from Pygments' JSON lexer
/// (BSD 2-Clause License); both notices are in THIRD_PARTY_NOTICES. Chroma's states
/// follow objects and arrays, and lose their place in a fragment; here a key is told
/// by the colon after it, so one state reads a fragment as well as a document.
/// Strings end at their line, as JSON's do, so one left open colors nothing after
/// it, and every repetition is possessive, so none can backtrack.
enum JSONLexer {
  static let states: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#"//[^\n]*+"#, .comment),
      Lexer.Rule(#""(?:[^"\\\n]++|\\.)*+"(?=\s*+:)"#, .name),
      Lexer.Rule(#""(?:[^"\\\n]++|\\.)*+""#, .string),
      Lexer.Rule(#"-?(?:0|[1-9][0-9]*+)(?:\.[0-9]++)?(?:[eE][+-]?[0-9]++)?"#, .number),
      Lexer.Rule(#"(?:true|false|null)\b"#, .keyword),
      Lexer.Rule(#"\.\.\.|…"#, .comment),
      Lexer.Rule(#"[{}\[\],:]"#, .punctuation),
    ]
  ]

  static let lexer = Lexer.defined(states)
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/RFCKit --filter JSONLexerTests`
Expected: PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Packages/RFCKit/Sources/RFCKit/Highlighting/JSONLexer.swift Packages/RFCKit/Tests/RFCKitTests/JSONLexerTests.swift
git commit -m "A JSON lexer that reads fragments and elisions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The XML lexer

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/XMLLexer.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/XMLLexerTests.swift`

**Interfaces:**
- Consumes: `Lexer` (Task 2).
- Produces: `enum XMLLexer { static let states: [String: [Lexer.Rule]]; static let options: NSRegularExpression.Options; static let lexer: Lexer }`

- [ ] **Step 1: Write the failing tests**

`Packages/RFCKit/Tests/RFCKitTests/XMLLexerTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: XML")
struct XMLLexerTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    XMLLexer.lexer.tokens(in: text)
  }

  @Test func `tags are names, attributes attributes, and values strings`() {
    let text = #"<entry id="e1" lang='en'>text &amp; more</entry>"#
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "<entry", in: text) == .name)
    #expect(tokens.kind(of: "id", in: text) == .attribute)
    #expect(tokens.kind(of: #""e1""#, in: text) == .string)
    #expect(tokens.kind(of: "'en'", in: text) == .string)
    #expect(tokens.kind(of: "text", in: text) == .plain)
    #expect(tokens.kind(of: "&amp;", in: text) == .keyword)
    #expect(tokens.kind(of: "</entry>", in: text) == .name)
  }

  @Test func `a comment runs across lines to its end`() {
    let text = "<!-- one\n two -->\n<a/>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .comment, in: text) == ["<!-- one\n two -->"])
    #expect(tokens.kind(of: "<a", in: text) == .name)
  }

  @Test func `a declaration and an instruction are keywords`() {
    let text = "<?xml version=\"1.0\"?>\n<!DOCTYPE note>\n<note/>"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "<?xml version=\"1.0\"?>", in: text) == .keyword)
    #expect(tokens.kind(of: "<!DOCTYPE note>", in: text) == .keyword)
  }

  @Test func `an elision between elements is text`() {
    let text = "<list>\n  <item/>\n  ...\n</list>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "</list>", in: text) == .name)
  }

  /// Review focus 2.
  @Test func `a quote never closed does not swallow the next element`() {
    let text = "<a id=\"open\n<b>x</b>"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "<b", in: text) == .name)
    #expect(tokens.kind(of: "</b>", in: text) == .name)
  }

  /// Review focus 2.
  @Test func `a tag never closed does not swallow the next element`() {
    let text = "<a href=x\n<b>y</b>"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "<b", in: text) == .name)
  }

  @Test func `many opening brackets are lexed in bounded time`() {
    let text = String(repeating: "<", count: 20_000)
    let elapsed = ContinuousClock().measure { #expect(tokens(text).cover(text)) }
    #expect(elapsed < .seconds(2))
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter XMLLexerTests`
Expected: build failure — `cannot find 'XMLLexer' in scope`.

- [ ] **Step 3: Write the lexer**

Upstream for reference: `gh api 'repos/alecthomas/chroma/contents/lexers/embedded/xml.xml?ref=e4159240b179' --jq .content | base64 -d`

`Packages/RFCKit/Sources/RFCKit/Highlighting/XMLLexer.swift`:

```swift
import Foundation

/// XML as RFCs set it: instances, often fragments with elided elements.
///
/// Translated from Chroma's `lexers/embedded/xml.xml` (github.com/alecthomas/chroma,
/// commit e4159240b179, MIT License), itself converted from Pygments' XML lexer
/// (BSD 2-Clause License); both notices are in THIRD_PARTY_NOTICES. Changed from it:
/// an attribute's `=` is punctuation; a quoted value ends at its line, so a quote
/// left open colors nothing after it; a `<` inside a tag or before a value means the
/// tag was never closed, and leaves it; repetitions are possessive where that does
/// not change what matches.
enum XMLLexer {
  static let options: NSRegularExpression.Options = [.dotMatchesLineSeparators]

  static let states: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(#"[^<&]++"#, .plain),
      Lexer.Rule(#"&[^\s;<&]*+;"#, .keyword),
      Lexer.Rule(#"<!\[CDATA\[.*?\]\]>"#, .keyword),
      Lexer.Rule(#"<!--"#, .comment, .push("comment")),
      Lexer.Rule(#"<\?.*?\?>"#, .keyword),
      Lexer.Rule(#"<![^>]*+>"#, .keyword),
      Lexer.Rule(#"<\s*+[\w:.-]++"#, .name, .push("tag")),
      Lexer.Rule(#"<\s*+/\s*+[\w:.-]++\s*+>"#, .name),
    ],
    "comment": [
      Lexer.Rule(#"[^-]++"#, .comment),
      Lexer.Rule(#"-->"#, .comment, .pop(1)),
      Lexer.Rule(#"-"#, .comment),
    ],
    "tag": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#"([\w.:-]++)(\s*+=)"#, groups: [.attribute, .punctuation], .push("value")),
      Lexer.Rule(#"/?\s*+>"#, .name, .pop(1)),
      Lexer.Rule(#"(?=<)"#, .plain, .pop(1)),
    ],
    "value": [
      Lexer.Rule(#"\s++"#, .plain),
      Lexer.Rule(#""[^"\n]*+""#, .string, .pop(1)),
      Lexer.Rule(#"'[^'\n]*+'"#, .string, .pop(1)),
      Lexer.Rule(#"(?=<)"#, .plain, .pop(1)),
      Lexer.Rule(#"[^\s>]++"#, .string, .pop(1)),
    ],
  ]

  static let lexer = Lexer.defined(states, options: options)
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/RFCKit --filter XMLLexerTests`
Expected: PASS. If `a tag never closed does not swallow the next element` fails, trace it: `x` is a value (`[^\s>]++` → string, pop to `tag`), the newline is plain in `tag`, and `(?=<)` must pop `tag` before `<b` is read in `root`.

- [ ] **Step 5: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Packages/RFCKit/Sources/RFCKit/Highlighting/XMLLexer.swift Packages/RFCKit/Tests/RFCKitTests/XMLLexerTests.swift
git commit -m "An XML lexer that recovers from quotes and tags left open

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: HTTP messages, the registry, and media-type suffixes

**Files:**
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/ArtworkClassification.swift` (add `ArtworkType.suffix` after `canonical`)
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/Lexers.swift`
- Create: `Packages/RFCKit/Sources/RFCKit/Highlighting/HTTPMessageHighlighter.swift`
- Modify: `Packages/RFCKit/Tests/RFCKitTests/ArtworkClassifierTests.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/HTTPMessageHighlighterTests.swift`
- Create: `Packages/RFCKit/Tests/RFCKitTests/LexersTests.swift`

**Interfaces:**
- Consumes: `Lexer`, `JSONLexer.lexer`, `XMLLexer.lexer`, `TokenRun`.
- Produces:
  - `ArtworkType.suffix: String?`
  - `public enum Lexers` with `public enum Language: Sendable, Hashable { case json, xml, httpMessage }`, `public static var claimedNames: Set<String>`, `public static var claimedSuffixes: Set<String>`, `public static func language(of: ArtworkType) -> Language?`, `public static func highlighter(for: Language) -> any Highlighter`, `public static let sizeLimit = 65_536`, `public static func highlight(_ text: String, as type: ArtworkType) -> [SyntaxToken]?`
  - `enum HTTPLexer { static let headStates; static let head: Lexer; static func isStartLine(_: String) -> Bool }`
  - `struct HTTPMessageHighlighter: Highlighter` with `struct Message: Equatable { var head: NSRange; var body: NSRange? }` and `static func messages(in: NSString) -> [Message]`

- [ ] **Step 1: Write the failing suffix tests**

Append to `ArtworkClassifierTests` (inside the struct):

```swift
  @Test(arguments: [
    ("application/problem+json", "json"), ("sdf+json", "json"), ("application/atom+xml", "xml"),
  ])
  func `a structured suffix is read from the type`(declared: String, suffix: String) {
    #expect(ArtworkType.canonical(declared)?.suffix == suffix)
  }

  @Test(arguments: ["json", "cbor-diag", "message/http", "a+"])
  func `a type without a suffix has none`(declared: String) {
    #expect(ArtworkType.canonical(declared)?.suffix == nil)
  }
```

- [ ] **Step 2: Write the failing registry tests**

`Packages/RFCKit/Tests/RFCKitTests/LexersTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: which lexer a type names")
struct LexersTests {
  private func language(_ declared: String) -> Lexers.Language? {
    ArtworkType.canonical(declared).flatMap(Lexers.language(of:))
  }

  @Test func `every lexer's definition is valid`() throws {
    _ = try Lexer(states: JSONLexer.states)
    _ = try Lexer(states: XMLLexer.states, options: XMLLexer.options)
    _ = try Lexer(states: HTTPLexer.headStates)
  }

  @Test(arguments: [
    ("json", Lexers.Language.json), ("JSON", .json), ("application/json", .json),
    ("application/problem+json", .json), ("sdf+json", .json),
    ("xml", .xml), ("application/xml", .xml), ("text/xml", .xml), ("application/problem+xml", .xml),
    ("http-message", .httpMessage), (#"message/http; msgtype="request""#, .httpMessage),
  ])
  func `a type names its language`(declared: String, expected: Lexers.Language) {
    #expect(language(declared) == expected)
  }

  @Test(arguments: ["abnf", "asn.1", "yang", "cbor-diag", "pseudocode"])
  func `a type with no lexer names none`(declared: String) {
    #expect(language(declared) == nil)
  }

  @Test func `every claimed name and suffix names a language`() {
    for name in Lexers.claimedNames {
      #expect(Lexers.language(of: ArtworkType(name: name)) != nil, "\(name)")
    }
    for suffix in Lexers.claimedSuffixes {
      #expect(Lexers.language(of: ArtworkType(name: "x+\(suffix)")) != nil, "\(suffix)")
    }
  }

  @Test func `a block over the size limit is not highlighted`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit + 1)
    #expect(Lexers.highlight(text, as: ArtworkType(name: "json")) == nil)
  }

  @Test func `a block at the size limit is`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit)
    #expect(Lexers.highlight(text, as: ArtworkType(name: "json"))?.cover(text) == true)
  }

  @Test func `a type with no lexer is not highlighted`() {
    #expect(Lexers.highlight("a = b", as: ArtworkType(name: "abnf")) == nil)
  }
}
```

- [ ] **Step 3: Write the failing HTTP tests**

`Packages/RFCKit/Tests/RFCKitTests/HTTPMessageHighlighterTests.swift` (messages hand-written in the format's shape):

```swift
import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: HTTP messages")
struct HTTPMessageHighlighterTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    HTTPMessageHighlighter().tokens(in: text)
  }

  @Test func `a request line is a method, a target and a version`() {
    let text = "GET /items?id=1 HTTP/1.1\nHost: www.example.com\n"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "GET", in: text) == .keyword)
    #expect(tokens.kind(of: "/items?id=1", in: text) == .string)
    #expect(tokens.kind(of: "HTTP/1.1", in: text) == .keyword)
    #expect(tokens.kind(of: "Host", in: text) == .name)
    #expect(tokens.kind(of: "www.example.com", in: text) == .plain)
  }

  @Test func `a status line is a version and a code`() {
    let text = "HTTP/1.1 404 Not Found\nContent-Length: 0"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "HTTP/1.1", in: text) == .keyword)
    #expect(tokens.kind(of: "404", in: text) == .number)
    #expect(tokens.kind(of: "Content-Length", in: text) == .name)
  }

  @Test func `fields without a start line are fields`() {
    let text = "Cache-Control: max-age=60\nVary: Accept"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["Cache-Control", "Vary"])
  }

  @Test func `a message set in from the margin is read as one`() {
    let text = "  POST /events HTTP/1.1\n  Content-Type: text/plain\n"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "POST", in: text) == .keyword)
    #expect(tokens.kind(of: "Content-Type", in: text) == .name)
  }

  @Test func `a status without its version is a code`() {
    let text = "206 Partial Content\nContent-Range: bytes 0-9/100"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "206", in: text) == .number)
    #expect(tokens.kind(of: "Content-Range", in: text) == .name)
  }

  @Test func `a pseudo-header field is a name`() {
    let text = ":method = GET\n:path = /"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == [":method", ":path"])
  }

  /// Review focus 3.
  @Test func `a body is lexed as the content type with parameters says`() {
    let text =
      "HTTP/1.1 400 Bad Request\nContent-Type: application/problem+json; charset=utf-8\n\n{\"title\": \"Bad\"}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .name)
    #expect(tokens.kind(of: #""Bad""#, in: text) == .string)
  }

  @Test func `an XML body is lexed as XML`() {
    let text = "POST / HTTP/1.1\nContent-Type: application/xml\n\n<a b=\"c\"/>"
    #expect(tokens(text).kind(of: "<a", in: text) == .name)
  }

  @Test func `a body with no content type is plain`() {
    let text = "HTTP/1.1 200 OK\n\n{\"title\": \"x\"}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .plain)
  }

  @Test func `a second message after a body is read as a message`() {
    let text =
      "GET / HTTP/1.1\nHost: example.com\n\nHTTP/1.1 200 OK\nContent-Type: application/json\n\n{\"a\": 1}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text) == ["GET", "HTTP/1.1", "HTTP/1.1"])
    #expect(tokens.kind(of: "200", in: text) == .number)
    #expect(tokens.kind(of: #""a""#, in: text) == .name)
  }

  @Test func `consecutive status lines are two messages`() {
    let source = NSString(string: "HTTP/1.1 100 Continue\nHTTP/1.1 200 OK\n")
    #expect(HTTPMessageHighlighter.messages(in: source).count == 2)
  }

  @Test func `an empty block has no messages`() {
    #expect(HTTPMessageHighlighter.messages(in: NSString(string: "")).isEmpty)
    #expect(tokens("").isEmpty)
  }
}
```

- [ ] **Step 4: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter "LexersTests|HTTPMessageHighlighterTests|ArtworkClassifierTests"`
Expected: build failure — `value of type 'ArtworkType' has no member 'suffix'`, `cannot find 'Lexers'`.

- [ ] **Step 5: Add `ArtworkType.suffix`**

In `ArtworkClassification.swift`, inside `struct ArtworkType`, after `canonical(_:)`:

```swift
  /// The structured syntax suffix of a media type (RFC 6838, Section 4.2.8): `json`
  /// in `application/problem+json`, and in the RPC's types that borrow the
  /// convention, `sdf+json`. Nil where there is none.
  public var suffix: String? {
    guard let plus = name.lastIndex(of: "+") else { return nil }
    let suffix = name[name.index(after: plus)...]
    return suffix.isEmpty ? nil : String(suffix)
  }
```

- [ ] **Step 6: Write the registry**

`Packages/RFCKit/Sources/RFCKit/Highlighting/Lexers.swift`:

```swift
import Foundation

/// Which highlighter a block's type names: the one place it is decided.
public enum Lexers {
  public enum Language: Sendable, Hashable {
    case json
    case xml
    case httpMessage
  }

  /// The canonical type names a language is named by, exactly.
  static let names: [String: Language] = [
    "json": .json, "application/json": .json,
    "xml": .xml, "application/xml": .xml, "text/xml": .xml,
    "http-message": .httpMessage, "message/http": .httpMessage,
  ]

  /// The structured suffixes a language is named by, where no name is: any
  /// `+json` or `+xml` type.
  static let suffixes: [String: Language] = ["json": .json, "xml": .xml]

  public static var claimedNames: Set<String> { Set(names.keys) }
  public static var claimedSuffixes: Set<String> { Set(suffixes.keys) }

  /// Over this, in UTF-16 code units, a block is not highlighted: above the corpus's
  /// largest highlighted block, 53 KB in RFC 8727, and a bound on what a
  /// pathological one can cost.
  public static let sizeLimit = 65_536

  /// An exact name wins over a suffix.
  public static func language(of type: ArtworkType) -> Language? {
    names[type.name] ?? type.suffix.flatMap { suffixes[$0] }
  }

  public static func highlighter(for language: Language) -> any Highlighter {
    switch language {
    case .json: JSONLexer.lexer
    case .xml: XMLLexer.lexer
    case .httpMessage: HTTPMessageHighlighter()
    }
  }

  /// `text`'s tokens, or nil where its type names no language or it is over the
  /// size limit.
  public static func highlight(_ text: String, as type: ArtworkType) -> [SyntaxToken]? {
    guard text.utf16.count <= sizeLimit, let language = language(of: type) else { return nil }
    return highlighter(for: language).tokens(in: text)
  }
}
```

- [ ] **Step 7: Write the HTTP highlighter**

`Packages/RFCKit/Sources/RFCKit/Highlighting/HTTPMessageHighlighter.swift`:

```swift
import Foundation

/// The head of an HTTP message, a line at a time: a start line or none, then fields.
///
/// Written for RFCs rather than translated: neither Pygments' HTTP lexer, which works
/// through callbacks, nor Chroma's, which is code, is a table, and both expect a
/// message that starts with a start line, which 221 of the corpus's 520 do not.
enum HTTPLexer {
  /// RFC 9112's request line, set in from the margin or not.
  static let requestLine =
    #"^([ \t]*+)([A-Z][A-Z-]*+)([ \t]++)([^\s]++)([ \t]++)(HTTP/[0-9](?:\.[0-9])?)[ \t]*+$"#
  /// RFC 9112's status line.
  static let statusLine = #"^([ \t]*+)(HTTP/[0-9](?:\.[0-9])?)([ \t]++)([0-9]{3})([^\n]*+)$"#
  /// A status line without its version, as some RFCs abbreviate one.
  static let bareStatusLine = #"^([ \t]*+)([1-5][0-9]{2})([ \t]++[^\n]*+)$"#
  /// An HTTP/2 or HTTP/3 pseudo-header field, as RFCs list them: `:method = GET`.
  static let pseudoHeaderLine = #"^([ \t]*+)(:[a-z]++)([ \t]*+[:=])([^\n]*+)$"#
  /// A field line: a token, a colon, a value.
  static let fieldLine = #"^([ \t]*+)([!#$%&'*+.^_`|~0-9A-Za-z-]++)(:)([^\n]*+)$"#

  static let headStates: [String: [Lexer.Rule]] = [
    "root": [
      Lexer.Rule(requestLine, groups: [.plain, .keyword, .plain, .string, .plain, .keyword]),
      Lexer.Rule(statusLine, groups: [.plain, .keyword, .plain, .number, .plain]),
      Lexer.Rule(bareStatusLine, groups: [.plain, .number, .plain]),
      Lexer.Rule(pseudoHeaderLine, groups: [.plain, .name, .punctuation, .plain]),
      Lexer.Rule(fieldLine, groups: [.plain, .name, .punctuation, .plain]),
      Lexer.Rule(#"[^\n]++"#, .plain),
      Lexer.Rule(#"\n"#, .plain),
    ]
  ]

  static let head = Lexer.defined(headStates)

  private static let startLine = Lexer.expression(
    "(?:\(requestLine))|(?:\(statusLine))", options: .anchorsMatchLines)

  /// Whether `line` starts a message: a request or status line with its version.
  static func isStartLine(_ line: String) -> Bool {
    startLine.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
  }

  static let contentType = Lexer.expression(
    #"^[ \t]*+content-type[ \t]*+:[ \t]*+([^\n]*+)$"#, options: [.anchorsMatchLines, .caseInsensitive])
}

/// An HTTP message, or several, as RFCs set them: a head lexed by `HTTPLexer`, and
/// a body lexed as its `Content-Type` says, where it names JSON or XML, and plain
/// otherwise.
struct HTTPMessageHighlighter: Highlighter {
  /// One message's head and body, as ranges of the block. The blank line that ends
  /// a head belongs to its body.
  struct Message: Equatable {
    var head: NSRange
    var body: NSRange?
  }

  func tokens(in text: String) -> [SyntaxToken] {
    let source = NSString(string: text)
    var output = TokenRun()
    for message in Self.messages(in: source) {
      let head = source.substring(with: message.head)
      output.append(contentsOf: HTTPLexer.head.tokens(in: head), offset: message.head.location)
      guard let body = message.body else { continue }
      let bodyText = source.substring(with: body)
      let tokens =
        Self.bodyHighlighter(forHead: head)?.tokens(in: bodyText)
        ?? [SyntaxToken(range: NSRange(location: 0, length: body.length), kind: .plain)]
      output.append(contentsOf: tokens, offset: body.location)
    }
    return output.tokens
  }

  /// The block split into messages, which together cover it. A message's head runs
  /// to its first blank line, and its body from there to a start line after a
  /// blank line; a start line inside a head starts the next message too.
  static func messages(in text: NSString) -> [Message] {
    guard text.length > 0 else { return [] }
    var messages: [Message] = []
    var start = 0
    var bodyStart: Int?
    var previousLineBlank = false
    var position = 0
    while position < text.length {
      let line = text.lineRange(for: NSRange(location: position, length: 0))
      let content = text.substring(with: line)
      let blank = content.allSatisfy(\.isWhitespace)
      if line.location > start, bodyStart == nil || previousLineBlank,
        HTTPLexer.isStartLine(content)
      {
        messages.append(message(from: start, bodyStart: bodyStart, to: line.location))
        start = line.location
        bodyStart = nil
      } else if bodyStart == nil, blank {
        bodyStart = line.location
      }
      previousLineBlank = blank
      position = NSMaxRange(line)
    }
    messages.append(message(from: start, bodyStart: bodyStart, to: text.length))
    return messages
  }

  private static func message(from start: Int, bodyStart: Int?, to end: Int) -> Message {
    let headEnd = bodyStart ?? end
    return Message(
      head: NSRange(location: start, length: headEnd - start),
      body: bodyStart.map { NSRange(location: $0, length: end - $0) })
  }

  /// What the head's `Content-Type` names, where it names a language other than
  /// HTTP itself.
  private static func bodyHighlighter(forHead head: String) -> (any Highlighter)? {
    let source = NSString(string: head)
    guard
      let match = HTTPLexer.contentType.firstMatch(
        in: head, range: NSRange(location: 0, length: source.length)),
      let type = ArtworkType.canonical(source.substring(with: match.range(at: 1))),
      let language = Lexers.language(of: type), language != .httpMessage
    else { return nil }
    return Lexers.highlighter(for: language)
  }
}
```

- [ ] **Step 8: Run the tests**

Run: `swift test --package-path Packages/RFCKit --filter "LexersTests|HTTPMessageHighlighterTests|ArtworkClassifierTests"`
Expected: PASS.

- [ ] **Step 9: Run the whole RFCKit suite**

Run: `make test`
Expected: PASS.

- [ ] **Step 10: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Packages/RFCKit
git commit -m "Highlight HTTP messages, and name lexers by type and media-type suffix

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The corpus-backed suite

**Files:**
- Modify: `Makefile` (`CORPUS_TEST_XML_DOCUMENTS`)
- Create: `Packages/RFCKit/Tests/RFCKitTests/CorpusBackedHighlightingTests.swift`

**Interfaces:**
- Consumes: `Lexers`, `HTTPLexer.isStartLine`, `FoldedLines.unfold`, `RFCXMLParser.parse`, `RFCDocument.blocks`, `CorpusText.xml`, the helpers from Task 2.

- [ ] **Step 1: List the documents**

In `Makefile`, append to `CORPUS_TEST_XML_DOCUMENTS` (keep what is there):

```make
CORPUS_TEST_XML_DOCUMENTS := rfc9110 rfc9114 rfc9393 rfc9457 rfc8927 rfc8727 rfc9635 rfc9022 rfc8935
```

(If main has added documents since, keep them too.)

- [ ] **Step 2: Write the suite**

`Packages/RFCKit/Tests/RFCKitTests/CorpusBackedHighlightingTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCKit

/// Every block the highlighters claim, in documents chosen for what they hold: RFC
/// 9110's HTTP without bodies, RFC 9457's problem+json and problem+xml bodies, RFC
/// 8927's valid JSON, RFC 8727's 53 KB JSON block, RFC 9635's invalid and folded
/// JSON and odd HTTP, RFC 9022's fragmentary XML, RFC 8935's indented HTTP. Each
/// block is lexed as published and, where RFC 8792 folded it, unfolded, as the
/// reader shows it in a wide column.
@Suite("Corpus-backed: syntax highlighting", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedHighlightingTests {
  static let documents = [
    "rfc9110", "rfc9457", "rfc8927", "rfc8727", "rfc9635", "rfc9022", "rfc8935",
  ]

  struct Sample {
    let place: String
    let language: Lexers.Language
    let type: ArtworkType
    let text: String
  }

  static func samples(_ stem: String) throws -> [Sample] {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    return document.blocks.flatMap { block -> [Sample] in
      guard case .preformatted(let content) = block,
        let type = ArtworkType.canonical(content.type),
        let language = Lexers.language(of: type)
      else { return [] }
      let place = "\(stem) \(content.anchor ?? "(no anchor)")"
      let texts = [content.text] + [FoldedLines.unfold(content.text)].compactMap { $0 }
      return texts.map { Sample(place: place, language: language, type: type, text: $0) }
    }
  }

  private static func nonWhitespace(_ text: String) -> Int {
    text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
  }

  @Test(arguments: documents)
  func `every block is covered exactly once`(stem: String) throws {
    let samples = try Self.samples(stem)
    #expect(!samples.isEmpty, "\(stem) has no block to highlight")
    for sample in samples {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type), "\(sample.place)")
      #expect(tokens.cover(sample.text), "\(sample.place)")
    }
  }

  @Test(arguments: documents)
  func `no block takes long`(stem: String) throws {
    for sample in try Self.samples(stem) {
      let elapsed = ContinuousClock().measure {
        _ = Lexers.highlight(sample.text, as: sample.type)
      }
      #expect(elapsed < .milliseconds(500), "\(sample.place) took \(elapsed)")
    }
  }

  @Test(arguments: documents)
  func `a block that parses as JSON leaves nothing plain but white space`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language == .json {
      guard (try? JSONSerialization.jsonObject(with: Data(sample.text.utf8), options: .fragmentsAllowed)) != nil
      else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let plain = tokens.text(of: .plain, in: sample.text)
      #expect(plain.allSatisfy { Self.nonWhitespace($0) == 0 }, "\(sample.place): \(plain.prefix(3))")
    }
  }

  @Test(arguments: documents)
  func `no JSON string or XML value runs past its line`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language != .httpMessage {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let strings = tokens.text(of: .string, in: sample.text) + tokens.text(of: .name, in: sample.text)
      #expect(strings.allSatisfy { !$0.contains("\n") }, "\(sample.place)")
    }
  }

  /// A JSON block that is valid or not is still mostly read: an elision, a
  /// fragment's stray character or a hand-broken string leaves a little plain, never
  /// most of it. A block typed `json` that is an HTTP message is another language.
  @Test(arguments: documents)
  func `a JSON block is mostly lexed`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language == .json {
      let firstLine = sample.text.split(separator: "\n").first.map(String.init) ?? ""
      guard !HTTPLexer.isStartLine(firstLine) else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let plain = tokens.text(of: .plain, in: sample.text).map(Self.nonWhitespace).reduce(0, +)
      let all = Self.nonWhitespace(sample.text)
      #expect(Double(plain) <= Double(all) * 0.1, "\(sample.place): \(plain) of \(all) plain")
    }
  }

  @Test(arguments: documents)
  func `an XML block with a tag has a name`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language == .xml && sample.text.contains("<") {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      #expect(tokens.contains { $0.kind == .name }, "\(sample.place)")
    }
  }

  @Test(arguments: documents)
  func `an HTTP block that starts with a message or a field has a name or keyword`(stem: String) throws {
    let field = try NSRegularExpression(pattern: HTTPLexer.fieldLine, options: .anchorsMatchLines)
    for sample in try Self.samples(stem) where sample.language == .httpMessage {
      let firstLine =
        sample.text.split(separator: "\n").first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
      let isField = field.firstMatch(in: firstLine, range: NSRange(location: 0, length: firstLine.utf16.count)) != nil
      guard HTTPLexer.isStartLine(firstLine) || isField else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      #expect(tokens.contains { $0.kind == .name || $0.kind == .keyword }, "\(sample.place)")
    }
  }
}
```

- [ ] **Step 3: Run it**

Run: `make test-corpus`
Expected: the new suite runs (it fetches the six new documents first) and passes, as do the existing corpus suites.

If `a JSON block is mostly lexed` fails, read the named block in `corpus/xml.noindex/` and decide which it is:
- the lexer misreads a JSON construct → fix `JSONLexer` and add a guard-level test of that construct to `JSONLexerTests` first;
- the block is not JSON whatever its type (CDDL, pseudocode, prose) → skip it by its anchor in a `static let notJSON: Set<String>` with a one-line reason each, never by loosening the 10% bound.

Report every anchor you skip.

- [ ] **Step 4: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Makefile Packages/RFCKit/Tests/RFCKitTests/CorpusBackedHighlightingTests.swift
git commit -m "Check the highlighters against the corpus's JSON, XML and HTTP blocks

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The syntax presentation, and suffixes in the renderer registry

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/Rendition.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/ArtworkRenderers.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/SyntaxPresentation.swift`
- Modify: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/ArtworkRenderersTests.swift`

**Interfaces:**
- Consumes: `Lexers.claimedNames`, `Lexers.claimedSuffixes`, `Lexers.highlight(_:as:)`, `SyntaxToken` (Task 5).
- Produces: `Rendition.styled(StyledText)`; `public struct StyledText: Equatable, Sendable { public var tokens: [SyntaxToken] }`; `RendererEntry.suffixes: Set<String>`; `enum SyntaxPresentation { static let entry: RendererEntry }` with presentation id `"syntax"`.

- [ ] **Step 1: Write the failing tests**

In `ArtworkRenderersTests`, replace `no type is claimed by two entries` and add tests:

```swift
  @Test func `no type and no suffix is claimed by two entries`() {
    let names = ArtworkRenderers.entries.flatMap(\.types)
    #expect(names.count == Set(names).count)
    let suffixes = ArtworkRenderers.entries.flatMap(\.suffixes)
    #expect(suffixes.count == Set(suffixes).count)
  }

  @Test func `a JSON block is rendered as styled text`() throws {
    let block = Preformatted(kind: .sourceCode, text: #"{"a": 1}"#, type: "json")
    let classification = ArtworkClassification(type: ArtworkType.canonical("json"))
    #expect(ArtworkRenderers.presentations(for: classification.type).map(\.id) == ["syntax"])
    let rendition = try #require(ArtworkRenderers.render(block, classification, context: context))
    guard case .styled(let styled) = rendition else {
      Issue.record("expected styled text, got \(rendition)")
      return
    }
    #expect(styled.tokens.contains { $0.kind == .name })
  }

  @Test func `a type is claimed by its structured suffix`() {
    let type = ArtworkType.canonical("application/problem+json")
    #expect(ArtworkRenderers.presentations(for: type).map(\.id) == ["syntax"])
  }

  @Test func `a block over the size limit is declined`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit + 1)
    let block = Preformatted(kind: .sourceCode, text: text, type: "json")
    let classification = ArtworkClassification(type: ArtworkType.canonical("json"))
    #expect(ArtworkRenderers.render(block, classification, context: context) == nil)
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter ArtworkRenderersTests`
Expected: build failure — `value of type 'RendererEntry' has no member 'suffixes'`.

- [ ] **Step 3: Add the rendition**

In `Rendition.swift`, replace the `Rendition` enum and its comment with:

```swift
/// Code highlighted: the block's own text, unchanged, and the tokens a lexer read in
/// it, colored by the reader's theme. Ranges are UTF-16, relative to the text lexed.
public struct StyledText: Equatable, Sendable {
  public var tokens: [SyntaxToken]

  public init(tokens: [SyntaxToken]) {
    self.tokens = tokens
  }
}

/// What a presentation makes of a block. Drawings join as a case when a renderer
/// first needs them.
public enum Rendition: Equatable, Sendable {
  case decorated(DecoratedText)
  case styled(StyledText)
}
```

- [ ] **Step 4: Add suffixes to the registry**

In `ArtworkRenderers.swift`, change `RendererEntry` to:

```swift
/// The types a renderer claims, by canonical name and by structured suffix (`json`
/// claims `application/problem+json`), and its presentations in order of preference.
public struct RendererEntry: Sendable {
  public let types: Set<String>
  public let suffixes: Set<String>
  public let presentations: [Presentation]

  public init(types: Set<String>, suffixes: Set<String> = [], presentations: [Presentation]) {
    self.types = types
    self.suffixes = suffixes
    self.presentations = presentations
  }
}
```

and in `enum ArtworkRenderers`:

```swift
  static let entries: [RendererEntry] = [
    PacketPresentation.entry,
    SyntaxPresentation.entry,
  ]

  /// An exact name wins over a suffix.
  static func presentations(for type: ArtworkType?) -> [Presentation] {
    guard let type else { return [] }
    if let entry = entries.first(where: { $0.types.contains(type.name) }) {
      return entry.presentations
    }
    guard let suffix = type.suffix else { return [] }
    return entries.first { $0.suffixes.contains(suffix) }?.presentations ?? []
  }
```

- [ ] **Step 5: Write the presentation**

`Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/SyntaxPresentation.swift`:

```swift
import Foundation
import RFCKit

/// Source code highlighted, for every type a lexer in RFCKit reads (`Lexers`).
enum SyntaxPresentation {
  static let entry = RendererEntry(
    types: Lexers.claimedNames, suffixes: Lexers.claimedSuffixes,
    presentations: [
      Presentation(id: "syntax") { block, classification, _ in
        guard let type = classification.type,
          let tokens = Lexers.highlight(block.text, as: type)
        else { return nil }
        return .styled(StyledText(tokens: tokens))
      }
    ])
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Packages/RFCReaderKit --filter ArtworkRenderersTests`
Expected: PASS. (The builder does not use `.styled` yet; Task 9 does. Until then a styled rendition makes a block `.rendered` in the builder; do not ship between Tasks 7 and 9.)

- [ ] **Step 7: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Packages/RFCReaderKit
git commit -m "A styled-text rendition for code, claimed by type and media-type suffix

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The syntax theme

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/SyntaxTheme.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/SyntaxThemeTests.swift`

**Interfaces:**
- Consumes: `TokenKind` (RFCKit), `PlatformColor`, `RFCColors.cardFill`.
- Produces: `public struct SyntaxTheme: Sendable` with `public init(_ colors: [TokenKind: PlatformColor])`, `public func color(for kind: TokenKind) -> PlatformColor?` (nil for `.plain` and for kinds left out), `public static let standard: SyntaxTheme`; `enum Contrast { static func ratio(_ a: RGB, _ b: RGB) -> Double }` with `struct RGB { var red, green, blue: Double }`.

The palette, measured with the WCAG formula against the card over the page (light: white page, card 3% black ≈ #F7F7F7; dark: card 8.5% white over a black page, #161616, and over macOS's dark text background, #313131):

| Role | Kinds | Light | Dark | Light ratio | Dark ratios |
|---|---|---|---|---|---|
| muted | punctuation, comment | #6E6E73 | #A1A1A6 | 4.73 | 5.06 / 7.04 |
| name | name | #3A3AB8 | #A9A9FF | 7.91 | 6.07 / 8.45 |
| string | string | #1F7A3A | #7BD88F | 5.02 | 7.47 / 10.39 |
| literal | keyword, number, attribute | #8A3FB0 | #D9A6F5 | 5.73 | 6.64 / 9.24 |

The spec had punctuation and comments in the secondary label color; that color is about 4:1 on the card, below the floor, so they get the muted gray instead.

- [ ] **Step 1: Write the failing tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/SyntaxThemeTests.swift`:

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Syntax theme")
@MainActor
struct SyntaxThemeTests {
  @Test func `the contrast of black on white is 21 and of a color on itself 1`() {
    let black = Contrast.RGB(red: 0, green: 0, blue: 0)
    let white = Contrast.RGB(red: 1, green: 1, blue: 1)
    #expect(abs(Contrast.ratio(black, white) - 21) < 0.01)
    #expect(abs(Contrast.ratio(white, white) - 1) < 0.01)
  }

  @Test func `plain text keeps the body color`() {
    #expect(SyntaxTheme.standard.color(for: .plain) == nil)
  }

  @Test func `every other kind has a color`() {
    for kind in TokenKind.allCases where kind != .plain {
      #expect(SyntaxTheme.standard.color(for: kind) != nil, "\(kind)")
    }
  }

  /// Dark mode is a redraw, never a rebuild, so a theme's colors must resolve by
  /// appearance.
  @Test func `every color is dynamic`() throws {
    for kind in TokenKind.allCases where kind != .plain {
      let color = try #require(SyntaxTheme.standard.color(for: kind))
      #expect(try resolved(color, dark: false) != resolved(color, dark: true), "\(kind)")
    }
  }

  /// The pages a card is drawn on: white in light; black (iOS) and macOS's dark text
  /// background in dark.
  @Test(arguments: [(false, 1.0), (true, 0.0), (true, 0.118)])
  func `every color reaches 4.5 to 1 against the card`(dark: Bool, page: Double) throws {
    let card = try resolved(RFCColors.cardFill, dark: dark)
    let level = page * (1 - card.alpha) + card.red * card.alpha
    let background = Contrast.RGB(red: level, green: level, blue: level)
    for kind in TokenKind.allCases where kind != .plain {
      let color = try resolved(try #require(SyntaxTheme.standard.color(for: kind)), dark: dark)
      let ratio = Contrast.ratio(
        Contrast.RGB(red: color.red, green: color.green, blue: color.blue), background)
      #expect(ratio >= 4.5, "\(kind) is \(ratio):1 on \(level) in \(dark ? "dark" : "light")")
    }
  }

  private struct Resolved: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
  }

  private func resolved(_ color: PlatformColor, dark: Bool) throws -> Resolved {
    var red: CGFloat = -1
    var green: CGFloat = -1
    var blue: CGFloat = -1
    var alpha: CGFloat = -1
    #if canImport(UIKit)
      let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
      _ = color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #else
      let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
      appearance.performAsCurrentDrawingAppearance {
        color.usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      }
    #endif
    return Resolved(red: red, green: green, blue: blue, alpha: alpha)
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter SyntaxThemeTests`
Expected: build failure — `cannot find 'Contrast' in scope`.

- [ ] **Step 3: Write the theme**

`Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/SyntaxTheme.swift`:

```swift
import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The color of each kind of token. A value, so that colors can be configured later
/// (pickers in Settings, a color-blind variant) by handing the builder another
/// theme. Its colors must be dynamic, resolved by appearance when drawn, so that
/// dark mode is a redraw and print's light appearance needs no rebuild; and each
/// must reach 4.5:1 against the verbatim card (`SyntaxThemeTests`).
public struct SyntaxTheme: Sendable {
  private let colors: [TokenKind: PlatformColor]

  public init(_ colors: [TokenKind: PlatformColor]) {
    self.colors = colors
  }

  /// The color of `kind`, or nil to keep the body color of the block's context,
  /// which a quote or an aside sets: always for plain text.
  public func color(for kind: TokenKind) -> PlatformColor? {
    kind == .plain ? nil : colors[kind]
  }

  /// Restrained, for a reader where code supports the prose: names, strings and
  /// literals in three quiet hues, punctuation and comments in gray. The system's
  /// secondary label color, about 4:1 on the card, is too faint for them.
  public static let standard: SyntaxTheme = {
    let muted = color(light: 0x6E6E73, dark: 0xA1A1A6)
    let literal = color(light: 0x8A3FB0, dark: 0xD9A6F5)
    return SyntaxTheme([
      .punctuation: muted,
      .comment: muted,
      .name: color(light: 0x3A3AB8, dark: 0xA9A9FF),
      .string: color(light: 0x1F7A3A, dark: 0x7BD88F),
      .keyword: literal,
      .number: literal,
      .attribute: literal,
    ])
  }()

  /// A color for each appearance, as sRGB hex, resolved when it is drawn.
  static func color(light: UInt32, dark: UInt32) -> PlatformColor {
    #if canImport(UIKit)
      UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) }
    #else
      NSColor(name: nil) { appearance in
        rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
      }
    #endif
  }

  private static func rgb(_ hex: UInt32) -> PlatformColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    #if canImport(UIKit)
      return UIColor(red: red, green: green, blue: blue, alpha: 1)
    #else
      return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    #endif
  }
}

/// WCAG 2's contrast ratio between two opaque sRGB colors, from 1 to 21.
enum Contrast {
  struct RGB {
    var red: Double
    var green: Double
    var blue: Double
  }

  static func ratio(_ first: RGB, _ second: RGB) -> Double {
    let lighter = max(luminance(first), luminance(second))
    let darker = min(luminance(first), luminance(second))
    return (lighter + 0.05) / (darker + 0.05)
  }

  private static func luminance(_ color: RGB) -> Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/RFCReaderKit --filter SyntaxThemeTests`
Expected: PASS. In `every color reaches 4.5 to 1 against the card`, `card.red` is the card's gray resolved in sRGB (the card is a gray, so red = green = blue). If a ratio falls below 4.5, darken that light value or lighten that dark value until it passes, and update the table in this task.

- [ ] **Step 5: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add Packages/RFCReaderKit
git commit -m "A syntax theme whose every color reaches 4.5:1 on the card

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Highlighted code in the reader body

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Attributes.swift` (`VerbatimBox.Shown`, `presentation`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder+Verbatim.swift` (`appendVerbatim`, new `highlight`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/AccessibleReading.swift` (`isDiagram`)
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderHighlightingTests.swift`

**Interfaces:**
- Consumes: `Rendition.styled`, `StyledText`, `SyntaxTheme.standard` (Tasks 7–8).
- Produces: `VerbatimBox.Shown.highlighted`; `VerbatimBox.Shown.isFigure: Bool` (true for `.rendered` and `.source`).

- [ ] **Step 1: Write the failing builder tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderHighlightingTests.swift` (blocks hand-written in each format's shape; nothing here calls `parse`):

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: highlighted code")
struct BuilderHighlightingTests {
  private static let json = #"{"name": "value", "count": 2}"#
  private static let listing = Preformatted(
    kind: .sourceCode, text: json, type: "json", anchor: "listing")

  private func build(
    _ content: Preformatted, style: ReadingStyle = ReadingStyle(),
    choices: PresentationChoices = .defaults
  ) -> BuiltDocument {
    DocumentTextBuilder.build(
      Fixtures.document(.preformatted(content)), style: style, choices: choices)
  }

  private func color(of fragment: String, in built: BuiltDocument) throws -> PlatformColor? {
    let range = (built.text.string as NSString).range(of: fragment)
    try #require(range.location != NSNotFound, "\(fragment) is not in the text")
    return built.text.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
      as? PlatformColor
  }

  private func box(in built: BuiltDocument) throws -> VerbatimBox {
    let offset = try #require(built.anchors.offset(of: "listing"))
    return try #require(
      built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
  }

  private func hasFigureItem(_ built: BuiltDocument) -> Bool {
    var found = false
    built.text.enumerateAttribute(
      .rfcFigureItem, in: NSRange(location: 0, length: built.text.length)
    ) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  @Test func `the text is the block's own`() {
    #expect(build(Self.listing).text.string.contains(Self.json))
  }

  @Test func `each token carries its theme color`() throws {
    let built = build(Self.listing)
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
    #expect(try color(of: #""value""#, in: built) == SyntaxTheme.standard.color(for: .string))
    #expect(try color(of: "2", in: built) == SyntaxTheme.standard.color(for: .number))
  }

  @Test func `plain text keeps the body color`() throws {
    let message = Preformatted(
      kind: .sourceCode, text: "HTTP/1.1 200 OK\n\nhello", type: "http-message", anchor: "listing")
    #expect(try color(of: "hello", in: build(message)) == RFCColors.label)
  }

  @Test func `a highlighted block is not a figure`() throws {
    let built = build(Self.listing)
    let box = try box(in: built)
    #expect(box.shown == .highlighted)
    #expect(box.presentation == nil, "no Show as Text / Show as Figure")
    #expect(!hasFigureItem(built), "no long-press figure menu on iOS")
    #expect(box.spokenLabel == nil)
    #expect(!AccessibleReading.isDiagram(box))
    #expect(AccessibleReading.Rotors(built.text).diagrams.isEmpty)
  }

  @Test func `drawing diagrams off leaves code highlighted`() throws {
    let built = build(Self.listing, choices: PresentationChoices(drawsDiagrams: false))
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  @Test func `a choice of text for the block leaves it highlighted`() throws {
    let key = PresentationKey(anchor: "listing", ordinal: 0)
    let built = build(Self.listing, choices: PresentationChoices(chosen: [key: .text]))
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  /// 17 HTTP messages in the corpus are artwork, not source code; a highlighted
  /// block keeps its indent, as plain artwork does.
  @Test func `highlighted artwork is not centered`() throws {
    let text = "GET / HTTP/1.1\nHost: example.com"
    let typed = build(
      Preformatted(kind: .artwork, text: text, type: "message/http", anchor: "listing"))
    let untyped = build(Preformatted(kind: .artwork, text: text, anchor: "listing"))
    func indent(_ built: BuiltDocument) throws -> CGFloat {
      let offset = (built.text.string as NSString).range(of: "GET").location
      let style = try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
      return style.firstLineHeadIndent
    }
    #expect(try indent(typed) == indent(untyped))
  }

  // MARK: - RFC 8792 folding

  private static let header =
    "=============== NOTE: '\\' line wrapping per RFC 8792 ================"

  /// A JSON block folded to fit the page, whose single unfolded line is `unfolded`.
  private static func folded(_ unfolded: String) -> Preformatted {
    let pieces = stride(from: 0, to: unfolded.count, by: 60).map { start in
      String(unfolded.dropFirst(start).prefix(60))
    }
    let text = header + "\n\n" + pieces.joined(separator: "\\\n")
    return Preformatted(kind: .sourceCode, text: text, type: "json", anchor: "listing")
  }

  @Test func `a folded block is highlighted where it is shown unfolded`() throws {
    let unfolded = #"{"key": ""# + String(repeating: "a", count: 50) + #""}"#
    let built = build(Self.folded(unfolded))
    #expect(built.text.string.contains(unfolded), "shown unfolded")
    #expect(try color(of: #""key""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  @Test func `a folded block is highlighted where it keeps its folds`() throws {
    let unfolded = #"{"key": ""# + String(repeating: "a", count: 50) + #""}"#
    let content = Self.folded(unfolded)
    let built = build(content, style: ReadingStyle(measure: 300))
    #expect(built.text.string.contains(content.text), "shown folded")
    #expect(try color(of: #""key""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderHighlightingTests`
Expected: build failure — `type 'VerbatimBox.Shown' has no member 'highlighted'`.

- [ ] **Step 3: Add the shown state**

In `Attributes.swift`, change `VerbatimBox.Shown` and `presentation`:

```swift
  /// Whether the block is set as its source, rendered, or highlighted, and whether a
  /// rendering exists to switch to: its menu offers "Show as Text" on a rendered
  /// block and "Show as Figure" on one shown as its source.
  public enum Shown: Sendable, Equatable {
    /// No presentation accepts the block.
    case plain
    case rendered
    /// A presentation accepts it, and the reader asked for the source.
    case source
    /// Code, highlighted: always, with nothing to switch to, and never a figure.
    case highlighted

    /// Whether the block is a figure: one with a drawing to switch to and from,
    /// a menu to do it in, and a card in the middle of the column.
    public var isFigure: Bool {
      self == .rendered || self == .source
    }
  }
```

```swift
  /// How it is shown, or nil for a block with no rendering to switch to.
  public var presentation: PresentationChoices.Presentation? {
    switch shown {
    case .plain, .highlighted: nil
    case .rendered: .figure
    case .source: .text
    }
  }
```

- [ ] **Step 4: Teach the builder**

In `DocumentTextBuilder+Verbatim.swift`, `appendVerbatim`, replace everything from `// A rendition's ranges are into the block's own text` through the `let shown: VerbatimBox.Shown = …` line with:

```swift
    let context = RenderContext(
      style: style, column: max(style.indentStep, style.measure - indent))
    var shownContent = content
    shownContent.text = text
    let rendition: Rendition? =
      switch ArtworkRenderers.render(shownContent, classification, context: context) {
      // Tokens are a function of the text alone, so a highlighted block follows the
      // text shown, unfolded (#64) or not.
      case .styled(let styled)?: .styled(styled)
      // A decoration's ranges are into the block as written, so a block shown other
      // than as written is not decorated.
      case .decorated(let decorated)? where text == content.text: .decorated(decorated)
      default: nil
      }
    let showsSource =
      choices.presentation(of: PresentationKey(anchor: content.anchor, ordinal: ordinal)) == .text
    // Code is highlighted whatever the choices say: it has no other presentation, and
    // "Draw diagrams" and "Show as Text" are about drawings.
    let shown: VerbatimBox.Shown =
      switch rendition {
      case nil: .plain
      case .styled?: .highlighted
      case .decorated?: showsSource ? .source : .rendered
      }
```

Replace the centering comment and `bodyIndent`:

```swift
    // A figure's card sits in the middle of the column; source code, highlighted
    // code and plain artwork keep their indent. Through the indent, so selection,
    // find and strokes follow. The scale fitted the block at `indent`, which this
    // never narrows.
    let bodyIndent =
      shown.isFigure ? max(indent, (style.measure - contentWidth) / 2) : indent
```

After `if let decorated { decorate(decorated, from: bodyStart) }` add:

```swift
    if case .styled(let styled)? = rendition {
      highlight(styled, from: bodyStart)
    }
```

Change the figure-item condition from `if shown != .plain, style.emitsLinks {` to:

```swift
    if shown.isFigure, style.emitsLinks {
```

Add the helper after `decorate(_:from:)`:

```swift
  /// Colors a highlighted block's tokens from the theme. Plain tokens keep the
  /// body color the block was set in, which a quote or an aside sets. The text is
  /// unchanged.
  func highlight(_ styled: StyledText, from bodyStart: Int) {
    for token in styled.tokens {
      guard let color = SyntaxTheme.standard.color(for: token.kind) else { continue }
      output.addAttribute(
        .foregroundColor, value: color,
        range: NSRange(location: bodyStart + token.range.location, length: token.range.length))
    }
  }
```

- [ ] **Step 5: Keep highlighted code out of the diagrams**

In `AccessibleReading.swift`, `isDiagram`:

```swift
  public static func isDiagram(_ box: VerbatimBox) -> Bool {
    guard box.shown != .highlighted else { return false }
    return box.spokenLabel != nil
      || (box.content.kind == .artwork && looksLikeDrawing(box.content.text))
  }
```

and add to its doc comment: "Highlighted code never is: it is read as code."

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Packages/RFCReaderKit --filter "BuilderHighlightingTests|BuilderRendererTests|BuilderVerbatimTests|BuilderCompletenessTests|BuilderHandoverTests|AccessibleReadingTests|AccessibleRotorTests|FigureMenuTests"`
Expected: PASS.

- [ ] **Step 7: Run everything**

Run: `make check`
Expected: lint, build, tests and app tests all pass. The App target compiles unchanged: its menus read `box.presentation`, which is nil for highlighted code.

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add Packages/RFCReaderKit
git commit -m "Highlight JSON, XML and HTTP messages in the reader

Code is always highlighted and never a figure: no menu to switch it, no
long-press figure item, no centering, and VoiceOver reads it as code.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Acknowledgements

**Files:**
- Create: `THIRD_PARTY_NOTICES`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/Acknowledgements.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Chrome/AcknowledgementsTests.swift`
- Modify: `App/RFCReader/RFCReaderApp.swift` (macOS commands)
- Create: `App/RFCReader/Views/AcknowledgementsView.swift`
- Modify: `App/RFCReader/Views/RFCListView.swift` (iOS `optionsMenu`, the sheet)

**Interfaces:**
- Produces: `public enum Acknowledgements { public static let text: String }`, identical to `THIRD_PARTY_NOTICES`.

- [ ] **Step 1: Write the notices file**

Fetch the two licenses verbatim:

```bash
gh api 'repos/alecthomas/chroma/contents/COPYING?ref=e4159240b179' --jq .content | base64 -d > /tmp/chroma-license
gh api 'repos/pygments/pygments/contents/LICENSE?ref=2.21.0' --jq .content | base64 -d > /tmp/pygments-license
```

Write `THIRD_PARTY_NOTICES` as: this header, then the Chroma section, then the Pygments section, each license text pasted verbatim with no trailing blank line at the end of the file:

```text
RFC Reader includes code adapted from the projects below. Their licenses ask for
these notices to accompany it.

Chroma (https://github.com/alecthomas/chroma)
The JSON and XML lexers in Packages/RFCKit/Sources/RFCKit/Highlighting are
adapted from Chroma's lexers/embedded/json.xml and xml.xml at commit
e4159240b179.

<the contents of /tmp/chroma-license>

Pygments (https://pygments.org)
Chroma's lexers are themselves converted from those of Pygments, whose license
follows (from Pygments 2.21.0).

<the contents of /tmp/pygments-license>
```

- [ ] **Step 2: Write the failing test**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/Chrome/AcknowledgementsTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Acknowledgements")
struct AcknowledgementsTests {
  /// The app shows what the repository says; one is the other.
  @Test func `the app's notices are the repository's`() throws {
    // Packages/RFCReaderKit/Tests/RFCReaderKitTests/Chrome/AcknowledgementsTests.swift
    let root = URL(filePath: #filePath)
      .deletingLastPathComponent()  // AcknowledgementsTests.swift
      .deletingLastPathComponent()  // Chrome
      .deletingLastPathComponent()  // RFCReaderKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // RFCReaderKit
      .deletingLastPathComponent()  // Packages
    let file = try String(contentsOf: root.appending(path: "THIRD_PARTY_NOTICES"), encoding: .utf8)
    #expect(Acknowledgements.text == file.trimmingCharacters(in: .newlines))
  }

  @Test func `they carry both licenses`() {
    #expect(Acknowledgements.text.contains("Chroma"))
    #expect(Acknowledgements.text.contains("Pygments"))
    #expect(Acknowledgements.text.contains("Permission is hereby granted"))
    #expect(Acknowledgements.text.contains("Redistribution and use in source and binary forms"))
  }
}
```

Run: `swift test --package-path Packages/RFCReaderKit --filter AcknowledgementsTests`
Expected: build failure — `cannot find 'Acknowledgements' in scope`.

- [ ] **Step 3: Write the text**

`Packages/RFCReaderKit/Sources/RFCReaderKit/Chrome/Acknowledgements.swift`:

```swift
/// The notices the licenses of code the app adapts ask for, shown in the About
/// panel on macOS and in Acknowledgements on iOS. The repository's
/// THIRD_PARTY_NOTICES, word for word; `AcknowledgementsTests` keeps them the same.
public enum Acknowledgements {
  public static let text = #"""
    <the whole of THIRD_PARTY_NOTICES, without its final newline>
    """#
}
```

Paste the file's text so that each line is indented four spaces relative to `public` (Swift strips the closing delimiter's indentation). If a license line runs past 200 characters with the indent, put `// swiftlint:disable:next line_length` above the `public static let`.

Run: `swift test --package-path Packages/RFCReaderKit --filter AcknowledgementsTests`
Expected: PASS.

- [ ] **Step 4: The About panel on macOS**

In `App/RFCReader/RFCReaderApp.swift`, add `AboutCommands()` to the `.commands { … }` block, before `WindowCommands()`, and define it beside `WindowCommands`:

```swift
  /// The About panel, crediting the code the app adapts, as its licenses ask.
  struct AboutCommands: Commands {
    var body: some Commands {
      CommandGroup(replacing: .appInfo) {
        Button("About RFC Reader") {
          let credits = NSAttributedString(
            string: Acknowledgements.text,
            attributes: [
              .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
              .foregroundColor: NSColor.labelColor,
            ])
          NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        }
      }
    }
  }
```

Wrap it in `#if os(macOS)` if `WindowCommands` is wrapped; import `RFCReaderKit` if the file does not.

- [ ] **Step 5: Acknowledgements on iOS**

`App/RFCReader/Views/AcknowledgementsView.swift`:

```swift
#if !os(macOS)
  import RFCReaderKit
  import SwiftUI

  /// The notices the licenses of code the app adapts ask for. iOS has no Settings
  /// screen of the app's own, so the list's menu opens this.
  struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        ScrollView {
          Text(Acknowledgements.text)
            .font(.footnote)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
      }
    }
  }
#endif
```

In `RFCListView.swift`: add `@State private var showsAcknowledgements = false` beside the view's other `@State` properties, inside `#if !os(macOS)` if they are platform-split. In `optionsMenu`, after `ListViewOptions(navigation: navigation)`:

```swift
        Section {
          Button("Acknowledgements", systemImage: "doc.text") {
            showsAcknowledgements = true
          }
        }
```

and on the view that carries `ToolbarItem(placement: .primaryAction) { optionsMenu }`, inside the same `#if !os(macOS)`:

```swift
      .sheet(isPresented: $showsAcknowledgements) { AcknowledgementsView() }
```

- [ ] **Step 6: Build both apps**

Run: `make build-app && make ios-sim`
Expected: both build with no warnings.

- [ ] **Step 7: Look at it on the Mac**

Run `make run`, choose RFC Reader ▸ About RFC Reader (through the accessibility API, not synthetic keystrokes), and check that the panel's credits show the notices. Then quit the app.

- [ ] **Step 8: Format, lint, commit**

```bash
make fmt && make lint
git branch --show-current
git add THIRD_PARTY_NOTICES Packages/RFCReaderKit App/RFCReader
git commit -m "Credit Chroma and Pygments, in the About panel and in Acknowledgements on iOS

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Measure

**Files:**
- Modify: `Tools/benchmarks/Benchmarks/RFCBenchmarks/RFCBenchmarks.swift`

- [ ] **Step 1: Add a lexing benchmark**

After the build benchmarks:

```swift
  // Every block RFC 8727 highlights, its 53 KB JSON block among them.
  Benchmark("Highlight: RFC 8727") { benchmark, blocks in
    for _ in benchmark.scaledIterations {
      for (text, type) in blocks {
        blackHole(Lexers.highlight(text, as: type))
      }
    }
  } setup: {
    try RFCXMLParser.parse(corpus.data("rfc8727.xml")).blocks.compactMap { block in
      guard case .preformatted(let content) = block,
        let type = ArtworkType.canonical(content.type), Lexers.language(of: type) != nil
      else { return nil }
      return (content.text, type)
    }
  }
```

- [ ] **Step 2: Compare against the baseline**

Run: `make benchmark BENCHMARK_ARGS='baseline compare before --filter "Build.*"'`
Expected, the budget: `Build: RFC 8727` and `Build: RFC 8927` p50 wall clock at most 10% above `before`; `Build: RFC 9110` and `Build: RFC 9000` within noise.

Run: `make benchmark BENCHMARK_ARGS='--filter "Highlight.*"'` and record its p50.

- [ ] **Step 3: If over budget**

The first lever: matching against a native Swift `String` may cost a bridge per search. In `Lexer.tokens(in:)`, build the source once with UTF-16 storage and search that:

```swift
    let source = NSString(characters: Array(text.utf16), length: text.utf16.count)
    let searched = source as String
```

and pass `searched` to `firstMatch(in:)`. Re-run the comparison. If it is still over, report the numbers and stop; do not loosen the budget.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add Tools/benchmarks
git commit -m "Benchmark highlighting RFC 8727's code

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

Put the measured numbers (before, after, budget) in the task report; Task 12 records them.

---

### Task 12: Docs, and the last check

**Files:**
- Create: `docs/decisions/2026-10-02-syntax-highlighting-is-one-regex-lexer-engine.md`
- Modify: `docs/ARCHITECTURE.md` (Decisions list; the "Highlighting" bullet under "Planned engines")
- Modify: `docs/VISION.md` (the Tier 1 row on ABNF and highlighting)
- Modify: `docs/superpowers/specs/2026-09-30-artwork-renderers-design.md`
- Modify: `docs/superpowers/specs/2026-10-02-syntax-highlighting-design.md`

- [ ] **Step 1: Write the decision record**

Follow the form of `docs/decisions/2026-10-01-artwork-is-classified-once-and-rendered-as-decorated-text.md`: a title, then an italic line with the date and the design it came from, then prose. Content:

- What is decided: one regex state-machine engine in RFCKit (`Lexer`), languages as rule tables (`JSONLexer`, `XMLLexer`) or, where a table cannot express it, a small highlighter on the engine (`HTTPMessageHighlighter`); `Lexers` is the one place a type names a language, by name or structured suffix.
- Why not Tree-sitter, JavaScript highlighters or TextMate grammars: copy the reasoning and the corpus table from the spec's "What the code is" and "Decision" sections.
- The engine's semantics: each state one alternation searched forward; unmatched characters plain; recovery at a newline; transparent and non-anchoring bounds; the size cap; possessive patterns.
- How the reader shows it: `Rendition.styled`, always on, outside the presentation choices, not a figure; colors from `SyntaxTheme.standard`, dynamic, each ≥ 4.5:1 on the card; the theme becomes a `ReadingStyle` member when it is a preference.
- The licenses: `THIRD_PARTY_NOTICES`, shown in the About panel and in Acknowledgements on iOS.
- The measurements from Task 11.

- [ ] **Step 2: Update ARCHITECTURE.md**

Add to the Decisions list, at the end:

```markdown
- [Syntax highlighting is one regex lexer engine](decisions/2026-10-02-syntax-highlighting-is-one-regex-lexer-engine.md)
```

Replace the "Highlighting" bullet under "Planned engines" with:

```markdown
- **Highlighting.** Built for JSON, XML and HTTP messages on one regex lexer engine in RFCKit (`Lexer`, `Lexers`), [as decided](decisions/2026-10-02-syntax-highlighting-is-one-regex-lexer-engine.md); further languages are rule tables on it. ABNF's rule links come from the strict `ABNF` parser instead (#185), and untyped blocks are not guessed at.
```

- [ ] **Step 3: Update VISION.md**

In the Tier 1 row on ABNF and syntax highlighting, replace "A small regex tokenizer per language in RFCKit produces tokens the renderer colors." with "One regex lexer engine in RFCKit, with a rule table per language, produces tokens the renderer colors; JSON, XML and HTTP messages first."

- [ ] **Step 4: Amend the artwork renderers design**

In `docs/superpowers/specs/2026-09-30-artwork-renderers-design.md`, add under its italic header paragraph:

```markdown
*Amended 2 October 2026 by the syntax highlighting design (`2026-10-02-syntax-highlighting-design.md`): the styled-text rendition is `Rendition.styled`, not `.text`; colors are stored in the text as dynamic colors at build time, as every other color the builder sets is, rather than as roles resolved at draw time; and highlighted code is outside the presentation choices — "Draw diagrams" and "Show as Text" are about drawings.*
```

- [ ] **Step 5: Bring the syntax highlighting design up to date with what was built**

In `docs/superpowers/specs/2026-10-02-syntax-highlighting-design.md`:
- In the `Lexer` bullet: replace "At each position the first rule of the current state that matches there wins." with "Each state is compiled to one alternation and searched forward from the current position: the first rule that matches at the earliest position wins, and the characters before it are unmatched."
- In the coverage item: replace "A rule whose groups nest, or that can leave a group unmatched, is rejected when its lexer is built" with "A rule whose groups nest, or that refers back to a group, is rejected when its lexer is built; a group that matches nothing emits nothing".
- In `.standard`: replace "punctuation and comments in the secondary label color" with "punctuation and comments in a muted gray (the secondary label color is about 4:1 on the card)".
- In "Acknowledgements": replace "bundled as a resource of RFCReaderKit" with "kept in RFCReaderKit as `Acknowledgements.text`, which a test holds equal to the file".

- [ ] **Step 6: The last check**

Run: `make check`
Expected: PASS.

Run: `make test-corpus`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git branch --show-current
git add docs
git commit -m "Record syntax highlighting's decision, and bring the docs up to date

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
