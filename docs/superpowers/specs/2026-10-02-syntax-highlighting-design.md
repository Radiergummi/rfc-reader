# Syntax highlighting — design

*2 October 2026. Approved in brainstorming, section by section. Covers the shared lexer engine and
the first slice, JSON, XML and HTTP messages, as roadmap item 3 of the artwork renderers design
(`2026-09-30-artwork-renderers-design.md`), on whose pipeline it builds. ABNF (roadmap item 2, #185)
stays on the strict `ABNF` parser and is not part of this slice.*

## Why

Source code in RFCs is set as plain monospaced text. Highlighting makes a JSON object, an XML
instance or an HTTP exchange readable at a glance, and the reader's principle that structure should
be visible applies to code as much as to prose. The aim is not one highlighter per language but one
engine, with each language a small definition, so that adding a language is cheap and the engine's
performance is tuned once.

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

More than half are IETF formats few general-purpose highlighters know. Blocks are usually fragments:
one ASN.1 type, a YANG excerpt, a message without its body.

## Decision: one regex lexer engine, not Tree-sitter

Options considered:

- **JavaScript highlighters** (Highlightr, HighlightSwift: highlight.js in JavaScriptCore). Ruled out
  by VISION.md, and JavaScriptCore does not exist on Linux, where RFCKit is tested.
- **Tree-sitter** (SwiftTreeSitter). Fastest and builds on Linux, but mature grammars exist only for
  JSON, XML, C, Python and YAML. For ABNF, ASN.1, YANG, CDDL, XDR and SDP, GitHub has hobby grammars
  of 0–6 stars or none; cbor-diag, rbnf and tls-presentation have none. Every IETF format would be a
  grammar to write, and a grammar expects a whole file, so fragments degrade into `ERROR` nodes.
- **TextMate grammars.** The widest grammar ecosystem, but no maintained Swift engine, and they
  depend on Oniguruma's regex semantics.
- **Regex state-machine lexers**, as Pygments, Rouge and Chroma use. A shared engine; a language is
  an ordered list of rules per state. Definitions exist to translate from: Pygments (BSD) has ABNF,
  ASN.1, CDDL, HTTP, JSON, XML, YANG and C; Chroma (MIT) has ABNF, YANG, JSON, XML and C as data.
  All 129 patterns of Chroma's `abnf`, `yang`, `json`, `xml` and `c` lexers compile with
  `NSRegularExpression` unchanged. A lexer has no notion of a whole file, so fragments cost nothing.

The regex lexer engine is chosen. Highlighting is lexical; where a feature needs structure, such as
ABNF rule links, a dedicated parser serves it (`ABNF`), as the artwork roadmap already plans.

## Design

### RFCKit (tested on Linux)

- **`TokenKind`**: `keyword`, `string`, `number`, `comment`, `name` (a JSON key, an XML tag, an HTTP
  header name), `attribute`, `punctuation`, `plain`. Semantic, not visual: what a token is, never
  how it looks.
- **`SyntaxToken`**: `{ range: NSRange, kind: TokenKind }`. Ranges are UTF-16, relative to the
  block's text, as `DecoratedText`'s are.
- **`Lexer`**, the engine. A lexer is a set of named states, each an ordered list of
  `Rule(pattern, action)`, starting in `root`. An action emits one kind, or one kind per capture
  group; it may push a state, pop one, or hand the matched range to another lexer. At each position
  the first rule of the current state that matches there wins (`NSRegularExpression`, `.anchored`).
  A character no rule matches is `plain`, and lexing goes on, so the engine never fails and the
  tokens cover the text exactly once. Patterns are compiled lazily, once per process.
- **`Lexers.json`, `Lexers.xml`, `Lexers.httpMessage`**: Swift literals, translated from Chroma or
  Pygments, each with a comment naming its source and license. The HTTP lexer hands a message's body
  to the JSON or XML lexer when its `Content-Type` is `application/json`, `application/xml`,
  `text/xml`, or ends in `+json` or `+xml`; any other body is `plain`.
- **`Lexers.for(_ type: ArtworkType) -> Lexer?`**: the one place a type names a lexer.
  `http-message` and `message/http` are HTTP; `json`, `application/json` and `+json` media types are
  JSON; `xml`, `application/xml`, `text/xml` and `+xml` are XML.

### RFCReaderKit

- **`Rendition.styled(StyledText)`**, the case the artwork design reserved. `StyledText` carries the
  block's tokens; the text is the block's, unchanged.
- **`SyntaxPresentation.entry`**: one `RendererEntry` claiming the lexed types, registered in
  `ArtworkRenderers.entries` beside `PacketPresentation`. Its presentation lexes the block and
  returns `.styled`; it declines a type `Lexers.for` has no lexer for.
- **`SyntaxTheme`**: a `TokenKind` → color map, so that colors are configurable later (pickers in
  Settings, a color-blind variant) by handing in another theme. Nothing about the theme is persisted
  or shown in Settings in this slice. `.standard` is restrained, for a reader where code supports
  prose: punctuation and comments in the secondary label color, names in system indigo, strings in
  system green, keywords, numbers and attributes in one restrained system tone, plain in the label
  color. All are dynamic system colors, so dark mode and print's light appearance need no rebuild.
- **The theme reaches `DocumentTextBuilder` through the build inputs**, as `PresentationChoices`
  does, so print, export and previews show what the reader shows. A theme change is a rebuild, like
  any reading preference.
- **`DocumentTextBuilder+Verbatim`** sets a `.styled` block exactly as verbatim text today — font,
  scaling, card, `VerbatimBox`, caption — and adds a `.foregroundColor` per token. Only attributes
  change, so find, selection, copy and VoiceOver read what they read today.

### Behavior

- Only blocks with a declared type are highlighted. Untyped blocks and converted legacy text are
  unaffected in this slice.
- "Draw diagrams" does not gate highlighting: code is not a diagram. A block's own "Show as Text"
  still sets it plain, and "Show as Figure" brings the highlighting back.

## Testing

- **Lexer guard-level tests** (RFCKit, Swift Testing), one suite per language. A lexer is a pure
  function of a block's text, so these take hand-written snippets in the shape of the format, never
  quoted from an RFC. They pin what a reader sees: a JSON key is `name` and its value `string`; an
  XML attribute is `attribute`; an HTTP header name is `name`; a JSON body after
  `Content-Type: application/json` is lexed as JSON.
- **Engine tests**: tokens cover the text exactly once, with no gaps or overlaps; input no rule
  matches becomes `plain`; push and pop; every pattern of every lexer compiles.
- **`Corpus-backed: syntax highlighting`**, over RFCXML documents read through `CorpusText` from
  `RFC_CORPUS_XML` and listed in `CORPUS_TEST_XML_DOCUMENTS`: RFC 9110 (59 `http-message` blocks),
  RFC 9457 (HTTP messages with JSON bodies), RFC 8927 (176 `json` blocks) and RFC 9022 (66 `xml`
  blocks). It checks that coverage stays exact on real input, that a block that parses as JSON
  (`JSONSerialization`) leaves nothing `plain` but whitespace, and that no block takes
  pathologically long, against catastrophic backtracking.
- **Builder tests** (RFCReaderKit): a `.styled` block's text is the verbatim block's; each token's
  range carries its theme color; a custom `SyntaxTheme` in the build inputs reaches the storage.
  ``BuilderCompletenessTests.`nothing becomes an attachment` `` stays green.

## Measurement

A `Tools/benchmarks` entry lexes the blocks of the four corpus documents. The builder benchmark is
compared before and after (`BENCHMARK_ARGS='baseline update before'`, then `'baseline compare
before'`); success is a builder benchmark flat within noise.

## Docs

- `docs/ARCHITECTURE.md`: "Decision: syntax highlighting is one regex lexer engine", dated, with the
  reasons above and the corpus counts.
- `docs/VISION.md`: the Tier 1 row's "a small regex tokenizer per language" becomes one engine with a
  definition per language.

## Later

Each its own plan: ASN.1, YANG, CDDL and C from Pygments or Chroma; cbor-diag, SDP, XDR, rbnf and
tls-presentation, which have no lexer to translate; `pseudocode` and untyped blocks, which need a
decision about guessing; `yangtree` and `test-vectors`, which are artwork-like and may be decorated
text instead; theme settings.
