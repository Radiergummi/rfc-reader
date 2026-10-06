# A reading mode folds paragraphs out of the layout, not out of the storage

*Decided October 2026 (issue #188, its first part #698).*
A reading mode shows less of a document: Outline shows its headings.
Focus and Implementer, the next two parts, build on the same mechanism.
None of them changes the text storage.
The reader body stays one text storage, built once.
A mode decides which of its paragraphs are laid out.

**How it hides.**
TextKit 2 asks the content manager's delegate whether to enumerate each paragraph as it lays the text out (`textContentManager(_:shouldEnumerate:options:)`).
`FoldingDelegate`, the reader's content storage's delegate, answers no for a hidden paragraph, which then makes no layout fragment.
Every offset, anchor, `AnchorIndex` entry and reading position is the same in every mode, so a switch keeps them.
Find, Copy, print, export and VoiceOver's reading work on the whole document.

**Which paragraphs** is `Folding.hidden(in:)` in RFCReaderKit, a pure function of the build and tested against built fixtures.
The App target only answers the delegate from it.
The delegate is not bound to the main actor, because TextKit enumerates and draws off the main thread too.
What it holds is behind a lock.

**The reader's line.**
A switch lays the document out again through the layout engine (`ReaderLayoutEngine.refold`), as a column change does, with the reader's line kept on top.
A line in a paragraph the mode hides is kept at the shown paragraph nearest it: the one before it, which in Outline is the nearest shown heading, or for folded text before any heading the first shown after it (`HiddenText.shownOffset(near:)`).
A jump, a deep link or a find hit into folded text expands the section it lands in, and every section it is nested in, and puts the line there in one layout.
The coordinator ignores the scene's folding from before that change until the scene has caught up, so the change is not folded back.
What folding needs of a build, where its paragraphs and headings are, is made once per build (`FoldingIndex`), not on every toggle.

**Outline.**
Headings only: the sections', and the abstract's, which has a heading but no section and is an entry of the outline of its own.
Each heading's fragment draws a disclosure chevron in the gutter (`FragmentGeometry.disclosureChevron`).
Closed, the outline shows the top-level headings and the abstract's.
A click on the chevron opens its section in place: its own text, up to the next heading, and its subsections' headings, each closed unless opened itself.
Closing it hides its whole subtree.
A heading is shown, with its chevron, only where every section it is nested in is open, which the entries' depths say.
On the Mac only the chevron toggles: a click on the heading's text is the text view's, for its links, a selection and a double-click on a word.
On iOS a tap on the heading toggles it too, after a link in it is followed.
The mode and the expanded sections are the window's, in `ReaderState.folding`.
The mode stays from one document to the next; the expanded sections do not, and none of it is kept.

**Implementer** (#700) folds no paragraph for its requirements: it draws a band behind each, so a switch changes no font and needs no rebuild.
Which sentences is the requirements index's (`Requirements`), and where they are in the build is `RequirementBands`, in RFCReaderKit: a requirement names its sentence and the anchor it lands on, not an offset, so each is found by its words alone, from its anchor to the end of its section's own text, since the build spaces, wraps and chips the same inlines its own way.
The bands are found off the main actor once per build and requirements, and only in Implementer.
The fragments find them where they find the disclosures, on the content storage's delegate, and draw them line by line, joined, under the chips (`FragmentGeometry.bandRects`).
The tint is a faint yellow, apart from a chip's accent and an aside's gray, at the most that keeps a link on it at 4.5:1 over the page and every card in both appearances.
Implementer becoming the outline opens the section the reader's line is in, as Focus becoming it does, since Implementer shows nearly the whole document and the line can be anywhere.

**Asides** fold in Implementer under a "Note" caption, the issue's one-line disclosure.
The storage has no line of its own for a collapsed aside to show, and the one TextKit 2 way to show a paragraph differently without touching the storage, the content storage delegate's `textContentStorage(_:textParagraphWith:)`, is unusable: probed headlessly on macOS 27, it took effect only after an edit notification, shrank the element's range to the substitute's length, and laid the next paragraph out a line too low.
So the builder sets the caption at the top of every aside, in every mode, as the maintainer chose on #700: reader-only, like a heading's backlink caption, left out of a copy and of print, and a word to VoiceOver.
Where the aside's own text opens with "Note:", "NOTE:" or "Notes:", that label gives way to the caption, so the card never says it twice; what counts as an aside is markup only, never a paragraph that merely starts "Note:".
Every character of an aside carries its ordinal (`.rfcAside`), which `FoldingIndex` finds the asides by.
In Implementer each aside's body, every paragraph after its caption, is folded, and the caption has the chevron, drawn in the gutter from the column's edge however far the caption is set in; a gutter click finds the paragraph by its layout fragment, not a character, for the same reason.
Switching into Implementer opens the asides the reader's line is in, and a jump into a closed aside opens it.
A requirement sentence the label opened is still found by `RequirementBands`, without the label's word (RFC 9110 and 9022 have them, which a corpus-backed suite pins).

**Measured** on macOS 27 over RFC 9110, with a probe that set the mode and drove the reader through its scripting dictionary:
- Outline hides 293 runs of paragraphs. The text view is 15,215 pt tall, against 198,823 pt in Normal.
- Jumps to §8.3, §15.5.1, §12.5.1, §5.6.2, §1.1 and §17.16 land where they do in Normal.
- Opening at a paragraph inside §8.3 expands exactly that section and lands there.
