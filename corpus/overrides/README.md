# Overrides

Per-document corrections to what `corpus-build convert` makes of a legacy RFC, one file per document, named `rfcNNNN.xml`. Fix the heuristic in RFCKit when a whole class of documents is wrong; correct a single document here.

## Patches

An override is a patch in the format of [RFC 5261](https://www.rfc-editor.org/rfc/rfc5261) (An XML Patch Operations Framework Utilizing XPath Selectors): a `<diff>` root holding `<add>`, `<replace>` and `<remove>` operations. `convert` converts the document as it would any other, applies the operations in order, each to the result of the one before, and parses and writes the result again, so the published XML is the same canonical form as every unpatched document's. Its generator comment names the patch.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<diff>
  <!-- The page dates RFC 5 June 2, 1969; the index gives only the month (#172). -->
  <add sel="/rfc/front/date" type="@day">2</add>
</diff>
```

| Operation | What `sel` selects | What it holds |
|---|---|---|
| `<replace sel>` | an element, an attribute or a text node | exactly one element, or text for an attribute or a text node |
| `<remove sel>` | an element, an attribute or a text node | nothing |
| `<add sel pos>` | an element | its new children. `pos` is `append` (the default), `prepend`, `before` or `after`. With `type="@name"`, the text is that attribute's value |

Two deviations from the RFC: selectors are full XPath 1.0, not its restricted subset, so an operation can select by content; and there is no `ws`, since the output is written again, which normalizes whitespace. Whitespace at the edges of an operation's content only lays the patch out and is dropped, from an attribute's value too; whitespace between two elements is kept, since it is what keeps two inline elements' words apart.

A patch fails, and the run with it, when:

- a selector matches no node, or more than one;
- the node does not suit the operation: `add pos="before"` on the root, or `replace` of an attribute with an element;
- the file holds an operation or an attribute this does not know, so a typo like `postion=` fails rather than appending, or holds no operation at all;
- writing the patched document again would lose some of its text, because the patch added something the document model cannot hold;
- an operation changes nothing in the written output, because writing undid it, such as an attribute the writer derives. Each operation is checked on its own, so one that writing undoes cannot pass behind another that takes effect.

A failed document gets no output, an earlier run's is removed, and `convert` logs every failure, records each in `report.json` and exits non-zero once all documents are converted. `make corpus-overrides-check` converts only the overridden documents and runs on every pull request, so a parser change that breaks a patch fails its own pull request; `make corpus-convert` runs it first.

## Writing one

- **Fix structure, never wording.** Every converted file says "the text itself is unchanged"; errata are the channel for wording. The header's metadata comes from the RFC index (#170, #218); a patch adds only what the page states and the index lacks, such as a day.
- **Carry no RFC text but the minimal text a misclassification took.** Selectors locate by a few words, as below. Content may hold RFC text only to restore what the converter misclassified and the patch has to remove, such as the words of a line that converted inside an artwork: those words and nothing more, never a sentence that was converted correctly, never surrounding context. This is the one exception to the rule that no RFC text is committed (`CLAUDE.md`); `rfc5.xml` is the example.
- **Precede each operation with a comment** giving the reason and the issue it fixes.
- **Select by anchor first, then by content**, as in `artwork[starts-with(normalize-space(), ':DEL')]`, since the text is frozen even where structure is not. **Never by position** (`section[3]/t[4]`): a parser change shifts every count. A legacy anchor is not fully stable either: it is `name-` and the slug of the detected heading, and moves when detection does. `preamble` is the one fixed anchor.
- **A patch shape that recurs in about three documents is a parser bug**, not an override. Fix the heuristic (see `CLAUDE.md`) and delete the patches.
- **When a parser change breaks an operation**, check first whether the change made it unnecessary. Often the node it corrected is now right, and the fix is to delete the operation.

The source texts are never committed: `make corpus-overrides-check` fetches the ones it needs into `corpus/overrides-check.noindex/`, out of the way of a corpus run, `make test-corpus` its own into `corpus/text.noindex/`, and the RFC index into `corpus/rfc-index.xml` when it is missing. `make corpus-fetch` downloads a fresh index over it.

## The snapshot

`rfc1142.xml` is the one override that is a whole document (an `<rfc>` root), published in place of the converter's output after checking that it parses; one that does not fails its document as a failed patch does. Its correction rejoins words that RFC 1142's form feeds split in the plain text, before conversion, which a patch on the output cannot do. `rfc1142.py` makes it, so the correction can be reviewed and rerun rather than trusted. A snapshot is the converter's output frozen, so a converter change can leave it stale: `make corpus-override-scripts-check` reports whether it is. Its script's new output is not committed, because that would be a fresh snapshot of RFC text (#243), and no new snapshot is added.
