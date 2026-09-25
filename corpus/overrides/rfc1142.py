#!/usr/bin/env python3
"""Regenerates rfc1142.xml, the hand-corrected RFC 1142 (issue #61).

RFC 1142 republishes ISO DP 10589 from a typeset original, and it is the only
legacy RFC whose form feeds are not page breaks: its 517 form feeds mark where
the typesetter changed font, most of them inside an identifier (`max` FF `i` FF
`mum` FF `Path` FF `Splits`). Its body also sits at column 0 with its numbered
headings run into the text, so the converter finds almost none of them.

Nothing here types content. The script corrects the source mechanically, runs
the converter over it, and demotes the headings the converter invents:

1. Every form feed is removed. Between a letter or digit and a letter it joins
   the fragments (`maximumPathSplits`, `originatingL1LSPBufferSize`); anywhere
   else it becomes a line break. A join the rest of the document spells
   differently is spelled its way (JOINED_SPELLINGS).
2. The numbered headings are found in order: a line at column 0 whose number
   follows the previous heading's (`7.2.9` -> `7.2.9.1` or `7.2.10` or `7.3`),
   and whose title, for a clause, opens as the contents list does. That keeps
   cross references (`7.2.9.1 for level 1 ...`) and list items (`1 Link State
   PDUs ...`) out. A title that wraps ends its line in a space, and its short
   continuation lines are joined to it. Each heading is set between blank
   lines, and `Annex X` is written `X Title` so it reads as appendix X.
3. corpus-build converts the corrected text.
4. Any section the converter found that is not one of those headings -- a
   table label standing alone between blank lines -- is demoted to a paragraph
   of the section before it, and the tree is nested again.

Needs Python 3.9 or later (str.removeprefix).

Usage:
  corpus/overrides/rfc1142.py <corpus-build> corpus/text.noindex/rfc1142.txt corpus/overrides/rfc1142.xml
"""

import pathlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

# The clause titles as the contents list gives them; a clause heading must open this way.
CLAUSES = {1: "Scope", 2: "References", 3: "Definitions", 4: "Symbols", 5: "Typographical",
           6: "Overview", 7: "Subnetwork Independent", 8: "Subnetwork Dependent", 9: "Structure",
           10: "System Environment", 11: "System Management", 12: "Conformance"}
ANNEXES = "ABCD"

# Joins that come out spelled otherwise than the rest of the document spells the word:
# `manual` FF `area` FF `Addresses` joins lowercase, where it is `manualAreaAddresses` elsewhere.
JOINED_SPELLINGS = {"manualareaAddresses": "manualAreaAddresses"}
# Headings whose line the extraction ran into the table beneath it: where the title ends.
TITLE_ENDS = {"9.10": "Numbers PDU", "A.4.1": "Implementation Identification",
              "A.4.2": "Protocol Summary: ISO 10589:19xx"}
# A heading line ending in a space whose next line is nevertheless the body.
NOT_WRAPPED = {"8.4.1.5"}
# The unnumbered sections the converter finds that are real.
# `Information technology` opens the standard's own title page, not a section, and is
# demoted with it into the Introduction. `ISO/IEC DIS 10589` is the same kind of line,
# but it heads the first thing the converter finds after the RFC's front matter -- the
# ISO title and the contents list -- and a demoted section needs one before it.
UNNUMBERED = {"ISO/IEC DIS 10589", "Introduction", "Security Considerations", "Author's Address"}

NUMBERED = re.compile(r"^(\d+(?:\.\d+)*|[A-D](?:\.\d+)+)\.?[ \t]+(\S.*)$")


def join_form_feeds(text):
    # One or more form feeds on lines of their own, with any whitespace-only lines around
    # them: `call` FF FF `Estab` is one break. The text neither opens nor ends with one,
    # so there is always a character on either side.
    separator = re.compile(r"\n(?:[ \t]*\n)*\f\n(?:[ \t]*\n|\f\n)*")

    def replace(match):
        before, after = text[match.start() - 1], text[match.end()]
        return "" if before.isalnum() and after.isalpha() else "\n"

    text = separator.sub(replace, text)
    for joined, spelling in JOINED_SPELLINGS.items():
        text = text.replace(joined, spelling)
    return text


def parts(number):
    return [ANNEXES.index(p) + 13 if p in ANNEXES else int(p) for p in number.split(".")]


def follows(previous, current):
    if previous is None:
        return current == [1]
    if current == previous + [1]:
        return True
    return any(current == previous[:k] + [previous[k] + 1] for k in range(len(previous)))


def is_continuation(line):
    stripped = line.strip()
    return (stripped and "\t" not in line and len(stripped.split()) <= 6
            and not re.search(r"[.:;]$", stripped) and not NUMBERED.match(line))


def mark_headings(text):
    """Returns the text with each heading on one line between blank lines, and the anchors."""
    lines = text.split("\n")
    found = []  # (line index, number, is annex)
    previous = None
    for index, line in enumerate(lines):
        annex = re.match(r"Annex ([A-D])\s*$", line)
        match = NUMBERED.match(line)
        if annex:
            number = annex.group(1)
        elif match:
            number = match.group(1)
            if "." not in number and not match.group(2).startswith(CLAUSES.get(int(number), "\0")):
                continue
        else:
            continue
        if follows(previous, parts(number)):
            previous = parts(number)
            found.append((index, number, bool(annex)))

    headings = {index: (number, annex) for index, number, annex in found}
    output, anchors, index = [], [], 0
    while index < len(lines):
        if index not in headings:
            output.append(lines[index])
            index += 1
            continue
        number, annex = headings[index]
        title = [lines[index]]
        index += 1
        while (number not in NOT_WRAPPED and title[-1] != title[-1].rstrip()
               and index not in headings and is_continuation(lines[index])):
            title.append(lines[index])
            index += 1
        heading = " ".join(part.strip() for part in title)
        rest = ""
        if number in TITLE_ENDS and TITLE_ENDS[number] not in heading:
            heading += " " + lines[index].strip()
            index += 1
        if number in TITLE_ENDS:
            end = heading.index(TITLE_ENDS[number]) + len(TITLE_ENDS[number])
            heading, rest = heading[:end], heading[end:]
        if annex:
            heading = f"{number} {heading.removeprefix(f'Annex {number}').strip()}"
        output += ["", heading, ""] + ([rest] if rest else [])
        anchors.append(f"section-{number}" if number[0].isdigit() else f"appendix-{number}")
    return "\n".join(output), anchors


def convert(corpus_build, text):
    with tempfile.TemporaryDirectory() as directory:
        source, target = pathlib.Path(directory, "in"), pathlib.Path(directory, "out")
        source.mkdir()
        source.joinpath("rfc1142.txt").write_text(text, encoding="utf-8")
        subprocess.run([corpus_build, "convert", "--in", str(source), "--out", str(target)],
                       check=True, capture_output=True)
        return target.joinpath("rfc1142.xml").read_text(encoding="utf-8")


def demote_invented_sections(xml, anchors):
    root = ET.fromstring(xml)
    keep = set(anchors)

    # Every section in document order, with its own blocks: a section's content precedes
    # its subsections, so a depth-first walk is reading order.
    flat = []

    def walk(section):
        name = section.find("name")
        blocks = [child for child in section if child.tag not in ("name", "section")]
        flat.append([section, name, blocks])
        for child in section.findall("section"):
            walk(child)

    containers = [root.find("middle"), root.find("back")]
    for container in containers:
        if container is not None:
            for section in container.findall("section"):
                walk(section)
                container.remove(section)

    # The first section is the ISO title block, which is kept, so a demoted one always
    # has a section before it.
    kept = []
    for section, name, blocks in flat:
        if section.get("anchor") in keep or "".join(name.itertext()) in UNNUMBERED:
            kept.append([section, name, blocks])
        else:
            paragraph = ET.Element("t")
            paragraph.text = "".join(name.itertext())
            kept[-1][2] += [paragraph] + blocks

    # Rebuild each section from its own blocks, then nest by depth as the parser does.
    def depth(section):
        return len(section.get("anchor").split("-", 1)[1].split(".")) if section.get("numbered") == "true" else 1

    roots, stack = [], []
    for section, name, blocks in kept:
        for child in list(section):
            section.remove(child)
        section.append(name)
        section.extend(blocks)
        while stack and depth(stack[-1]) >= depth(section):
            stack.pop()
        if stack:
            stack[-1].append(section)
        else:
            roots.append(section)
        stack.append(section)

    # The serializer's rule: everything from the first appendix on is the back.
    middle, back = root.find("middle"), root.find("back")
    if back is None:
        back = ET.SubElement(root, "back")
    for section in roots:
        if section.get("anchor").startswith("appendix-") or len(back):
            back.append(section)
        else:
            middle.append(section)

    # `anchor` and `pn` are both xsd:ID: where they agree, the part number alone is written,
    # as the published series does, and the parser reads the anchor back from it (#65, PR #86).
    for section in root.iter("section"):
        if section.get("anchor") == section.get("pn"):
            del section.attrib["anchor"]

    indent(root, 0)
    return root


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
    text = join_form_feeds(pathlib.Path(source).read_text(encoding="utf-8"))
    text, anchors = mark_headings(text)
    root = demote_invented_sections(convert(corpus_build, text), anchors)
    comment = ("Hand-corrected from rfc1142.txt by corpus/overrides/rfc1142.py: form feeds inside "
               "words joined, numbered headings recovered, invented headings demoted. The text is "
               "otherwise the converter's. Corrections: https://github.com/Radiergummi/rfc-reader")
    body = ET.tostring(root, encoding="unicode")
    pathlib.Path(destination).write_text(
        f"<?xml version='1.0' encoding='utf-8'?>\n<!-- {comment} -->\n{body}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
