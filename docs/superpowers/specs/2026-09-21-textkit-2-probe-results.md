# TextKit 2 probe results

Date: 2026-09-21
Machine: Apple M3 Pro, macOS 27.0 (build 26A428), arm64
Toolchain: Apple Swift 6.4 (swiftlang-6.4.0.34.1)

Measured with the throwaway `Tools/textkit-probe` package (deleted after this run; git history
keeps it at the commit that adds this file). Probes A and B ran headless — no window, no view —
against `corpus/xml/rfc5661.xml`: 968 sections, 1,303,608 characters in the approximated
attributed string (one paragraph per block, `plainText`, monospaced for preformatted). Probe C
fetched `https://www.rfc-editor.org/rfc/rfc9110.xml` and `.../rfc9114.xml` over the network.

## Probe A — deep jump

**Decision note (added after this probe ran):** the > 400 ms verdict below stands as measured.
The decision is to proceed with the single-storage TextKit 2 design as specified anyway, and to
revisit layout cost later as a paging optimisation. The measured numbers and the verdict itself
are unchanged.

Cold storage, lay out only as far as the last section (`ensureLayout` over the full document
range in one call, timed).

| Trial | Time |
|---|---|
| 1 (cold) | 551.5 ms |
| 2 (warm) | 532.5 ms |
| 3 (warm) | 539.3 ms |

**Verdict — gate table:**

| Deep jump, warm | Verdict |
|---|---|
| < 150 ms | Proceed. Re-measure on an iOS device in Task 9. |
| 150–400 ms | Proceed, but Task 9 must lay out asynchronously and show the jump target as soon as its fragment exists. |
| **> 400 ms** | **Stop.** Sequential layout is too expensive for reading-position restore on every open. Return to the spec: the remaining options are chunked storages per chapter, which weakens requirement 1, or accepting a visible delay on deep links. |

Both warm trials (532.5 ms, 539.3 ms) land in the **> 400 ms — Stop** band. Per the task
instructions, this is reported as a concern rather than acted on: the probe tool is not deleted
and no workaround is invented here. **The decision on how to proceed — chunked storages per
chapter, or accepting a visible delay on deep links — is the controller's, not this task's.**

## Probe B — restyle

Rebuild the approximated attributed string at the same measure and lay the whole document out
again from scratch (simulates a font-size change).

| Trial | Time |
|---|---|
| 1 (cold) | 610.7 ms |
| 2 (warm) | 545.4 ms |
| 3 (warm) | 624.0 ms |

**Debounce for Task 9's font-size slider:** the higher of the two warm trials, 624.0 ms, rounded
up to the next 50 ms → **650 ms**.

## Probe C — table grid/stacked threshold

Real font metrics (17 pt system font), two measures: 712 pt (760 pt frame minus 24 pt padding
each side) and 320 pt (narrow iPhone). Gutter 16 pt between columns.

### RFC 9110 (12 tables)

| Table | Columns | Total width | Shape @ 712 pt | Shape @ 320 pt |
|---|---|---|---|---|
| 1 | 3 | 765 pt | stacked | stacked |
| 2 | 3 | 451 pt | grid | stacked |
| 3 | 4 | 434 pt | grid | stacked |
| 4 | 3 | 826 pt | stacked | stacked |
| 5 | 2 | 301 pt | grid | grid |
| 6 | 2 | 727 pt | stacked | stacked |
| 7 | 4 | 307 pt | grid | grid |
| 8 | 3 | 361 pt | grid | stacked |
| 9 | 4 | 472 pt | grid | stacked |
| 10 | 3 | 804 pt | stacked | stacked |
| 11 | 3 | 722 pt | stacked | stacked |
| 12 | 4 | 573 pt | grid | stacked |

### RFC 9114 (5 tables)

| Table | Columns | Total width | Shape @ 712 pt | Shape @ 320 pt |
|---|---|---|---|---|
| 1 | 5 | 622 pt | grid | stacked |
| 2 | 3 | 314 pt | grid | grid |
| 3 | 4 | 490 pt | grid | stacked |
| 4 | 4 | 785 pt | stacked | stacked |
| 5 | 4 | 358 pt | grid | stacked |

### Comparison against the spec's character estimate

The design spec's "Tables as text, in one of two shapes" section predicted, from character
counts alone, that RFC 9110's tables 1, 4 and 6 (105–116 characters, each with an 87–92 character
prose column) would come out stacked at the 712 pt measure, and that most of RFC 9114's tables
would come out grid. Both hold with real font metrics:

- RFC 9110 tables 1, 4, 6 are stacked at 712 pt, exactly as predicted.
- RFC 9114: 4 of 5 tables (1, 2, 3, 5) are grid at 712 pt; only table 4 is stacked — "most... grid"
  holds.
- At 320 pt, nearly everything is stacked: only RFC 9110 table 5 and RFC 9114 table 2 stay grid.

Task 7 asserts against the per-table verdicts above.

## Files

- Probe source (now deleted, recoverable from git history at this commit):
  `Tools/textkit-probe/Package.swift`, `Tools/textkit-probe/Sources/textkit-probe/main.swift`.
