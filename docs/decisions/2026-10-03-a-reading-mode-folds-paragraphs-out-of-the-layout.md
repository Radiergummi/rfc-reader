# A reading mode folds paragraphs out of the layout, not out of the storage

*Decided October 2026 (issue #188, its first part #698).* A reading mode shows less of a document: Outline shows its headings. Focus and Implementer, the next two parts, build on the same mechanism. None of them changes the text storage. The reader body stays one text storage, built once. A mode decides which of its paragraphs are laid out.

**How it hides.** TextKit 2 asks the content manager's delegate whether to enumerate each paragraph as it lays the text out (`textContentManager(_:shouldEnumerate:options:)`). `FoldingDelegate`, the reader's content storage's delegate, answers no for a hidden paragraph, which then makes no layout fragment. Every offset, anchor, `AnchorIndex` entry and reading position is the same in every mode, so a switch keeps them. Find, Copy, print, export and VoiceOver's reading work on the whole document.

**Which paragraphs** is `Folding.hidden(in:)` in RFCReaderKit, a pure function of the build and tested against built fixtures. The App target only answers the delegate from it. The delegate is not bound to the main actor, because TextKit enumerates and draws off the main thread too. What it holds is behind a lock.

**The reader's line.** A switch lays the document out again through the layout engine (`ReaderLayoutEngine.refold`), as a column change does, with the reader's line kept on top. A line in a paragraph the mode hides is kept at the shown paragraph before it, which in Outline is its section's heading (`HiddenText.shownOffset(atOrBefore:)`). A jump, a deep link or a find hit into folded text expands the section it lands in first.

**Outline.** Headings only. Each heading's fragment draws a disclosure chevron in the gutter (`FragmentGeometry.disclosureChevron`), and a click or tap on a heading opens its section's own text, up to the next heading, in place. The mode and the expanded sections are the window's, in `ReaderState.folding`. The mode stays from one document to the next; the expanded sections do not, and none of it is kept.

**Measured** on macOS 27 over RFC 9110, with a probe that set the mode and drove the reader through its scripting dictionary:
- Outline hides 293 runs of paragraphs. The text view is 15,215 pt tall, against 198,823 pt in Normal.
- Jumps to §8.3, §15.5.1, §12.5.1, §5.6.2, §1.1 and §17.16 land where they do in Normal.
- Opening at a paragraph inside §8.3 expands exactly that section and lands there.
