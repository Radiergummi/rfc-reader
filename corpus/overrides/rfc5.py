#!/usr/bin/env python3
"""Regenerates rfc5.xml, the hand-corrected RFC 5 (issue #172).

RFC 5 carries an NLS editor command line under its title, and a line of its own text
directly after it:

    :DEL, 02/06/69 1010:58   JFR   ;   .DSN=1; .LSP=0; ['=] AND NOT SP ; ['?];
    dual transmission?

The converter keeps the command line as the lead-in's artwork, and takes `dual
transmission?` -- a column-0 line standing alone -- for a heading with nothing under
it. No other document has either shape, so this corrects the one document rather than
teaching the parser a rule.

Nothing here types content. The script runs the converter over the unchanged text,
then:

1. sets the title the RFC index gives, and the author and date of the header block,
   which the converter does not recognise (`Jeff Rulifson`, `June 2, l969` with a
   lower-case L for the 1);
2. removes the command line;
3. keeps `dual transmission?` as the lead-in's paragraph rather than a heading. What
   it refers to is not clear from the document, and dropping it would lose the only
   text on the page that is neither the header nor the editor's.

Usage:
  corpus/overrides/rfc5.py <corpus-build> corpus/text.noindex/rfc5.txt corpus/overrides/rfc5.xml
"""

import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

TITLE = "Decode Encode Language (DEL)"
COMMAND_LINE = ":DEL, 02/06/69 1010:58"
STRAY_LINE = "dual transmission?"


def convert(corpus_build, source):
    with tempfile.TemporaryDirectory() as directory:
        inputs, target = pathlib.Path(directory, "in"), pathlib.Path(directory, "out")
        inputs.mkdir()
        inputs.joinpath("rfc5.txt").write_text(
            pathlib.Path(source).read_text(encoding="utf-8"), encoding="utf-8")
        subprocess.run([corpus_build, "convert", "--in", str(inputs), "--out", str(target)],
                       check=True, capture_output=True)
        return ET.fromstring(target.joinpath("rfc5.xml").read_text(encoding="utf-8"))


def correct_front(root):
    front = root.find("front")
    front.find("title").text = TITLE
    author = front.find("author")
    author.attrib.clear()
    author.set("fullname", "J. Rulifson")
    if front.find("date") is None:
        date = ET.Element("date", {"month": "June", "day": "2", "year": "1969"})
        front.insert(list(front).index(author) + 1, date)


def correct_lead_in(root):
    middle = root.find("middle")
    preamble = middle.find("section[@anchor='preamble']")
    stray = middle.find("section[@anchor='name-dual-transmission']")
    if preamble is None or stray is None:
        sys.exit("rfc5.py: the converter no longer produces the lead-in this corrects")
    command = [child for child in preamble if child.tag == "artwork"]
    if len(command) != 1 or not (command[0].text or "").strip().startswith(COMMAND_LINE):
        sys.exit("rfc5.py: expected the lead-in to be the editor's command line alone")
    if stray.find("name").text != STRAY_LINE or len(stray) != 1:
        sys.exit(f"rfc5.py: expected an empty section named {STRAY_LINE!r}")
    preamble.remove(command[0])
    paragraph = ET.SubElement(preamble, "t")
    paragraph.text = STRAY_LINE
    middle.remove(stray)


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
    correct_lead_in(root)
    indent(root, 0)
    comment = ("Hand-corrected from rfc5.txt by corpus/overrides/rfc5.py: title, author and date "
               "set, the NLS editor's command line removed, and the line after it kept as a "
               "paragraph rather than a heading. The text is otherwise the converter's. "
               "Corrections: https://github.com/Radiergummi/rfc-reader")
    body = ET.tostring(root, encoding="unicode")
    pathlib.Path(destination).write_text(
        f"<?xml version='1.0' encoding='utf-8'?>\n<!-- {comment} -->\n{body}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
