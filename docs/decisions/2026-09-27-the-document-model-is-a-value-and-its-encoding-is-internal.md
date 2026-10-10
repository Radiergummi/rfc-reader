# The document model is a value, and its encoding is internal

*Decided September 2026 (issue #130).*
Every type from `RFCDocument` down to `Inline` is `Hashable` and `Codable`, all synthesized, so a test compares documents whole, the corpus can be diffed structurally, and a parsed model can be kept.
What stood in the way was one field: `Reference.seriesInfo` was an array of labeled tuples, which can be none of `Equatable`, `Hashable` or `Codable`, and so kept every type that held a reference from being any of them.
It is `[SeriesInfo]` now.
`CrossReference.Display` stays `Equatable` only, because it is computed for rendering rather than parsed.

The encoded form is not a format.
Nothing persists it, and a synthesized decoder requires every key, so adding a field, even one with a default such as `abbreviations`, or renaming a case or an associated-value label breaks every payload written before.
Whatever first keeps encoded models versions the cache and discards it on a mismatch; committing to a stable format, with migrations, is that change's decision.

`Block` and `Inline` are no longer `indirect`: every recursive case already goes through an array, so the compiler needs no box.
That trades pointers for inline payloads, measured: a `Block` is 88 bytes of array stride instead of 8 and an `Inline` 64, and the parsed model of RFC 9271 takes 31% more heap (415 to 544 KB), RFC 9842 23% and RFC 793 7%, with no measurable difference in a full corpus conversion.
Should that start to matter, `indirect` on the largest cases alone (`table`, `crossReference`, `link`) is the cheaper form.
