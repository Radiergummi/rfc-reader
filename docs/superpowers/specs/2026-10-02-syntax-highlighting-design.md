# Syntax highlighting — design

*2 October 2026. Approved in brainstorming, section by section, then revised after an adversarial
review checked it against the code and the corpus. Covers the shared lexer engine and the first
slice, JSON, XML and HTTP messages, as roadmap item 3 of the artwork renderers design
(`2026-09-30-artwork-renderers-design.md`), on whose pipeline it builds. ABNF (roadmap item 2,
#185) stays on the strict `ABNF` parser and is not part of this slice.*

## Why

Source code in RFCs is set as plain monospaced text. Highlighting makes a JSON object, an XML
instance or an HTTP exchange readable at a glance. The aim is not one highlighter per language but
one engine, with each language a small definition, so that adding a language is cheap and the
engine's correctness and performance are worked out once.

## What the code is

Counted over the 9,835 documents in `corpus/xml.noindex` on 2 October 2026, by `<sourcecode
type=…>`:

| Type | Blocks | Type | Blocks |
|---|---|---|---|
| test-vectors | 1,304 | yang | 272 |
| json | 1,050 | cddl | 252 |
| *(no type, or empty)* | 1,257 | sdp | 236 |
| pseudocode | 673 | xdr | 196 |
| http-message | 503 | rbnf | 131 |
| asn.1 | 482 | cbor-diag | 127 |
| xml | 398 | tls-presentation | 111 |
| yangtree | 388 | abnf9110 | 102 |
| abnf | 292 | c | 96 |

More than half are IETF formats few general-purpose highlighters know. The first slice's types,
canonicalized (`json`, `+json`, `xml`, `+xml`, `http-message`, `message/http`, as `<sourcecode>` or
`<artwork>`), are 1,079 JSON, 398 XML and 520 HTTP blocks, and they are rarely well formed:

- **JSON:** 439 of 1,079 do not parse — 177 are members without their object, 62 elide with `...`,
  36 are folded (RFC 8792), 23 are HTTP messages typed `json`, and some break strings across lines
  by hand. The largest block is 53 KB (RFC 8727).
- **XML:** fragments, `...` elisions and unclosed elements are common (45 of RFC 9022's 66 blocks).
- **HTTP:** 221 of 520 are field lines with no start line; 49 start otherwise (an indented message,
  as in RFC 8935 and 8936, or a bare status such as `206 Partial Content`); 7 use HTTP/2
  pseudo-header fields; 9 hold more than one message. Only 174 have a `Content-Type`.
- **Folding:** 166 of these blocks are folded per RFC 8792 (41 JSON, 50 XML, 75 HTTP).

## Decision: one regex lexer engine, not Tree-sitter

Options considered:

- **JavaScript highlighters** (Highlightr, HighlightSwift: highlight.js in JavaScriptCore). Ruled out
  by VISION.md, and JavaScriptCore does not exist on Linux, where RFCKit is tested.
- **Tree-sitter** (SwiftTreeSitter). Fastest and builds on Linux, but mature grammars exist only for
  JSON, XML, C, Python and YAML. For ABNF, ASN.1, YANG, CDDL, XDR and SDP, GitHub has hobby grammars
  of 0–6 stars or none; cbor-diag, rbnf and tls-presentation have none. Every IETF format would be a
  grammar to write, and a grammar expects a whole file, so fragments — most of the corpus, above —
  degrade into `ERROR` nodes.
- **TextMate grammars.** The widest grammar ecosystem, but no maintained Swift engine, and they
  depend on Oniguruma's regex semantics.
- **Regex state-machine lexers**, as Pygments, Rouge and Chroma use. A shared engine; a language is
  an ordered list of rules per state. Rule tables exist to translate from: Pygments (BSD-2-Clause)
  and Chroma (MIT, itself largely converted from Pygments). All 129 patterns of Chroma's `abnf`,
  `yang`, `json`, `xml` and `c` lexers compile with `NSRegularExpression` — which shows only that
  they compile; Chroma's regexp2 and ICU differ in places (`$`, `\Z`), so a translated rule is
  tested, not trusted. A lexer has no notion of a whole file, so fragments cost nothing.

The regex lexer engine is chosen. Highlighting is lexical; where a feature needs structure, such as
ABNF rule links, a dedicated parser serves it (`ABNF`), as the artwork roadmap already plans.

## Design

### RFCKit (tested on Linux)

- **`TokenKind`**: `keyword`, `string`, `number`, `comment`, `name` (a JSON key, an XML tag, an HTTP
  field name or method), `attribute`, `punctuation`, `plain`. Semantic, not visual.
- **`SyntaxToken`**: `{ range: NSRange, kind: TokenKind }`. Ranges are UTF-16, relative to the text
  lexed.
- **`Lexer`**, the engine: named states, each an ordered list of `Rule(pattern, action)`, starting in
  `root`. An action emits one kind, or one kind per capture group; it may push a state or pop one.
  At each position the first rule of the current state that matches there wins. Its semantics are
  fixed, each pinned by an engine test:
  - **Matching** is at the position (`.anchored`) with `.withTransparentBounds` and
    `.withoutAnchoringBounds`, so lookbehind and `\b` see the characters before it and `^` matches
    only at a line's start. Patterns compile with `.anchorsMatchLines`, as Pygments' and Chroma's
    default to.
  - **Coverage:** the tokens cover the text exactly once, in order, without gaps or overlaps.
    Characters of a match outside every group are `plain`. A rule whose groups nest, or that can
    leave a group unmatched, is rejected when its lexer is built — a test builds every lexer.
  - **Zero-length matches** are allowed only for a rule that changes state; one that does not is
    rejected when the lexer is built, so lexing cannot loop.
  - **Pop at `root`** is ignored.
  - **Recovery:** a character no rule matches is `plain`; after one, lexing returns to `root` at the
    next newline, as Pygments does, so a stray `"` before an elision does not make the rest of the
    block a string.
  - **Bounds:** a block over 64 KB (above the corpus's largest, 53 KB) is not lexed. A match that
    fails with an error (ICU's backtracking limit) is treated as no match. String-like patterns are
    written possessive or atomic (`(?:[^"\\]++|\\.)*+`) so that they cannot backtrack.
- **Patterns are compiled once per lexer**, each lexer a `static let`, so no shared mutable cache is
  needed. The first commit confirms in Linux CI that corelibs' `NSRegularExpression` is usable from
  a `static let` under strict concurrency; RFCKit uses only Swift `Regex` today.
- **`Lexers.json`, `Lexers.xml`**: Swift literals translated from Chroma's rule tables (Pygments'
  `JsonLexer` is hand-written code today, not a table), each naming the exact upstream file and
  version in a comment.
- **`HTTPMessageHighlighter`**: hand-written, because neither upstream has HTTP as a rule table
  (Pygments' uses callbacks, Chroma's is Go code) and the body's lexer depends on a field's value,
  which rules cannot remember. It splits a block into messages — a start line, or a block's first
  line, begins one — and each message into its head and body at the first blank line. The head is
  lexed by `Lexers.httpHead`, a rule table that accepts a start line or none, leading whitespace,
  and pseudo-header fields. The body is lexed by `Lexers.for(ArtworkType.canonical(contentType))`
  when the head has a `Content-Type`, and is `plain` otherwise.
- **`Lexers.for(_ type: ArtworkType)`**: the one place a type names a highlighter, so the media-type
  rules live once. `http-message` and `message/http` are HTTP; `json` and `application/json` are
  JSON; `xml`, `application/xml` and `text/xml` are XML; otherwise an exact name wins over a
  structured suffix, so any `+json` or `+xml` type (`sdf+json`, `application/problem+xml`) is JSON
  or XML.
- **`ArtworkType` gains a `suffix`** (`json` for `application/problem+json` and `sdf+json`), parsed
  by `canonical`, and `ArtworkRenderers` looks up an exact name first, then the suffix. The test
  that no type is claimed twice covers suffixes too.

### RFCReaderKit

- **`Rendition.styled(StyledText)`**. `StyledText` carries the tokens. The artwork design called
  this case `.text`; `.styled` is the name, and that design is amended to say so.
- **`SyntaxPresentation.entry`**: one `RendererEntry` claiming `json`, `xml`, `http-message` and
  `message/http` by name and `json` and `xml` by suffix, registered in `ArtworkRenderers.entries`.
  It declines a block `Lexers.for` has no highlighter for, or that is over the size cap.
- **Highlighting is always on.** There is no global switch and no per-block switch: highlighted code
  is code, and there is no reason to read it plain. So a `.styled` rendition is outside
  `PresentationChoices` altogether — "Draw diagrams" and a block's "Show as Text" apply only to
  `.decorated` renditions. In `appendVerbatim`, that means:
  - a `.styled` block is shown as highlighted whatever the choices say;
  - it is **not a figure**: no `.rfcFigureItem` (so no long-press figure menu on iOS, no image copy
    or share) and no "Show as Text"/"Show as Figure" item in any menu;
  - it is **not centered**: centering keys on a `.decorated` rendition, not on `kind == .artwork`,
    since 17 HTTP messages are `<artwork type="message/http; …">`;
  - `VerbatimBox` records a highlighted block so that the menus and `AccessibleReading` can tell it
    from a figure; it has no `spokenLabel` and is not in the Diagrams rotor.
- **Highlighting follows the text shown.** A rendition's ranges are into the block's own text today,
  so a block shown unfolded (#64) is not decorated. Tokens are a function of the text alone, so
  `.styled` lexes the text as displayed, folded or not, and is exempt from that gate: a folded block
  is highlighted at every window width.
- **`SyntaxTheme`**: a `TokenKind` → color map, so colors can be configured later (pickers in
  Settings, a color-blind variant) by handing in another theme. In this slice the builder reads a
  static `SyntaxTheme.standard`, as it reads `RFCColors`; nothing is persisted or plumbed through
  the build inputs. When a theme becomes a preference it joins `ReadingStyle`, which keys the
  preview cache (`BuildKey`).
- **`.standard`** is restrained, for a reader where code supports prose: punctuation and comments in
  the secondary label color; names, strings, and keywords/numbers/attributes in three custom
  dynamic colors with light and dark values. Every token color reaches **4.5:1** against the
  verbatim card's fill in both appearances; a test in RFCReaderKit resolves the theme in light and
  dark and checks the ratios. A theme's colors must be dynamic, and the test checks that too.
  `plain` tokens keep the builder's body color for the context (`bodyColor`), which a block quote or
  aside changes.
- **Colors are stored at build time as dynamic colors**, as every other color in the storage is.
  Dark mode is a redraw; print builds, lays out and draws in the light appearance (`DocumentPDF`).
  The artwork design's "colors are roles, resolved at draw time" is amended to describe this.
- **Rich copy** on macOS keeps the token colors, resolved in the appearance copied from, as it does
  for links and the secondary label color today.
- **Unaffected:** find and the search index work from the plain text and the model, and copy as
  plain text, VoiceOver and selection read the block's characters, which do not change.

### Acknowledgements

Pygments' license requires its notice in the documentation or other materials of a binary
distribution, and Chroma's in all substantial portions; Chroma's tables descend from Pygments', so a
lexer translated from Chroma carries both. The project is AGPL-3.0, which is compatible with both.

- **`THIRD_PARTY_NOTICES`** at the repository root holds both license texts with their copyright
  lines, and each translated lexer names its upstream file and version.
- **The app shows them**, from the same text, bundled as a resource of RFCReaderKit:
  - macOS: the standard About panel's credits (`orderFrontStandardAboutPanel(options:)` with
    `.credits`);
  - iOS, which has no Settings screen of its own: an "Acknowledgements" item in the app's existing
    menu, opening a sheet with the notices as selectable text.

## Testing

- **Lexer guard-level tests** (RFCKit, Swift Testing), one suite per language. A lexer is a pure
  function of a block's text, so these take hand-written snippets in the shape of the format, never
  quoted from an RFC. They pin what a reader sees: a JSON key is `name` and its value `string`; an
  XML attribute is `attribute`; an HTTP field name is `name`, with or without a start line, indented
  or not; a body after `Content-Type: application/problem+json` is lexed as JSON; a second message
  in a block is lexed as one.
- **Engine tests**: coverage is exact; transparent and non-anchoring bounds; multiline anchors;
  per-group kinds with the rest `plain`; push and pop, and pop at `root`; recovery at the newline
  after an unmatched character; a zero-length rule that does not change state, and nested groups,
  rejected; every lexer builds.
- **Adversarial guard tests, in the regular suite**: a 100,000-character unterminated string, a
  deeply repeated `{` and `<`, and a block just over the size cap, each lexed in bounded time.
- **`Corpus-backed: syntax highlighting`**, over RFCXML documents read through `CorpusText` from
  `RFC_CORPUS_XML` and listed in `CORPUS_TEST_XML_DOCUMENTS`: RFC 9110 (HTTP without bodies), RFC
  9457 (`problem+json` and `problem+xml` bodies), RFC 8927 (valid JSON), RFC 8727 (the 53 KB JSON
  block), RFC 9635 (invalid and folded JSON, odd HTTP), RFC 9022 (fragmentary XML) and RFC 8935
  (indented HTTP). Every block: coverage is exact; no string token spans more than one line where
  the format has no multi-line strings; plain characters other than whitespace stay under a bound
  per block. A block that parses as JSON (`JSONSerialization`) leaves nothing `plain` but
  whitespace.
- **Builder tests** (RFCReaderKit): a `.styled` block's text is the verbatim block's; each token's
  range carries its theme color; a highlighted block carries no `.rfcFigureItem`, is not centered,
  has no `spokenLabel` and is not in `Rotors.diagrams`; "Draw diagrams" off and a `.text` choice
  for its key leave it highlighted; a folded block is highlighted at a width that unfolds it and one
  that does not; `plain` tokens keep the context's body color. The theme's contrast test, and
  ``BuilderCompletenessTests.`nothing becomes an attachment` ``, as above.
- **Acknowledgements:** a test that the bundled notices name Pygments and Chroma and carry both
  license texts.

## Measurement

`Tools/benchmarks` gains a lexing benchmark over the corpus documents above, and builder benchmarks
for RFC 8927 and RFC 8727, whose bodies are mostly code — the existing RFC 9110 and RFC 9000
builds have almost none. The budget: highlighting adds at most 10% to the RFC 8727 and RFC 8927
builds, measured with `BENCHMARK_ARGS='baseline update before'` and then `'baseline compare
before'`.

## Docs

- `docs/decisions/2026-10-02-syntax-highlighting-is-one-regex-lexer-engine.md`: the decision above,
  with the corpus counts, and `docs/ARCHITECTURE.md` describing the engine as built.
- `docs/VISION.md`: the Tier 1 row's "a small regex tokenizer per language" becomes one engine with a
  definition per language.
- The artwork renderers design, amended where this one departs from it: `.styled` for `.text`,
  colors stored as dynamic colors, and highlighting outside the presentation choices.

## Later

Each its own plan: ASN.1, YANG, CDDL and C; cbor-diag, SDP, XDR, rbnf and tls-presentation, which
have no rule table to translate; `pseudocode` and untyped blocks, which need a decision about
guessing; `yangtree` and `test-vectors`, which are artwork-like and may be decorated text instead;
theme settings.
