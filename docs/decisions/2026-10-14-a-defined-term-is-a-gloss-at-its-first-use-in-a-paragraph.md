# A defined term is a gloss at its first use in a paragraph, not a link

*Decided 14 October 2026 (issue #396), with the agreements made on #176 on 28 September.*

The reader marks a term the document defines (`RFCDocument.definedTerms`, #176) where the document uses it, so its definition can be read without leaving the place: a dotted underline in the secondary color, quieter than a link's, the long-standing convention for a defined term or an abbreviation.

**It is a gloss, not a link.** A marked term carries `.rfcGloss`, a `GlossBox` per use, and no `.link`: a click on it selects, as on any text. Its card shows the term and its definition on hover and force click on macOS and on long press on iOS, as a reference's card does (the 26 September decision), and **Go to Definition** in its menu, the Mac's context menu and the long-press menu, follows the definition's anchor, so Back returns. A link to the definition was the cheaper choice, all of a reference's handling reused; the maintainer chose the gloss, which abbreviations are to share (#67), and which has no anchor of its own to link to there. A hover target is therefore a reference or a gloss (`HoverTarget`), told apart by its box.

**Only the first use in each paragraph is marked**, matched case-sensitively, as a whole word, the longest term where two start at the same word. Not in a heading, a table cell, a definition list's term, inline code, a link or a reference, nor in the term's own definition; and not on paper, where there is no card to show.

**A term of one word that is a common English word is not marked.** `client` or `message` is known to every reader, defined by nearly every document its own way, and would be underlined in nearly every paragraph. The common words are the lower-case words used in prose in at least a tenth of the corpus's documents, `corpus-build common-words` over the 9,835 documents of 14 October: 1,606 words, committed as RFCReaderKit's `CommonWords.txt`, a word list and no RFC text. An acronym is never one, being no lower-case word, and a term of several words is always marked, whatever its words.

| Share of documents | Common words | Defined single-word spellings skipped (of 2,190) |
|---|---|---|
| 0.5% | 8,395 | 111 |
| 2% | 4,530 | 91 |
| 5% | 2,650 | 72 |
| **10%** | **1,606** | **51** |
| 20% | 797 | 26 |
| 30% | 452 | 17 |

At a tenth it skips the vocabulary of every protocol, `key`, `address`, `message`, `server`, `client`, `header`, `packet`, `connection`, `peer`, `byte`, `proxy`, `gateway`, `endpoint`, and keeps what a document defines that a reader benefits from: `upstream` and `downstream` (8.5%), `datagram`, `handshake`, `relay`, `cipher`, `plaintext`. The threshold is `COMMON_WORDS_THRESHOLD` in the Makefile; `corpus/common-words.json` reports the others.

The bar to show terms at all was 95% of a hand-read sample defined correctly; #840 measured 98 of 100.
