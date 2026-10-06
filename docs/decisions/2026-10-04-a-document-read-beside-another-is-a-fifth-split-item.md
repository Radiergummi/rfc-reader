# A document read beside another is a fifth split item, and the two scroll by aligned sections

*Decided October 2026 (issue #187), on the maintainer's answers to the design questions on the issue.*
A document can be read beside the one it obsoletes, or the one obsoleting it: RFC 7231 beside RFC 9110.
The two readers scroll together, section by section.

**Only along an obsoletes edge.**
The counterparts come from `SectionAlignment` (#388), which pairs the sections of a successor with those of the document it obsoletes.
Two unrelated documents have no counterparts to scroll by, and would only scroll apart, which two windows already do; File ▸ Open Beside for any document is left out for now.
A draft's revisions have no obsoletes edge either, and come with the diff view.

**The alignment is computed on the device.**
The corpus writes it to the `successions` table of `indexes.sqlite`, but nothing in the app installs or reads that database yet, and the app has no SQLite dependency.
Both documents are loaded anyway, and `SectionAlignment.pairs(among:)` is a pure RFCKit function over them, so it runs in an `@concurrent` job once the comparison opens (`SideBySide.align`).
Measured on the issue, in a release build: 7231 ↔ 9110 0.23 s, the whole HTTP group (7230, 7231, 9110, 9112) 0.41 s.
The old document's other successors and the new one's other predecessors are aligned alongside where they are already on the device (`SideBySidePair.alignedAmong`): a section's counterpart is its best match across every edge aligned together, and the decision record for the alignment found 7230's message syntax paired with its nearest, wrong, 9110 section when 9112 was left out.
`AlignedScrolling` takes rows, so reading the table can replace the source later.

**How the other side follows** is `AlignedScrolling`, in RFCReaderKit: the counterpart of the section the leading reader's line is in, as far through it, in characters, as the leading line is through its own section.
A section with no counterpart holds the other reader still, and says so in the bar under the reader beside.
**Which side leads** is `ScrollCoupling`: the reader used last, by a scroll wheel or trackpad, a click in its text, a drag on iOS, or a place it was sent to.
Only the leader's moves are followed, so the follower's own move, which reports a new place too, and a rebuild of it after a resize, move nothing back.
Each reader keeps its own text storage and `RFCTextView`; what couples them is the coordinator's `CoupledReader` conformance, which reports the line and follows through the layout engine's jump.

**The reader beside is a second `DocumentView`** with its own `NavigationModel` and `ReaderState` (`SideBySide`), so it loads, builds and scrolls as any reader does, and what it reports reaches neither the window's toolbar nor its panel, which stay the window's reader's.
It opens where the window's reader's counterpart is, not at its own saved place.
A link it follows to a third document ends the comparison and opens that document in the window's reader; so does reading another document in the window's reader.

**On macOS it is a fifth split item.**
This changes the standing rule that a window's split controller has four items (`2026-09-22-the-window-layer-is-appkits-on-macos.md`).
The item is inserted after the reader only while comparing, and removed after.
Its hosted root is given the four models explicitly, as every hosted root is, with the reader beside's own navigation and reader state in place of the window's.
It refuses the safe area as the reader's root does, since the panel now opens over it.
The alternative, two readers inside the reader item's hosted root, would have been simpler for the coupling, but would have shared one contents panel and one inspector between two documents.

**While comparing, the sidebar and the list are collapsed**, and the window's floor is two readable panes, 840 pt, and nothing else (`ReaderLayout.minimumWindowWidth(panelIsOpen:comparing:)`).
Kept open, the two columns' 480 pt on top of two readers made the floor 1320 pt, wider than a 1280 pt display, half of a wide one, or a full-screen window, and the window was forced past the screen.
Decided by the maintainer on the pull request (#661), over keeping them open and over a narrower floor for each reader.
When the comparison ends, each column goes back to how it was before, unless the reader opened it in the meantime, in which case it stays open (`ColumnSetAside`).
Opened while comparing, the two narrow the readers rather than widen the window.
The list cannot be dragged open, so in practice that is the sidebar, through its toolbar button.

**On iPad** the detail column is split in two, in a regular width only.
The contents panel belongs to the pair, not to the window's reader: the two readers sit inside `DocumentView`'s chrome, so the panel opens beside both rather than between them (#661).
**On iPhone** it is not offered.

**Verified** on macOS 27, with a probe that opened RFC 7231, compared it with 9110 and drove both readers through `jump(toSection:)`: 7231 §5.3.2 put the reader beside at 9110's `field.accept`, §3.1.1.5 at `field.content-type`, §6.5.1 at `status.400`, §4.3.1 at `GET` and §7.1.1.1 at `http.date`; led from the reader beside, 9110's `status.404` put 7231 at §6.5.4, and `field.content-type` and `GET` back at §3.1.1.5 and §4.3.1.
Closing the comparison removed the fifth item.

**What following costs.**
The same probe scrolled the leading reader 300 steps of 40 pt, one every 16 ms, in a Release build, and timed each step with the follower's move in it.
Reading alone: 0.7 ms a step at the median.
Following with a jump, as a link does, settling the line each time: 7 to 20 ms.
Most of that was the follower reading back its own line from where its viewport had been, by walking the fragments in between, twice a step.
The follower now reports the line it was put at (`reportVisibleAnchor(placed:)`), and pins it rather than settling once its document is laid out (`ReaderLayoutEngine.follow(toOffset:)`): 1.9 to 2.7 ms at the median, 4 ms at the 95th percentile.
