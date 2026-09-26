#!/usr/bin/env python3
"""Regenerates rfc822.xml, the hand-corrected RFC 822 (issue #171).

RFC 822 sets every line of its title page as a run of its own, between blank lines,
and no other document does. The front matter takes the run that states the number
(`RFC #  822`) for the header block and the next one for the title, so the title
came out as `Obsoletes:  RFC #733  (NIC #41952)` and the document obsoleted nothing.
Its headings are indented like its body, so no heading ends the lead-in, and the rest
of the title page -- the reviser, his address, the contents' `APPENDIX` and the
footer of the contents page -- opened the body.

Nothing here types content. The script runs the converter over the unchanged text,
then:

1. sets the title and date the title page states, what it obsoletes, and its author;
2. removes the lead-in's blocks up to and including the contents page's footer
   (`August 13, 1982  - i -  RFC #822`), which is where the preface begins. Every
   block removed is checked against the title page's lines, so a converter change
   that moves the body's start makes the script fail rather than drop the body.

Usage:
  corpus/overrides/rfc822.py <corpus-build> corpus/text.noindex/rfc822.txt corpus/overrides/rfc822.xml
"""

import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

TITLE = "Standard for the Format of ARPA Internet Text Messages"
# The lead-in's first blocks, as the converter sets them: the title page, then the
# contents page's leftovers. The contents entries themselves are already dropped.
TITLE_PAGE = [
    "STANDARD FOR THE FORMAT OF",
    "ARPA INTERNET TEXT MESSAGES",
    "August 13, 1982",
    "Revised by",
    "David H. Crocker",
    "Dept. of Electrical Engineering",
    "APPENDIX",
    "August 13, 1982               - i -                      RFC #822",
]


def convert(corpus_build, source):
    with tempfile.TemporaryDirectory() as directory:
        inputs, target = pathlib.Path(directory, "in"), pathlib.Path(directory, "out")
        inputs.mkdir()
        inputs.joinpath("rfc822.txt").write_text(
            pathlib.Path(source).read_text(encoding="utf-8"), encoding="utf-8")
        subprocess.run([corpus_build, "convert", "--in", str(inputs), "--out", str(target)],
                       check=True, capture_output=True)
        return ET.fromstring(target.joinpath("rfc822.xml").read_text(encoding="utf-8"))


def correct_front(root):
    # The attribute order the converter writes: obsoletes before xml:lang.
    attributes = dict(root.attrib)
    root.attrib.clear()
    for name, value in attributes.items():
        if name.endswith("lang"):
            root.set("obsoletes", "733")
        root.set(name, value)
    front = root.find("front")
    front.find("title").text = TITLE
    author = front.find("author")
    author.attrib.clear()
    author.set("fullname", "D. Crocker")
    date = ET.Element("date", {"month": "August", "day": "13", "year": "1982"})
    front.insert(list(front).index(author) + 1, date)


def remove_title_page(root):
    preamble = root.find("middle/section[@anchor='preamble']")
    blocks = [child for child in preamble if child.tag != "name"]
    # In order; a line the converter already keeps out of the lead-in is skipped. The
    # address is one block of three lines, matched on its first.
    removed = 0
    for expected in TITLE_PAGE:
        text = (blocks[removed].text or "").strip()
        if text == expected or (text.startswith(expected) and "\n" in text):
            preamble.remove(blocks[removed])
            removed += 1
    first = (blocks[removed].text or "").strip()
    if first != "PREFACE":
        sys.exit(f"rfc822.py: expected the preface after the title page, found {first[:60]!r}")


def indent(element, level):
    """Re-indents the structural elements only; mixed content is left exactly as it was."""
    if element.tag not in ("rfc", "front", "middle", "back", "section") or len(element) == 0:
        return
    element.text = "\n" + "  " * (level + 1)
    for child in element:
        indent(child, level + 1)
        child.tail = "\n" + "  " * (level + 1)
    element[-1].tail = "\n" + "  " * level


def main():
    corpus_build, source, destination = sys.argv[1:4]
    root = convert(corpus_build, source)
    correct_front(root)
    remove_title_page(root)
    indent(root, 0)
    comment = ("Hand-corrected from rfc822.txt by corpus/overrides/rfc822.py: title, date, author "
               "and obsoletes set from the title page, and the title page removed from the body. "
               "The text is otherwise the converter's. Corrections: "
               "https://github.com/Radiergummi/rfc-reader")
    body = ET.tostring(root, encoding="unicode")
    pathlib.Path(destination).write_text(
        f"<?xml version='1.0' encoding='utf-8'?>\n<!-- {comment} -->\n{body}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
